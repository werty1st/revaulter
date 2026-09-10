#!/usr/bin/env bash

# Installs revaulter-cli + the ZFS boot-unlock helpers from this bundle
# (the .deb from `make cli-deb` is the preferred path; this is the tarball equivalent)

set -euo pipefail

CONF_DIR=/etc/revaulter/cli
KEY_DIR=/etc/revaulter/keys
UNIT_DEST=/lib/systemd/system/revaulter-zfs-unlock@.service

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root" >&2
  exit 1
fi

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

install -m 0755 revaulter-cli        /usr/bin/revaulter-cli
install -m 0755 revaulter-zfs-unlock /usr/bin/revaulter-zfs-unlock
install -m 0755 revaulter-zfs-setup  /usr/bin/revaulter-zfs-setup
install -m 0644 revaulter-zfs-unlock@.service "${UNIT_DEST}"

install -d -m 0700 "${CONF_DIR}" "${KEY_DIR}"
if [ ! -e "${CONF_DIR}/config" ]; then
  install -m 0600 config "${CONF_DIR}/config"
  echo "Installed default config to ${CONF_DIR}/config"
fi

systemctl daemon-reload

echo
echo "Done. Next:"
echo "  1. edit ${CONF_DIR}/config (REVAULTER_SERVER, REVAULTER_REQUEST_KEY)"
echo "  2. per dataset: revaulter-zfs-setup [--create] <pool/dataset>"
