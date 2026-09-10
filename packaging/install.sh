#!/usr/bin/env bash

# Installs the Revaulter server from this bundle onto a systemd host
# (the .deb from `make deb` is the preferred path; this is the tarball equivalent)

set -euo pipefail

BIN_DEST=/usr/bin/revaulter
CONF_DIR=/etc/revaulter
DATA_DIR=/var/lib/revaulter
UNIT_DEST=/lib/systemd/system/revaulter.service

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root" >&2
  exit 1
fi

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

if ! getent group revaulter >/dev/null; then
  groupadd --system revaulter
fi
if ! getent passwd revaulter >/dev/null; then
  useradd --system --gid revaulter --home-dir "${DATA_DIR}" \
    --no-create-home --shell /usr/sbin/nologin revaulter
fi

install -m 0755 revaulter "${BIN_DEST}"
install -d -m 0750 -o revaulter -g revaulter "${DATA_DIR}"
install -d -m 0755 "${CONF_DIR}"

if [ ! -e "${CONF_DIR}/config.yaml" ]; then
  install -m 0640 -o root -g revaulter config.yaml "${CONF_DIR}/config.yaml"
  echo "Installed default config to ${CONF_DIR}/config.yaml"
fi
install -m 0644 config.sample.yaml "${CONF_DIR}/config.sample.yaml"
install -m 0644 revaulter.service "${UNIT_DEST}"

systemctl daemon-reload

echo
echo "Done. Next:"
echo "  1. edit ${CONF_DIR}/config.yaml (secretKey, sessionSigningKey, baseUrl)"
echo "     generate secrets with: openssl rand -base64 32"
echo "  2. systemctl enable --now revaulter"
