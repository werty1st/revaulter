#!/usr/bin/env bash

# Assembles the revaulter-cli .deb (CLI + ZFS boot-unlock scaffolding) from an
# already-built revaulter-cli binary
# Invoked by `make cli-deb`; can also be run directly
#
# Usage:
#   packaging/build-cli-deb.sh <version> <arch> <cli-binary-path> <out-dir> [maintainer] [commit]

set -euo pipefail

version="${1:?version required}"
arch="${2:?arch required}"
binary="${3:?path to the revaulter-cli binary required}"
out_dir="${4:?output directory required}"
maintainer="${5:-Revaulter packager <root@localhost>}"
commit="${6:-unknown}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "${binary}" ]]; then
  echo "Error: binary not found or not executable: ${binary}" >&2
  exit 1
fi

pkg="revaulter-cli"
deb_version="${version//-/\~}"
stage="${out_dir}/deb/${pkg}_${deb_version}_${arch}"

echo "### Building ${pkg}_${deb_version}_${arch}.deb"

rm -rf "${stage}"
mkdir -p \
  "${stage}/DEBIAN" \
  "${stage}/usr/bin" \
  "${stage}/etc/revaulter/cli" \
  "${stage}/lib/systemd/system" \
  "${stage}/usr/share/doc/${pkg}"

install -m 0755 "${binary}"                                        "${stage}/usr/bin/revaulter-cli"
install -m 0755 "${repo_root}/packaging/cli/revaulter-zfs-unlock"  "${stage}/usr/bin/revaulter-zfs-unlock"
install -m 0755 "${repo_root}/packaging/cli/revaulter-zfs-setup"   "${stage}/usr/bin/revaulter-zfs-setup"
install -m 0640 "${repo_root}/packaging/cli/config"                "${stage}/etc/revaulter/cli/config"
install -m 0644 "${repo_root}/packaging/cli/revaulter-zfs-unlock@.service" \
                                                                  "${stage}/lib/systemd/system/revaulter-zfs-unlock@.service"
install -m 0644 "${repo_root}/packaging/cli/README.md" \
                                                                  "${stage}/usr/share/doc/${pkg}/README.md"

installed_size="$(du -k -s "${stage}/usr" | cut -f1)"

cat > "${stage}/DEBIAN/control" <<EOF
Package: ${pkg}
Version: ${deb_version}
Architecture: ${arch}
Maintainer: ${maintainer}
Installed-Size: ${installed_size}
Section: utils
Priority: optional
Depends: curl, openssl, systemd
Recommends: zfsutils-linux
Homepage: https://github.com/ItalyPaleAle/revaulter
Description: Revaulter CLI and ZFS boot-unlock helper
 revaulter-cli talks to a Revaulter v2 server to encrypt, decrypt and sign data,
 each operation gated behind a WebAuthn / passkey approval.
 .
 This package also ships revaulter-zfs-setup / revaulter-zfs-unlock and a
 templated systemd unit (revaulter-zfs-unlock@.service) that unwraps a ZFS
 dataset passphrase via Revaulter at boot and pipes it straight into
 "zfs load-key". The server URL is pre-configured; only the request key is
 filled in per host.
 .
 Built from commit ${commit}.
EOF

cat > "${stage}/DEBIAN/conffiles" <<EOF
/etc/revaulter/cli/config
EOF

cat > "${stage}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

case "$1" in
  configure)
    mkdir -p /etc/revaulter/cli /etc/revaulter/keys
    chmod 0700 /etc/revaulter/cli /etc/revaulter/keys
    chmod 0600 /etc/revaulter/cli/config || true

    if [ -d /run/systemd/system ]; then
      systemctl daemon-reload || true
    fi

    if grep -q '^REVAULTER_REQUEST_KEY=""' /etc/revaulter/cli/config 2>/dev/null; then
      echo
      echo "revaulter-cli installed. Next:"
      echo "  1. put your request key in /etc/revaulter/cli/config (REVAULTER_REQUEST_KEY)"
      echo "  2. per dataset: revaulter-zfs-setup <pool/dataset>"
      echo
    fi
    ;;
esac

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
    rm -rf /etc/revaulter/cli /etc/revaulter/keys
    rmdir /etc/revaulter 2>/dev/null || true
    ;;
esac

exit 0
EOF

chmod 0755 "${stage}/DEBIAN/postinst" "${stage}/DEBIAN/postrm"

dpkg-deb --root-owner-group --build "${stage}" "${out_dir}/${pkg}_${deb_version}_${arch}.deb"

echo "-> ${out_dir}/${pkg}_${deb_version}_${arch}.deb"
dpkg-deb --info "${out_dir}/${pkg}_${deb_version}_${arch}.deb"
