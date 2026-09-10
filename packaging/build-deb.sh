#!/usr/bin/env bash

# Assembles a .deb for the Revaulter server from an already-built linux binary
# Invoked by `make deb`; can also be run directly
#
# Usage:
#   packaging/build-deb.sh <version> <arch> <binary-path> <out-dir> [maintainer] [commit]

set -euo pipefail

version="${1:?version required}"
arch="${2:?arch required}"
binary="${3:?path to the revaulter binary required}"
out_dir="${4:?output directory required}"
maintainer="${5:-Revaulter packager <root@localhost>}"
commit="${6:-unknown}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "${binary}" ]]; then
  echo "Error: binary not found or not executable: ${binary}" >&2
  exit 1
fi

pkg="revaulter"
# Debian versions may not contain '-' outside the debian-revision; use '~' for pre-release separators
deb_version="${version//-/\~}"
stage="${out_dir}/deb/${pkg}_${deb_version}_${arch}"

echo "### Building ${pkg}_${deb_version}_${arch}.deb"

rm -rf "${stage}"
mkdir -p \
  "${stage}/DEBIAN" \
  "${stage}/usr/bin" \
  "${stage}/etc/revaulter" \
  "${stage}/lib/systemd/system" \
  "${stage}/usr/share/doc/${pkg}"

install -m 0755 "${binary}"                                  "${stage}/usr/bin/revaulter"
install -m 0640 "${repo_root}/packaging/config.yaml"         "${stage}/etc/revaulter/config.yaml"
install -m 0644 "${repo_root}/packaging/systemd/revaulter.service" "${stage}/lib/systemd/system/revaulter.service"
install -m 0644 "${repo_root}/config.sample.yaml"            "${stage}/usr/share/doc/${pkg}/config.sample.yaml"

installed_size="$(du -k -s "${stage}/usr" | cut -f1)"

cat > "${stage}/DEBIAN/control" <<EOF
Package: ${pkg}
Version: ${deb_version}
Architecture: ${arch}
Maintainer: ${maintainer}
Installed-Size: ${installed_size}
Section: utils
Priority: optional
Depends: adduser, systemd
Homepage: https://github.com/ItalyPaleAle/revaulter
Description: Unseal secrets with WebAuthn approval
 Revaulter is a self-hosted service to encrypt and decrypt secrets, with each
 operation gated behind an explicit WebAuthn / passkey approval.
 .
 Built from commit ${commit}.
EOF

cat > "${stage}/DEBIAN/conffiles" <<EOF
/etc/revaulter/config.yaml
EOF

cat > "${stage}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

case "$1" in
  configure)
    if ! getent group revaulter >/dev/null; then
      addgroup --system revaulter
    fi
    if ! getent passwd revaulter >/dev/null; then
      adduser --system --ingroup revaulter --home /var/lib/revaulter \
        --no-create-home --gecos "Revaulter service" --disabled-login revaulter
    fi

    mkdir -p /var/lib/revaulter
    chown revaulter:revaulter /var/lib/revaulter
    chmod 0750 /var/lib/revaulter

    chown root:revaulter /etc/revaulter/config.yaml || true
    chmod 0640 /etc/revaulter/config.yaml || true

    if [ -d /run/systemd/system ]; then
      systemctl daemon-reload || true
      systemctl enable revaulter.service || true
    fi

    if grep -q 'CHANGE_ME' /etc/revaulter/config.yaml 2>/dev/null; then
      echo
      echo "Revaulter installed. Before starting the service:"
      echo "  1. edit /etc/revaulter/config.yaml (set secretKey, sessionSigningKey, baseUrl)"
      echo "     generate secrets with: openssl rand -base64 32"
      echo "  2. systemctl start revaulter"
      echo
    fi
    ;;
esac

exit 0
EOF

cat > "${stage}/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = remove ] || [ "$1" = deconfigure ]; then
  if [ -d /run/systemd/system ]; then
    systemctl stop revaulter.service || true
  fi
fi

exit 0
EOF

cat > "${stage}/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e

case "$1" in
  remove)
    if [ -d /run/systemd/system ]; then
      systemctl daemon-reload || true
    fi
    ;;
  purge)
    if [ -d /run/systemd/system ]; then
      systemctl disable revaulter.service || true
      systemctl daemon-reload || true
    fi
    rm -rf /etc/revaulter /var/lib/revaulter
    if getent passwd revaulter >/dev/null; then
      deluser --system revaulter || true
    fi
    if getent group revaulter >/dev/null; then
      delgroup --system revaulter || true
    fi
    ;;
esac

exit 0
EOF

chmod 0755 "${stage}/DEBIAN/postinst" "${stage}/DEBIAN/prerm" "${stage}/DEBIAN/postrm"

dpkg-deb --root-owner-group --build "${stage}" "${out_dir}/${pkg}_${deb_version}_${arch}.deb"

echo "-> ${out_dir}/${pkg}_${deb_version}_${arch}.deb"
dpkg-deb --info "${out_dir}/${pkg}_${deb_version}_${arch}.deb"
