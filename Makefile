.PHONY: test
test:
	go test -tags unit ./...

.PHONY: test-race
test-race:
	CGO_ENABLED=1 go test -race -tags unit ./...

.PHONY: lint
lint:
	golangci-lint run -c .golangci.yaml

.PHONY: gen-config
gen-config:
	go run ./tools/gen-config-yaml

# Ensure gen-config ran
.PHONY: check-config-diff
check-config-diff: gen-config
	git diff --exit-code config.sample.yaml

.PHONY: gen-db
gen-db:
	go generate ./internal/db/...

# Ensure gen-db ran
.PHONY: check-db-diff
check-db-diff: gen-db
	git diff --exit-code internal/db/backup/tables_gen.go

.PHONY: client-format
client-format:
	(cd client/web && pnpm run format)

.PHONY: client-lint
client-lint:
	(cd client/web && pnpm run lint)

.PHONY: test-client
test-client:
	(cd client/web && pnpm run test)

# Runs against chromium only
# Set E2E_BROWSERS to "all", or to a comma-separated list of chromium, firefox and webkit, to run against other engines
.PHONY: test-e2e
test-e2e:
	(cd client/web && pnpm run e2e)

# ---------------------------------------------------------------------------
# Deployment / packaging
#
# Everything below builds inside Docker, so no Go/Node toolchain is needed on
# the host. See packaging/README.md for details.
#
# The build stages run natively and the Go binary is cross-compiled, so any
# ARCH builds cheaply on any host (no QEMU).
#
# Server (runs as a container via docker-compose):
#   make image                -> local $(ARCH) container image ($(IMAGE):$(IMAGE_TAG))
#   make image ARCH=arm64     -> same, for an arm64/v8 host
#   make image-amd64 / -arm64 -> convenience aliases for the above
#   make images               -> both arches, tagged $(IMAGE):$(IMAGE_TAG)-amd64 / -arm64
#   make binary / bundle / deb [ARCH=...]  -> native server binary / tarball / .deb
#
# CLI + ZFS boot-unlock (for the ZFS host, default ARCH=amd64):
#   make cli-binary [ARCH=...] -> revaulter-cli in $(DIST_DIR)/bin/$(ARCH)/
#   make cli-bundle [ARCH=...] -> tarball: revaulter-cli + zfs-unlock scripts + systemd unit
#   make cli-deb    [ARCH=...] -> revaulter-cli_<ver>_<arch>.deb
#
#   make dist-clean           -> remove $(DIST_DIR)
# ---------------------------------------------------------------------------

IMAGE ?= revaulterx
IMAGE_TAG ?= 2
DIST_DIR ?= .dist
APP_VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT_HASH ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD_DATE ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
DEB_VERSION ?= $(patsubst v%,%,$(APP_VERSION))
DEB_MAINTAINER ?= gusty <werty1st@gmail.com>

# Target CPU architecture: amd64 (default, the ZFS host) or arm64 (the compose host)
ARCH ?= amd64
ifeq ($(ARCH),amd64)
  TARGET_PLATFORM := linux/amd64
else ifeq ($(ARCH),arm64)
  TARGET_PLATFORM := linux/arm64/v8
else
  $(error unsupported ARCH '$(ARCH)' - use 'amd64' or 'arm64')
endif

BIN_DIR := $(DIST_DIR)/bin/$(ARCH)
BUNDLE_NAME := revaulter-$(DEB_VERSION)-linux-$(ARCH)

DOCKER_BUILD := docker build -f packaging/Dockerfile \
	--platform $(TARGET_PLATFORM) \
	--build-arg APP_VERSION=$(APP_VERSION) \
	--build-arg COMMIT_HASH=$(COMMIT_HASH) \
	--build-arg BUILD_DATE=$(BUILD_DATE)

.PHONY: image
image:
	$(DOCKER_BUILD) --target runtime -t $(IMAGE):$(IMAGE_TAG) .
	@echo "-> image $(IMAGE):$(IMAGE_TAG) ($(TARGET_PLATFORM))"

.PHONY: image-amd64
image-amd64:
	$(MAKE) image ARCH=amd64

.PHONY: image-arm64
image-arm64:
	$(MAKE) image ARCH=arm64

# Both arches on one machine, kept apart by an -amd64 / -arm64 tag suffix
.PHONY: images
images:
	$(MAKE) image ARCH=amd64 IMAGE_TAG=$(IMAGE_TAG)-amd64
	$(MAKE) image ARCH=arm64 IMAGE_TAG=$(IMAGE_TAG)-arm64

.PHONY: binary
binary:
	mkdir -p "$(BIN_DIR)"
	$(DOCKER_BUILD) --target artifact --output type=local,dest=$(BIN_DIR) .
	@echo "-> $(BIN_DIR)/revaulter"

.PHONY: cli-binary
cli-binary:
	mkdir -p "$(BIN_DIR)"
	$(DOCKER_BUILD) --target artifact-cli --output type=local,dest=$(BIN_DIR) .
	@echo "-> $(BIN_DIR)/revaulter-cli"

.PHONY: bundle
bundle: binary
	rm -rf "$(DIST_DIR)/$(BUNDLE_NAME)"
	mkdir -p "$(DIST_DIR)/$(BUNDLE_NAME)"
	install -m 0755 "$(BIN_DIR)/revaulter"               "$(DIST_DIR)/$(BUNDLE_NAME)/revaulter"
	install -m 0644 packaging/config.yaml                "$(DIST_DIR)/$(BUNDLE_NAME)/config.yaml"
	install -m 0644 config.sample.yaml                   "$(DIST_DIR)/$(BUNDLE_NAME)/config.sample.yaml"
	install -m 0644 packaging/systemd/revaulter.service  "$(DIST_DIR)/$(BUNDLE_NAME)/revaulter.service"
	install -m 0755 packaging/install.sh                 "$(DIST_DIR)/$(BUNDLE_NAME)/install.sh"
	install -m 0644 LICENSE.md                           "$(DIST_DIR)/$(BUNDLE_NAME)/LICENSE.md"
	tar -C "$(DIST_DIR)" -czf "$(DIST_DIR)/$(BUNDLE_NAME).tar.gz" "$(BUNDLE_NAME)"
	@echo "-> $(DIST_DIR)/$(BUNDLE_NAME).tar.gz"

.PHONY: deb
deb: binary
	packaging/build-deb.sh "$(DEB_VERSION)" "$(ARCH)" "$(BIN_DIR)/revaulter" "$(DIST_DIR)" "$(DEB_MAINTAINER)" "$(COMMIT_HASH)"

CLI_BUNDLE_NAME := revaulter-cli-$(DEB_VERSION)-linux-$(ARCH)

.PHONY: cli-bundle
cli-bundle: cli-binary
	rm -rf "$(DIST_DIR)/$(CLI_BUNDLE_NAME)"
	mkdir -p "$(DIST_DIR)/$(CLI_BUNDLE_NAME)"
	install -m 0755 "$(BIN_DIR)/revaulter-cli"                     "$(DIST_DIR)/$(CLI_BUNDLE_NAME)/revaulter-cli"
	install -m 0755 packaging/cli/revaulter-zfs-unlock            "$(DIST_DIR)/$(CLI_BUNDLE_NAME)/revaulter-zfs-unlock"
	install -m 0755 packaging/cli/revaulter-zfs-setup             "$(DIST_DIR)/$(CLI_BUNDLE_NAME)/revaulter-zfs-setup"
	install -m 0644 packaging/cli/revaulter-zfs-unlock@.service   "$(DIST_DIR)/$(CLI_BUNDLE_NAME)/revaulter-zfs-unlock@.service"
	install -m 0644 packaging/cli/config                         "$(DIST_DIR)/$(CLI_BUNDLE_NAME)/config"
	install -m 0755 packaging/cli/install.sh                     "$(DIST_DIR)/$(CLI_BUNDLE_NAME)/install.sh"
	install -m 0644 LICENSE.md                                   "$(DIST_DIR)/$(CLI_BUNDLE_NAME)/LICENSE.md"
	tar -C "$(DIST_DIR)" -czf "$(DIST_DIR)/$(CLI_BUNDLE_NAME).tar.gz" "$(CLI_BUNDLE_NAME)"
	@echo "-> $(DIST_DIR)/$(CLI_BUNDLE_NAME).tar.gz"

.PHONY: cli-deb
cli-deb: cli-binary
	packaging/build-cli-deb.sh "$(DEB_VERSION)" "$(ARCH)" "$(BIN_DIR)/revaulter-cli" "$(DIST_DIR)" "$(DEB_MAINTAINER)" "$(COMMIT_HASH)"

.PHONY: dist-clean
dist-clean:
	rm -rf "$(DIST_DIR)"
