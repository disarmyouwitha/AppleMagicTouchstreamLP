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
LAUNCHER_MODE="wrapper"
SERVICE_MODE="none"
SERVICE_USER="${SUDO_USER:-}"
SERVICE_NAME="glasstokey-linux"
EXECUTABLE_NAME="GlassToKey.Linux"

usage() {
  cat <<EOF
Usage:
  sudo ./packaging/linux/install.sh [options]

Options:
  --publish-dir <path>     Publish output to install.
  --install-dir <path>     Target installation directory. Default: ${INSTALL_DIR}
  --rule-source <path>     udev rules file to install.
  --bin-name <name>        Wrapper command name. Default: ${BIN_NAME}
  --launcher-mode <mode>   wrapper | none. Default: ${LAUNCHER_MODE}
  --service-mode <mode>    user | none. Default: ${SERVICE_MODE}
  --service-user <user>    Target user for a user systemd service. Default: \$SUDO_USER
  --service-name <name>    Service file basename. Default: ${SERVICE_NAME}
  --help                   Show this help.
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This install script writes to system locations and must be run with sudo." >&2
    exit 1
  fi
}

resolve_user_home() {
  getent passwd "$1" | cut -d: -f6
}

install_wrapper() {
  cat > "${BIN_DEST}" <<EOF
#!/usr/bin/env bash
exec "${INSTALL_DIR}/${EXECUTABLE_NAME}" "\$@"
EOF
  chmod 0755 "${BIN_DEST}"
}

install_user_service() {
  if [ -z "${SERVICE_USER}" ]; then
    echo "User service mode requires --service-user or running under sudo so SUDO_USER is available." >&2
    exit 1
  fi

  local user_home
  user_home="$(resolve_user_home "${SERVICE_USER}")"
  if [ -z "${user_home}" ] || [ ! -d "${user_home}" ]; then
    echo "Could not resolve home directory for service user '${SERVICE_USER}'." >&2
    exit 1
  fi

  local service_dir="${user_home}/.config/systemd/user"
  local service_path="${service_dir}/${SERVICE_NAME}.service"
  mkdir -p "${service_dir}"

  cat > "${service_path}" <<EOF
[Unit]
Description=GlassToKey Linux runtime
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${EXECUTABLE_NAME} run-engine
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

  chown -R "${SERVICE_USER}:${SERVICE_USER}" "${service_dir}"
  echo "${service_path}"
}

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
    --launcher-mode)
      LAUNCHER_MODE="$2"
      shift 2
      ;;
    --service-mode)
      SERVICE_MODE="$2"
      shift 2
      ;;
    --service-user)
      SERVICE_USER="$2"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="$2"
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

require_root

case "${LAUNCHER_MODE}" in
  wrapper|none)
    ;;
  *)
    echo "Unsupported launcher mode: ${LAUNCHER_MODE}" >&2
    exit 1
    ;;
esac

case "${SERVICE_MODE}" in
  user|none)
    ;;
  *)
    echo "Unsupported service mode: ${SERVICE_MODE}" >&2
    exit 1
    ;;
esac

if [ ! -d "${PUBLISH_DIR}" ]; then
  echo "Publish directory not found: ${PUBLISH_DIR}" >&2
  echo "Build it first with:" >&2
  echo "  dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained" >&2
  exit 1
fi

if [ ! -f "${PUBLISH_DIR}/${EXECUTABLE_NAME}" ]; then
  echo "Expected executable not found in publish directory: ${PUBLISH_DIR}/${EXECUTABLE_NAME}" >&2
  exit 1
fi

if [ ! -f "${RULE_SOURCE}" ]; then
  echo "udev rule file not found: ${RULE_SOURCE}" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"
cp -a "${PUBLISH_DIR}/." "${INSTALL_DIR}/"
install -m 0644 "${RULE_SOURCE}" "${RULE_DEST}"

if [ "${LAUNCHER_MODE}" = "wrapper" ]; then
  install_wrapper
fi

SERVICE_PATH=""
if [ "${SERVICE_MODE}" = "user" ]; then
  SERVICE_PATH="$(install_user_service)"
fi

udevadm control --reload-rules
udevadm trigger

echo "Installed GlassToKey.Linux to ${INSTALL_DIR}"
echo "udev rules installed to ${RULE_DEST}"
if [ "${LAUNCHER_MODE}" = "wrapper" ]; then
  echo "Wrapper command: ${BIN_DEST}"
fi
if [ -n "${SERVICE_PATH}" ]; then
  echo "User service installed to ${SERVICE_PATH}"
fi
echo
echo "Post-install guidance:"
echo "  1. Reconnect the trackpads or wait a few seconds for the refreshed udev permissions to apply."
if [ "${LAUNCHER_MODE}" = "wrapper" ]; then
  echo "  2. Run '${BIN_NAME} doctor'"
  echo "  3. Run '${BIN_NAME} init-config' if this is the first install"
  echo "  4. Run '${BIN_NAME} show-config' and confirm left/right device bindings"
  echo "  5. Run '${BIN_NAME} run-engine 10' for a live smoke test"
else
  echo "  2. Run '${INSTALL_DIR}/${EXECUTABLE_NAME} doctor'"
  echo "  3. Run '${INSTALL_DIR}/${EXECUTABLE_NAME} init-config' if this is the first install"
  echo "  4. Run '${INSTALL_DIR}/${EXECUTABLE_NAME} show-config' and confirm left/right device bindings"
  echo "  5. Run '${INSTALL_DIR}/${EXECUTABLE_NAME} run-engine 10' for a live smoke test"
fi

if [ -n "${SERVICE_PATH}" ]; then
  echo
  echo "User service enable/start commands for ${SERVICE_USER}:"
  echo "  sudo -u ${SERVICE_USER} systemctl --user daemon-reload"
  echo "  sudo -u ${SERVICE_USER} systemctl --user enable --now ${SERVICE_NAME}.service"
  echo "  sudo -u ${SERVICE_USER} journalctl --user -u ${SERVICE_NAME}.service -f"
  echo
  echo "If your sudo environment does not expose the user session bus, run those three commands after logging in as ${SERVICE_USER}."
fi
