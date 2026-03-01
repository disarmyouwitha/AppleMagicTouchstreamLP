#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PUBLISH_DIR="${REPO_ROOT}/GlassToKey.Linux/bin/Release/net10.0/publish/linux-x64-self-contained"
INSTALL_DIR="/opt/GlassToKey.Linux"
RULE_SOURCE="${SCRIPT_DIR}/90-glasstokey.rules"
RULE_DEST="/etc/udev/rules.d/90-glasstokey.rules"
BIN_NAME="glasstokey-linux"
BIN_DEST="/usr/local/bin/${BIN_NAME}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --publish-dir)
      PUBLISH_DIR="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --rule-source)
      RULE_SOURCE="$2"
      shift 2
      ;;
    --bin-name)
      BIN_NAME="$2"
      BIN_DEST="/usr/local/bin/${BIN_NAME}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "${PUBLISH_DIR}" ]; then
  echo "Publish directory not found: ${PUBLISH_DIR}" >&2
  echo "Build it first with:" >&2
  echo "  dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained" >&2
  exit 1
fi

if [ ! -f "${RULE_SOURCE}" ]; then
  echo "udev rule file not found: ${RULE_SOURCE}" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"
cp -a "${PUBLISH_DIR}/." "${INSTALL_DIR}/"
install -m 0644 "${RULE_SOURCE}" "${RULE_DEST}"

cat > "${BIN_DEST}" <<EOF
#!/usr/bin/env bash
exec "${INSTALL_DIR}/GlassToKey.Linux" "\$@"
EOF
chmod 0755 "${BIN_DEST}"

udevadm control --reload-rules
udevadm trigger

echo "Installed GlassToKey.Linux to ${INSTALL_DIR}"
echo "Wrapper command: ${BIN_DEST}"
echo "udev rules installed to ${RULE_DEST}"
echo
echo "Next steps:"
echo "  1. Run '${BIN_NAME} doctor'"
echo "  2. Run '${BIN_NAME} init-config' if this is the first install"
echo "  3. Run '${BIN_NAME} run-engine 10' for a live smoke test"
