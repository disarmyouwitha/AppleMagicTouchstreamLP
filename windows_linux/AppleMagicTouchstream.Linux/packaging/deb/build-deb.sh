#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

PACKAGE_NAME="applemagictouchstream-linux"
PACKAGE_VERSION="0.1.0"
ARCH="amd64"
CLI_PUBLISH_DIR="${REPO_ROOT}/AppleMagicTouchstream.Linux/bin/Release/net10.0/publish/linux-x64-self-contained"
GUI_PUBLISH_DIR="${REPO_ROOT}/AppleMagicTouchstream.Linux/Gui/bin/Release/net10.0/publish/linux-x64-self-contained"
OUTPUT_DIR="${SCRIPT_DIR}/out"
SKIP_PUBLISH="no"
RULE_SOURCE="${REPO_ROOT}/AppleMagicTouchstream.Linux/packaging/90-applemagictouchstream.rules"
CONTROL_TEMPLATE="${SCRIPT_DIR}/DEBIAN/control.in"
POSTINST_TEMPLATE="${SCRIPT_DIR}/DEBIAN/postinst"
PRERM_TEMPLATE="${SCRIPT_DIR}/DEBIAN/prerm"
DESKTOP_TEMPLATE="${SCRIPT_DIR}/usr/share/applications/applemagictouchstream.desktop.in"

usage() {
  cat <<EOF
Usage:
  ./AppleMagicTouchstream.Linux/packaging/deb/build-deb.sh [options]

Options:
  --version <version>           Debian package version. Default: ${PACKAGE_VERSION}
  --arch <arch>                 Debian architecture. Default: ${ARCH}
  --package-name <name>         Debian package name. Default: ${PACKAGE_NAME}
  --cli-publish-dir <path>      Self-contained CLI publish output.
  --gui-publish-dir <path>      Optional GUI publish output. If absent, GUI launcher is skipped.
  --output-dir <path>           Directory for built .deb output.
  --skip-publish                Skip running dotnet publish before packaging.
  --help                        Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      PACKAGE_VERSION="$2"
      shift 2
      ;;
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --package-name)
      PACKAGE_NAME="$2"
      shift 2
      ;;
    --cli-publish-dir)
      CLI_PUBLISH_DIR="$2"
      shift 2
      ;;
    --gui-publish-dir)
      GUI_PUBLISH_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-publish)
      SKIP_PUBLISH="yes"
      shift 1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "dpkg-deb is required to build the Debian package." >&2
  exit 1
fi

if [ "${SKIP_PUBLISH}" != "yes" ]; then
  if ! command -v dotnet >/dev/null 2>&1; then
    echo "dotnet is required to publish before packaging. Use --skip-publish to bypass this step." >&2
    exit 1
  fi

  dotnet publish "${REPO_ROOT}/AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj" -c Release -p:PublishProfile=LinuxSelfContained
  dotnet publish "${REPO_ROOT}/AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj" -c Release -p:PublishProfile=LinuxGuiSelfContained
fi

if [ ! -d "${CLI_PUBLISH_DIR}" ] || [ ! -f "${CLI_PUBLISH_DIR}/AppleMagicTouchstream.Linux" ]; then
  echo "CLI publish output not found: ${CLI_PUBLISH_DIR}" >&2
  echo "Build it first with:" >&2
  echo "  dotnet publish AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained" >&2
  exit 1
fi

if [ ! -f "${RULE_SOURCE}" ]; then
  echo "udev rules file not found: ${RULE_SOURCE}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
BUILD_ROOT="$(mktemp -d "${OUTPUT_DIR}/pkg.XXXXXX")"
PACKAGE_ROOT="${BUILD_ROOT}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}"

cleanup() {
  rm -rf "${BUILD_ROOT}"
}
trap cleanup EXIT

mkdir -p \
  "${PACKAGE_ROOT}/DEBIAN" \
  "${PACKAGE_ROOT}/opt/AppleMagicTouchstream.Linux" \
  "${PACKAGE_ROOT}/etc/udev/rules.d" \
  "${PACKAGE_ROOT}/usr/bin" \
  "${PACKAGE_ROOT}/usr/lib/systemd/user" \
  "${PACKAGE_ROOT}/usr/share/applications"

cp -a "${CLI_PUBLISH_DIR}/." "${PACKAGE_ROOT}/opt/AppleMagicTouchstream.Linux/"
install -m 0644 "${RULE_SOURCE}" "${PACKAGE_ROOT}/etc/udev/rules.d/90-applemagictouchstream.rules"
install -m 0755 "${POSTINST_TEMPLATE}" "${PACKAGE_ROOT}/DEBIAN/postinst"
install -m 0755 "${PRERM_TEMPLATE}" "${PACKAGE_ROOT}/DEBIAN/prerm"

sed \
  -e "s/@PACKAGE_NAME@/${PACKAGE_NAME}/g" \
  -e "s/@PACKAGE_VERSION@/${PACKAGE_VERSION}/g" \
  -e "s/@ARCH@/${ARCH}/g" \
  "${CONTROL_TEMPLATE}" > "${PACKAGE_ROOT}/DEBIAN/control"

cat > "${PACKAGE_ROOT}/usr/bin/applemagictouchstream" <<'EOF'
#!/usr/bin/env bash
exec /opt/AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux "$@"
EOF
chmod 0755 "${PACKAGE_ROOT}/usr/bin/applemagictouchstream"

cat > "${PACKAGE_ROOT}/usr/lib/systemd/user/applemagictouchstream.service" <<'EOF'
[Unit]
Description=AppleMagicTouchstream Linux runtime
After=graphical-session.target

[Service]
Type=simple
WorkingDirectory=/opt/AppleMagicTouchstream.Linux
ExecStart=/opt/AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux run-engine
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

if [ -d "${GUI_PUBLISH_DIR}" ] && [ -f "${GUI_PUBLISH_DIR}/AppleMagicTouchstream.Linux.Gui" ]; then
  mkdir -p "${PACKAGE_ROOT}/opt/AppleMagicTouchstream.Linux.Gui"
  cp -a "${GUI_PUBLISH_DIR}/." "${PACKAGE_ROOT}/opt/AppleMagicTouchstream.Linux.Gui/"
  cat > "${PACKAGE_ROOT}/usr/bin/applemagictouchstream-gui" <<'EOF'
#!/usr/bin/env bash
set -eu

START_MODE="--background"

if [ "${1:-}" = "--foreground" ]; then
  shift
  exec /opt/AppleMagicTouchstream.Linux.Gui/AppleMagicTouchstream.Linux.Gui "$@"
fi

if [ "${1:-}" = "--show" ]; then
  START_MODE="--show"
  shift
fi

if command -v setsid >/dev/null 2>&1; then
  setsid /opt/AppleMagicTouchstream.Linux.Gui/AppleMagicTouchstream.Linux.Gui "${START_MODE}" "$@" </dev/null >/dev/null 2>&1 &
else
  /opt/AppleMagicTouchstream.Linux.Gui/AppleMagicTouchstream.Linux.Gui "${START_MODE}" "$@" </dev/null >/dev/null 2>&1 &
fi
EOF
  chmod 0755 "${PACKAGE_ROOT}/usr/bin/applemagictouchstream-gui"
  sed -e "s/@GUI_EXEC@/applemagictouchstream-gui/g" "${DESKTOP_TEMPLATE}" > "${PACKAGE_ROOT}/usr/share/applications/applemagictouchstream.desktop"
fi

dpkg-deb --build --root-owner-group "${PACKAGE_ROOT}" >/dev/null
FINAL_PACKAGE="${OUTPUT_DIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"
mv "${PACKAGE_ROOT}.deb" "${FINAL_PACKAGE}"
echo "Built Debian package: ${FINAL_PACKAGE}"
