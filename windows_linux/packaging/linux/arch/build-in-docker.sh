#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
host_uid="${SUDO_UID:-$(id -u)}"
host_gid="${SUDO_GID:-$(id -g)}"

if [[ "${host_uid}" -eq 0 ]]; then
  echo "Host UID resolved to root. Run this script from a non-root user shell." >&2
  exit 1
fi

docker run --rm \
  -e HOST_UID="${host_uid}" \
  -e HOST_GID="${host_gid}" \
  -v "${repo_root}:/workspace" \
  -w /workspace/packaging/linux/arch \
  archlinux:latest \
  bash -lc '
    set -euo pipefail

    pacman -Syu --noconfirm --needed base-devel dotnet-sdk git sudo libevdev systemd systemd-sysvcompat

    if ! getent group "${HOST_GID}" >/dev/null; then
      groupadd --gid "${HOST_GID}" hostgroup
    fi

    build_user="$(getent passwd "${HOST_UID}" | cut -d: -f1 || true)"
    if [[ -z "${build_user}" ]]; then
      build_user=builder
      useradd --create-home --uid "${HOST_UID}" --gid "${HOST_GID}" "${build_user}"
    fi

    sudo -u "${build_user}" bash -lc "cd /workspace/packaging/linux/arch && makepkg -f --noconfirm"
  '
