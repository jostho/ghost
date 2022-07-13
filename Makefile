
# required binaries
CARGO := cargo
RUSTC := rustc
CC := gcc
LDD := ldd
BUILDAH := buildah
GIT := git
JQ := jq
PODMAN := podman
CURL := curl

ARCH = $(shell arch)

GIT_BRANCH := $(shell $(GIT) rev-parse --abbrev-ref HEAD)
GIT_COMMIT := $(shell $(GIT) rev-parse --short HEAD)
GIT_VERSION := $(GIT_BRANCH)/$(GIT_COMMIT)

APP_NAME := $(shell $(CARGO) read-manifest | $(JQ) -r .name)
APP_VERSION := $(shell $(CARGO) read-manifest | $(JQ) -r .version)
APP_REPOSITORY := $(shell $(CARGO) read-manifest | $(JQ) -r .repository)
APP_OWNER := jostho

IMAGE_BINARY_PATH := /usr/local/bin/$(APP_NAME)
IMAGE_META_VERSION_PATH := /usr/local/etc/$(APP_NAME)-release
IMAGE_SHARE_PATH := /usr/local/share
PORT := 8000

LOCAL_META_VERSION_PATH := $(CURDIR)/target/meta.version

TARGET_MUSL := $(ARCH)-unknown-linux-musl

RUSTC_PRINT_TARGET_CMD := $(RUSTC) -Z unstable-options --print target-spec-json
JQ_TARGET_CMD := $(JQ) -r '."llvm-target"'

# github action sets "CI=true"
ifeq ($(CI), true)
IMAGE_PREFIX := ghcr.io/$(APP_OWNER)
IMAGE_VERSION := $(GIT_COMMIT)
else
IMAGE_PREFIX := $(APP_OWNER)
IMAGE_VERSION := v$(APP_VERSION)
endif

check: check-required check-optional

check-required:
	$(CARGO) --version
	$(RUSTC) --version
	$(CC) --version | head -1
	$(LDD) --version | head -1

check-optional:
	$(BUILDAH) --version
	$(GIT) --version
	$(JQ) --version
	$(PODMAN) --version
	$(CURL) --version | head -1

clean:
	$(CARGO) clean

build:
	$(CARGO) build --release

build-static:
	$(CARGO) build --release --target $(TARGET_MUSL)

check-target-dir:
	test -d $(CURDIR)/target

prep-version-file: check-target-dir
	echo "$(APP_NAME) $(APP_VERSION) ($(GIT_COMMIT)) $(LLVM_TARGET)" > $(LOCAL_META_VERSION_PATH)
	$(MAKE) -s check-required >> $(LOCAL_META_VERSION_PATH)

# target for Containerfile
build-prep: LLVM_TARGET = $(shell RUSTC_BOOTSTRAP=1 $(RUSTC_PRINT_TARGET_CMD) | $(JQ_TARGET_CMD))
build-prep: build prep-version-file

build-image-default: BASE_IMAGE = debian
build-image-default:
	$(BUILDAH) bud \
		--tag $(IMAGE_NAME) \
		--label app-name=$(APP_NAME) \
		--label app-version=$(APP_VERSION) \
		--label app-git-version=$(GIT_VERSION) \
		--label app-arch=$(ARCH) \
		--label app-base-image=$(BASE_IMAGE) \
		--label org.opencontainers.image.source=$(APP_REPOSITORY) \
		-f Containerfile .

build-image-static: BASE_IMAGE = scratch
build-image-static: CONTAINER = $(APP_NAME)-$(BASE_IMAGE)-build-1
build-image-static: LOCAL_BINARY_PATH = $(CURDIR)/target/$(TARGET_MUSL)/release/$(APP_NAME)
build-image-static:
	$(BUILDAH) from --name $(CONTAINER) $(BASE_IMAGE)
	$(BUILDAH) copy $(CONTAINER) $(LOCAL_BINARY_PATH) $(IMAGE_BINARY_PATH)
	$(BUILDAH) copy $(CONTAINER) $(LOCAL_META_VERSION_PATH) $(IMAGE_META_VERSION_PATH)
	$(BUILDAH) copy $(CONTAINER) $(LOCAL_META_VERSION_PATH) $(IMAGE_SHARE_PATH)/$(APP_NAME)/static/meta.txt
	$(BUILDAH) config \
		--cmd $(IMAGE_BINARY_PATH) \
		--port $(PORT) \
		--env RUST_LOG=info \
		--env GHOST_STATIC_DIR=$(IMAGE_SHARE_PATH)/$(APP_NAME)/static \
		-l app-name=$(APP_NAME) \
		-l app-version=$(APP_VERSION) \
		-l app-git-version=$(GIT_VERSION) \
		-l app-arch=$(ARCH) \
		-l app-base-image=$(BASE_IMAGE) \
		-l app-llvm-target=$(LLVM_TARGET) \
		-l org.opencontainers.image.source=$(APP_REPOSITORY) \
		$(CONTAINER)
	$(BUILDAH) commit --rm $(CONTAINER) $(IMAGE_NAME)

verify-image:
	$(BUILDAH) images
	$(PODMAN) run $(IMAGE_NAME) $(IMAGE_BINARY_PATH) --version

run-container: VERIFY_URL = http://localhost:$(PORT)/{healthcheck,release}
run-container: verify-image
	$(PODMAN) run -d -p $(PORT):$(PORT) $(IMAGE_NAME)
	sleep 10
	$(CURL) -fsS -i -m 10 -w "\n--- %{url_effective} \n" $(VERIFY_URL)
	$(PODMAN) stop -l

push-image:
ifeq ($(CI), true)
	$(BUILDAH) push $(IMAGE_NAME)
endif

image: IMAGE_NAME = $(IMAGE_PREFIX)/$(APP_NAME):$(IMAGE_VERSION)
image: clean build-image-default verify-image push-image

image-static: IMAGE_NAME = $(IMAGE_PREFIX)/$(APP_NAME)-static:$(IMAGE_VERSION)
image-static: LLVM_TARGET = $(shell RUSTC_BOOTSTRAP=1 $(RUSTC_PRINT_TARGET_CMD) --target $(TARGET_MUSL) | $(JQ_TARGET_CMD))
image-static: clean build-static prep-version-file build-image-static verify-image push-image

run-image: IMAGE_NAME = $(IMAGE_PREFIX)/$(APP_NAME):$(IMAGE_VERSION)
run-image: run-container

run-image-static: IMAGE_NAME = $(IMAGE_PREFIX)/$(APP_NAME)-static:$(IMAGE_VERSION)
run-image-static: run-container

.PHONY: check check-required check-optional check-target-dir
.PHONY: clean prep-version-file
.PHONY: build build-static build-prep
.PHONY: build-image-default build-image-static
.PHONY: verify-image push-image
.PHONY: image image-static
.PHONY: run-image run-image-static run-container
