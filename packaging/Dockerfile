# syntax=docker/dockerfile:1

# Self-contained multi-stage build for Revaulter
#
# Everything (Go, Node, pnpm) lives in the build stages, so nothing needs to be
# installed on the host - only Docker with BuildKit
#
# The build stages always run natively ($BUILDPLATFORM) and the Go binaries are
# cross-compiled for the target, so building linux/amd64 on an arm64 host (or
# vice versa) needs no QEMU emulation
#
# Targets:
#   runtime      - the distroless server image (default), used by docker-compose;
#                  also serves the revaulter-cli .deb at GET /revaulter-cli.deb
#   artifact-cli - a scratch image with just revaulter-cli, for `--output` (make cli-binary)
#
# Build args:
#   APP_VERSION, COMMIT_HASH, BUILD_DATE  - stamped into `... version`
#   CLI_DEB_ARCH  (default amd64)         - arch of the bundled revaulter-cli .deb
#   DEB_VERSION, DEB_MAINTAINER           - metadata for that .deb

ARG GO_VERSION=1.27
ARG NODE_VERSION=24
# gcr.io/distroless/static-debian13:nonroot - keep the digest in sync with ../Dockerfile
ARG DISTROLESS_DIGEST=sha256:1c2c046bc09ed40fad370b599a0b1ae7987f55b01e247cf27a7c27cd97e5bbc7

# ---- Stage 1: build the embedded web client (arch-independent) -----------
FROM --platform=$BUILDPLATFORM node:${NODE_VERSION}-bookworm-slim AS webbuild
WORKDIR /src/client/web
ENV CI=1
RUN npm install -g pnpm@12.0.0
COPY client/web/package.json client/web/pnpm-lock.yaml client/web/pnpm-workspace.yaml ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile
COPY client/web/ ./
RUN pnpm run build

# ---- Stage 2: common Go build base --------------------------------------
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-bookworm AS gobase
WORKDIR /src
# CGO is off: the SQLite driver (modernc.org/sqlite) is pure Go, so cross-compiling is trivial
ENV CGO_ENABLED=0 GOWORK=off
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY . .
ARG TARGETOS
ARG TARGETARCH
ARG APP_VERSION=dev
ARG BUILD_DATE=""
ARG COMMIT_HASH=""
ENV COMMIT_HASH="${COMMIT_HASH}"
ENV GO_LDFLAGS="-s -w \
  -X github.com/italypaleale/revaulter/internal/buildinfo.AppVersion=${APP_VERSION} \
  -X github.com/italypaleale/revaulter/internal/buildinfo.BuildId=${APP_VERSION} \
  -X github.com/italypaleale/revaulter/internal/buildinfo.BuildDate=${BUILD_DATE} \
  -X github.com/italypaleale/revaulter/internal/buildinfo.CommitHash=${COMMIT_HASH}"

# ---- Stage 2b: revaulter-cli (no web client, no Node dependency) -------
FROM gobase AS gobuild-cli
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
    go build -trimpath -ldflags "${GO_LDFLAGS}" -o /out/revaulter-cli ./cmd/cli

# ---- Stage 2c: the revaulter-cli .deb, to bundle into the server image -
# Built for CLI_DEB_ARCH (the ZFS client), independent of the server image's arch
FROM gobase AS debbuild
ARG CLI_DEB_ARCH=amd64
ARG DEB_VERSION=dev
ARG DEB_MAINTAINER="Revaulter packager <root@localhost>"
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOOS=linux GOARCH="${CLI_DEB_ARCH}" \
    go build -trimpath -ldflags "${GO_LDFLAGS}" -o /tmp/revaulter-cli ./cmd/cli
RUN mkdir -p /out \
 && packaging/build-cli-deb.sh "${DEB_VERSION}" "${CLI_DEB_ARCH}" /tmp/revaulter-cli /out "${DEB_MAINTAINER}" "${COMMIT_HASH}" \
 && cp /out/revaulter-cli_*_"${CLI_DEB_ARCH}".deb /out/revaulter-cli.deb

# ---- Stage 2a: server binary (web client + cli .deb embedded) ----------
FROM gobase AS gobuild-server
COPY --from=webbuild /src/client/web/dist ./client/web/dist
# The server serves anything under the embedded dist/ via its NoRoute handler,
# so this lands at GET /revaulter-cli.deb
COPY --from=debbuild /out/revaulter-cli.deb ./client/web/dist/revaulter-cli.deb
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
    go build -trimpath -ldflags "${GO_LDFLAGS}" -o /out/revaulter ./cmd/revaulter

# ---- Stage 3a: runtime image ------------------------------------------
FROM gcr.io/distroless/static-debian13:nonroot@${DISTROLESS_DIGEST} AS runtime
COPY --from=gobuild-server /out/revaulter /bin/revaulter
# The server is ready < 1s after start; probe fast during the start period so the
# container reports "healthy" quickly instead of sitting in "starting" for the
# default 30s interval (--start-interval needs Docker Engine >= 25.0)
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --start-interval=1s \
    CMD ["/bin/revaulter", "healthcheck"]
CMD ["/bin/revaulter"]
ENTRYPOINT ["/bin/revaulter"]

# ---- Stage 3b: binary-only artifact, for `docker build --output` (make cli-binary) --
FROM scratch AS artifact-cli
COPY --from=gobuild-cli /out/revaulter-cli /revaulter-cli
