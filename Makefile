# Revaulter - development & packaging
#
# Deployment:
#   - the server / web UI runs as a container on the Hetzner VPS (vault.vpnpro.eu)
#   - nas1 / nas2 (Ubuntu ZFS storage servers, amd64) install the revaulter-cli
#     .deb, which the server image also serves at GET /revaulter-cli.deb
#
# Everything below builds inside Docker - no Go/Node/pnpm toolchain on the host.
# Run `make` or `make help` for the target list.

.DEFAULT_GOAL := help

##@ Development

.PHONY: test
test: ## Run unit tests
	go test -tags unit ./...

.PHONY: test-race
test-race: ## Run unit tests with the race detector
	CGO_ENABLED=1 go test -race -tags unit ./...

.PHONY: lint
lint: ## Run golangci-lint
	golangci-lint run -c .golangci.yaml

.PHONY: gen-config
gen-config: ## Regenerate config.sample.yaml from internal/config
	go run ./tools/gen-config-yaml

.PHONY: check-config-diff
check-config-diff: gen-config ## Fail if config.sample.yaml is out of date
	git diff --exit-code config.sample.yaml

.PHONY: gen-db
gen-db: ## Regenerate the db backup table code
	go generate ./internal/db/...

.PHONY: check-db-diff
check-db-diff: gen-db ## Fail if the db backup table code is out of date
	git diff --exit-code internal/db/backup/tables_gen.go

##@ Web client

.PHONY: client-format
client-format: ## Format the web client (pnpm)
	(cd client/web && pnpm run format)

.PHONY: client-lint
client-lint: ## Lint the web client (pnpm)
	(cd client/web && pnpm run lint)

.PHONY: test-client
test-client: ## Run web client unit tests
	(cd client/web && pnpm run test)

# Runs against chromium only
# Set E2E_BROWSERS to "all", or a comma-separated list of chromium, firefox and webkit
.PHONY: test-e2e
test-e2e: ## Run web client e2e tests (chromium)
	(cd client/web && pnpm run e2e)

# ---------------------------------------------------------------------------
# Packaging config
#
# Builds run natively ($BUILDPLATFORM); the Go binaries are cross-compiled, so
# any ARCH builds cheaply on any host (no QEMU). See packaging/README.md.
# ---------------------------------------------------------------------------

IMAGE       ?= revaulterx
IMAGE_TAG   ?= 2
DIST_DIR    ?= .dist
APP_VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT_HASH ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD_DATE  ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

# revaulter-cli .deb metadata
#
# packaging/ is gitignored, so `git describe` does NOT change when the scripts or
# the systemd unit in it change - without a build stamp apt refuses the reinstall
# with "is already the newest version". `:=` so date runs once per make invocation
BUILD_STAMP := $(shell date -u +%Y%m%d%H%M%S)
# Drop the -dirty suffix: build-cli-deb.sh turns "-" into "~", and "~" sorts
# BEFORE an empty suffix in Debian versions, which would make it a downgrade.
# +BUILD_STAMP already marks this as a local build and sorts monotonically up
DEB_BASE_VERSION := $(patsubst v%,%,$(subst -dirty,,$(APP_VERSION)))
DEB_VERSION    ?= $(DEB_BASE_VERSION)+$(BUILD_STAMP)
DEB_MAINTAINER ?= gusty <werty1st@gmail.com>
# Arch of the .deb the server image serves at /revaulter-cli.deb (nas1/nas2 are amd64)
CLI_DEB_ARCH   ?= amd64

# Target CPU architecture for `make image` / `make cli-*`: amd64 (default) or arm64
# The server image arch and the embedded .deb arch (CLI_DEB_ARCH) are independent:
#   make image ARCH=arm64    -> arm64 image, amd64 .deb inside (for nas1/nas2)
ARCH ?= amd64
ifeq ($(ARCH),amd64)
  TARGET_PLATFORM := linux/amd64
else ifeq ($(ARCH),arm64)
  TARGET_PLATFORM := linux/arm64/v8
else
  $(error unsupported ARCH '$(ARCH)' - use 'amd64' or 'arm64')
endif

BIN_DIR := $(DIST_DIR)/bin/$(ARCH)

DOCKER_BUILD := docker build -f packaging/Dockerfile \
	--platform $(TARGET_PLATFORM) \
	--build-arg APP_VERSION=$(APP_VERSION) \
	--build-arg COMMIT_HASH=$(COMMIT_HASH) \
	--build-arg BUILD_DATE=$(BUILD_DATE) \
	--build-arg CLI_DEB_ARCH=$(CLI_DEB_ARCH) \
	--build-arg DEB_VERSION=$(DEB_VERSION) \
	--build-arg 'DEB_MAINTAINER=$(DEB_MAINTAINER)'

##@ Server image (deploy on the VPS)

.PHONY: image
image: ## Build the server image (revaulterx:2) for ARCH, default amd64
	$(DOCKER_BUILD) --target runtime -t $(IMAGE):$(IMAGE_TAG) .
	@echo "-> $(IMAGE):$(IMAGE_TAG) ($(TARGET_PLATFORM)); serves /revaulter-cli.deb ($(CLI_DEB_ARCH))"

.PHONY: image-amd64
image-amd64: ## Build the server image for amd64
	$(MAKE) image ARCH=amd64

.PHONY: image-arm64
image-arm64: ## Build the server image for arm64
	$(MAKE) image ARCH=arm64

.PHONY: images
images: ## Build both arches (tags get an -amd64 / -arm64 suffix)
	$(MAKE) image ARCH=amd64 IMAGE_TAG=$(IMAGE_TAG)-amd64
	$(MAKE) image ARCH=arm64 IMAGE_TAG=$(IMAGE_TAG)-arm64

##@ revaulter-cli / ZFS boot-unlock (install on nas1 / nas2)

.PHONY: cli-deb
cli-deb: cli-binary ## Build the revaulter-cli .deb into .dist/ (same one the image serves)
	packaging/build-cli-deb.sh "$(DEB_VERSION)" "$(ARCH)" "$(BIN_DIR)/revaulter-cli" "$(DIST_DIR)" "$(DEB_MAINTAINER)" "$(COMMIT_HASH)"

.PHONY: cli-binary
cli-binary: ## Build just the revaulter-cli binary into .dist/bin/<arch>/
	mkdir -p "$(BIN_DIR)"
	$(DOCKER_BUILD) --target artifact-cli --output type=local,dest=$(BIN_DIR) .
	@echo "-> $(BIN_DIR)/revaulter-cli"

##@ Housekeeping

.PHONY: dist-clean
dist-clean: ## Remove the .dist/ build output directory
	rm -rf "$(DIST_DIR)"

.PHONY: help
help: ## Show this help
	@echo 'Revaulter - make targets   (usage: make <target> [ARCH=amd64|arm64])'
	@awk 'BEGIN {FS = ":.*## "} \
		/^##@ / {printf "\n%s\n", substr($$0, 5); next} \
		/^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)


# Quick
# build: make image ARCH=arm64 CLI_DEB_ARCH=amd64
# download: wget https://vault.vpnpro.eu/revaulter-cli.deb
