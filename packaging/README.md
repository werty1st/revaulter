# Packaging / self-hosting

All builds run inside Docker (BuildKit); the host only needs `docker` (the .deb is
assembled inside the build container). No Go / Node / pnpm toolchain required.

Two independent deliverables:

| Where | What runs | Build target |
|-------|-----------|--------------|
| The compose host (arm64) | the **Revaulter server** container | `make image ARCH=arm64` |
| The ZFS host (amd64) | **`revaulter-cli`** + the ZFS boot-unlock service | `apt install` the .deb the image serves |

The server `.deb` / `bundle` targets are commented out in the `Makefile` - the
server only ever runs as a container here.

## The build (`packaging/Dockerfile`)

Multi-stage:

1. `webbuild` - Node 24 + pnpm, builds the Svelte client into `client/web/dist`
2. `gobase` - Go 1.27 base with modules downloaded (CGO off, pure-Go SQLite)
3. `gobuild-cli` - builds `./cmd/cli` (no web client, no Node dependency)
4. `debbuild` - cross-builds `./cmd/cli` for `CLI_DEB_ARCH` and runs
   `build-cli-deb.sh` to assemble `revaulter-cli.deb`
5. `gobuild-server` - builds `./cmd/revaulter` with the web client + `revaulter-cli.deb`
   embedded at `dist/revaulter-cli.deb`
6. `runtime` - distroless server image (same base as the upstream `Dockerfile`)
7. `artifact-cli` - `scratch` image with just `revaulter-cli`, for `make cli-binary`

The server serves anything under the embedded `dist/` via its NoRoute handler, so
the .deb lands at `GET /revaulter-cli.deb`.

Build stages run natively (`$BUILDPLATFORM`); the Go binaries are cross-compiled,
so `ARCH=amd64` (default) and `ARCH=arm64` both build without QEMU on either kind
of host.

`packaging/Dockerfile.dockerignore` keeps `.git`, `node_modules`, etc. out of the
build context; the upstream root `Dockerfile` (used by CI) is untouched.

---

## Server: container image (for docker-compose)

```sh
make image                  # revaulterx:2 for linux/amd64
make image ARCH=arm64       # revaulterx:2 for linux/arm64/v8
make image-arm64            # shorthand
make images                 # both, tagged revaulterx:2-amd64 / revaulterx:2-arm64
```

Run `make image ARCH=<arch>` directly on each target host so the local
`revaulterx:2` tag matches that host's CPU. There is **no multi-arch manifest** -
that needs either a registry push or the containerd image store (see below).
Nothing is pushed anywhere; the image lands in the local Docker daemon.

```yaml
services:
  revaulter:
    image: revaulterx:2
    volumes:
      - ./config.yaml:/etc/revaulter/config.yaml:ro
      - revaulter-data:/var/lib/revaulter
    ports:
      - "8080:8080"
volumes:
  revaulter-data:
```

### Multi-arch image locally, without a registry

A multi-arch image is a manifest list; the classic Docker image store can't hold
one, so `buildx --platform amd64,arm64 --load` fails. Options:

- **Enable the containerd image store**: add `{"features":{"containerd-snapshotter":true}}`
  to `/etc/docker/daemon.json`, restart Docker. Then `buildx --platform
  linux/amd64,linux/arm64 --load` works and `docker run` auto-selects the arch.
- `buildx --output type=oci,dest=img.tar` then `docker load < img.tar` (also needs
  the containerd store to keep both arches).
- A throwaway `registry:2` container on `localhost:5000`.

The server runs on a single-arch VPS, so a plain `make image` there is enough.

There is no native-server install path (no `bundle` / `deb`) - the server only
ever runs as a container. `git log` has the removed targets if you ever need one.

---

## ZFS host: `revaulter-cli` .deb + boot unlock

The server image carries the `revaulter-cli` `.deb` (arch `CLI_DEB_ARCH`, default
`amd64`) and serves it from the embedded static FS, so on the ZFS host:

```sh
wget https://vault.vpnpro.eu/revaulter-cli.deb      # add --no-check-certificate for a self-signed cert
sudo apt install ./revaulter-cli.deb
```

Rebuild the server image after changing the CLI or the scripts to refresh what it
serves; use `make image CLI_DEB_ARCH=arm64` if the ZFS host is arm64.

The `.deb` is pre-configured for this deployment:

- `REVAULTER_SERVER` in `/etc/revaulter/cli/config` is already set to
  `https://vault.vpnpro.eu` (baked in from `packaging/cli/config`)
- only `REVAULTER_REQUEST_KEY` has to be filled in, once, after install

Then per dataset:

```sh
sudoedit /etc/revaulter/cli/config                  # REVAULTER_REQUEST_KEY="rvk_..."
sudo revaulter-zfs-setup z1pool32tb/encrypted       # prompts for the dataset passphrase
```

`revaulter-zfs-setup` pins the anchor (first run), wraps the **passphrase**
(`keyformat=passphrase`) into `/etc/revaulter/keys/<dataset>.json`, verifies it
with a dry-run `zfs load-key -n`, and enables
`revaulter-zfs-unlock@<escaped-dataset>.service`. `--create` instead generates a
random passphrase and `zfs create`s the dataset. At boot the unit waits for the
server, asks for approval, and runs `zfs load-key -r` + `zfs mount -a`. It retries
internally and never enters `failed`, so dependent units can use `Requires=` —
see the retry section in `packaging/cli/README.md`.

Full details are in `packaging/cli/README.md` (shipped to
`/usr/share/doc/revaulter-cli/README.md`).

Build the `.deb` standalone (same artifact the image embeds):

```sh
make cli-deb                 # -> .dist/revaulter-cli_<version>_amd64.deb
make cli-deb ARCH=arm64      # if the ZFS host is arm64
```

The package installs:

| Path | Purpose |
|------|---------|
| `/usr/bin/revaulter-cli` | the CLI |
| `/usr/bin/revaulter-zfs-setup` | register a dataset: pin trust, wrap passphrase, verify, enable the unit |
| `/usr/bin/revaulter-zfs-unlock` | run by the unit at boot: unwrap via Revaulter -> `zfs load-key -r` -> `zfs mount -a` |
| `/lib/systemd/system/revaulter-zfs-unlock@.service` | templated unit, `%I` = dataset |
| `/etc/revaulter/cli/config` | conffile: server URL (pre-set) + request key + trust-store / key-dir paths |
| `/etc/revaulter/cli/trust.json` | pinned anchor (created by `revaulter-zfs-setup`) |
| `/etc/revaulter/keys/<dataset>.json` | wrapped passphrase envelope, safe on an unencrypted disk |

`apt purge revaulter-cli` removes `/etc/revaulter/cli` and `/etc/revaulter/keys` -
**back up your wrapped envelopes first** if you still need them.
