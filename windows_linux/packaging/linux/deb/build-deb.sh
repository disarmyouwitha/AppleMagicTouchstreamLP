#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

PACKAGE_NAME="glasstokey-linux"
PACKAGE_VERSION="0.1.0"
ARCH="amd64"
CLI_PUBLISH_DIR="${REPO_ROOT}/GlassToKey.Linux/bin/Release/net10.0/publish/linux-x64-self-contained"
GUI_PUBLISH_DIR="${REPO_ROOT}/GlassToKey.Linux.Gui/bin/Release/net10.0/publish/linux-x64-self-contained"
OUTPUT_DIR="${SCRIPT_DIR}/out"
RULE_SOURCE="${REPO_ROOT}/packaging/linux/90-glasstokey.rules"
CONTROL_TEMPLATE="${SCRIPT_DIR}/DEBIAN/control.in"
POSTINST_TEMPLATE="${SCRIPT_DIR}/DEBIAN/postinst"
PRERM_TEMPLATE="${SCRIPT_DIR}/DEBIAN/prerm"
DESKTOP_TEMPLATE="${SCRIPT_DIR}/usr/share/applications/glasstokey.desktop.in"

usage() {
  cat <<EOF
Usage:
  ./packaging/linux/deb/build-deb.sh [options]

Options:
  --version <version>           Debian package version. Default: ${PACKAGE_VERSION}
  --arch <arch>                 Debian architecture. Default: ${ARCH}
  --package-name <name>         Debian package name. Default: ${PACKAGE_NAME}
  --cli-publish-dir <path>      Self-contained CLI publish output.
  --gui-publish-dir <path>      Optional GUI publish output. If absent, GUI launcher is skipped.
  --output-dir <path>           Directory for built .deb output.
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

if [ ! -d "${CLI_PUBLISH_DIR}" ] || [ ! -f "${CLI_PUBLISH_DIR}/GlassToKey.Linux" ]; then
  echo "CLI publish output not found: ${CLI_PUBLISH_DIR}" >&2
  echo "Build it first with:" >&2
  echo "  dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained" >&2
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
  "${PACKAGE_ROOT}/opt/GlassToKey.Linux" \
  "${PACKAGE_ROOT}/etc/udev/rules.d" \
  "${PACKAGE_ROOT}/usr/bin" \
  "${PACKAGE_ROOT}/usr/lib/systemd/user" \
  "${PACKAGE_ROOT}/usr/share/applications"

cp -a "${CLI_PUBLISH_DIR}/." "${PACKAGE_ROOT}/opt/GlassToKey.Linux/"
install -m 0644 "${RULE_SOURCE}" "${PACKAGE_ROOT}/etc/udev/rules.d/90-glasstokey.rules"
install -m 0755 "${POSTINST_TEMPLATE}" "${PACKAGE_ROOT}/DEBIAN/postinst"
install -m 0755 "${PRERM_TEMPLATE}" "${PACKAGE_ROOT}/DEBIAN/prerm"

sed \
  -e "s/@PACKAGE_NAME@/${PACKAGE_NAME}/g" \
  -e "s/@PACKAGE_VERSION@/${PACKAGE_VERSION}/g" \
  -e "s/@ARCH@/${ARCH}/g" \
  "${CONTROL_TEMPLATE}" > "${PACKAGE_ROOT}/DEBIAN/control"

cat > "${PACKAGE_ROOT}/usr/bin/glasstokey" <<'EOF'
#!/usr/bin/env bash
exec /opt/GlassToKey.Linux/GlassToKey.Linux "$@"
EOF
chmod 0755 "${PACKAGE_ROOT}/usr/bin/glasstokey"

cat > "${PACKAGE_ROOT}/usr/lib/systemd/user/glasstokey.service" <<'EOF'
[Unit]
Description=GlassToKey Linux runtime
After=graphical-session.target

[Service]
Type=simple
WorkingDirectory=/opt/GlassToKey.Linux
ExecStart=/opt/GlassToKey.Linux/GlassToKey.Linux run-engine
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

if [ -d "${GUI_PUBLISH_DIR}" ] && [ -f "${GUI_PUBLISH_DIR}/GlassToKey.Linux.Gui" ]; then
  mkdir -p "${PACKAGE_ROOT}/opt/GlassToKey.Linux.Gui"
  cp -a "${GUI_PUBLISH_DIR}/." "${PACKAGE_ROOT}/opt/GlassToKey.Linux.Gui/"
  cat > "${PACKAGE_ROOT}/usr/bin/glasstokey-gui" <<'EOF'
#!/usr/bin/env bash
exec /opt/GlassToKey.Linux.Gui/GlassToKey.Linux.Gui "$@"
EOF
  chmod 0755 "${PACKAGE_ROOT}/usr/bin/glasstokey-gui"
  sed -e "s/@GUI_EXEC@/glasstokey-gui/g" "${DESKTOP_TEMPLATE}" > "${PACKAGE_ROOT}/usr/share/applications/glasstokey.desktop"
fi

dpkg-deb --build --root-owner-group "${PACKAGE_ROOT}" >/dev/null
FINAL_PACKAGE="${OUTPUT_DIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"
mv "${PACKAGE_ROOT}.deb" "${FINAL_PACKAGE}"
echo "Built Debian package: ${FINAL_PACKAGE}"
