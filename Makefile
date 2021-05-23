# tested with make 4.2.1

# required binaries
CARGO := cargo
RUSTC := rustc
CC := gcc
LDD := ldd
BUILDAH := buildah
GIT := git
JQ := jq
PODMAN := podman

ARCH = $(shell arch)

GIT_BRANCH := $(shell $(GIT) rev-parse --abbrev-ref HEAD)
GIT_COMMIT := $(shell $(GIT) rev-parse --short HEAD)
GIT_VERSION := $(GIT_BRANCH)/$(GIT_COMMIT)

APP_NAME := $(shell $(CARGO) read-manifest | $(JQ) -r .name)
APP_VERSION := $(shell $(CARGO) read-manifest | $(JQ) -r .version)

IMAGE_BINARY_PATH := /usr/local/bin/$(APP_NAME)
IMAGE_META_VERSION_PATH := /usr/local/etc/$(APP_NAME)-release
PORT := 8000

LOCAL_META_VERSION_PATH := $(CURDIR)/target/meta.version

TARGET_MUSL := $(ARCH)-unknown-linux-musl

RUSTC_PRINT_TARGET_CMD := $(RUSTC) -Z unstable-options --print target-spec-json
JQ_TARGET_CMD := $(JQ) -r '."llvm-target"'

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

clean:
	$(CARGO) clean

build:
	$(CARGO) build --release

build-static:
	$(CARGO) build --release --target $(TARGET_MUSL)

check-target-dir:
	test -d $(CURDIR)/target

prep-version-file: check-target-dir
	echo "$(APP_NAME) $(APP_VERSION) $(LLVM_TARGET)" > $(LOCAL_META_VERSION_PATH)
	$(MAKE) -s check-required >> $(LOCAL_META_VERSION_PATH)

# target for Containerfile
build-prep-version-file: LLVM_TARGET = $(shell RUSTC_BOOTSTRAP=1 $(RUSTC_PRINT_TARGET_CMD) | $(JQ_TARGET_CMD))
build-prep-version-file: build prep-version-file

build-image-default: BASE_IMAGE_TYPE = debian
build-image-default: IMAGE_NAME = jostho/$(APP_NAME):v$(APP_VERSION)
build-image-default:
	$(BUILDAH) bud \
		--tag $(IMAGE_NAME) \
		--label app-name=$(APP_NAME) \
		--label app-version=$(APP_VERSION) \
		--label app-git-version=$(GIT_VERSION) \
		--label app-arch=$(ARCH) \
		--label app-base-image=$(BASE_IMAGE_TYPE) \
		-f Containerfile .
	$(BUILDAH) images
	$(PODMAN) run $(IMAGE_NAME) $(IMAGE_BINARY_PATH) --version

build-image-static: BASE_IMAGE_TYPE = scratch
build-image-static: CONTAINER = $(APP_NAME)-$(BASE_IMAGE_TYPE)-build-1
build-image-static: BASE_IMAGE = $(BASE_IMAGE_TYPE)
build-image-static: IMAGE_NAME = jostho/$(APP_NAME)-static:v$(APP_VERSION)
build-image-static: LOCAL_BINARY_PATH = $(CURDIR)/target/$(TARGET_MUSL)/release/$(APP_NAME)
build-image-static:
	$(BUILDAH) from --name $(CONTAINER) $(BASE_IMAGE)
	$(BUILDAH) copy $(CONTAINER) $(LOCAL_BINARY_PATH) $(IMAGE_BINARY_PATH)
	$(BUILDAH) copy $(CONTAINER) $(LOCAL_META_VERSION_PATH) $(IMAGE_META_VERSION_PATH)
	$(BUILDAH) config \
		--cmd $(IMAGE_BINARY_PATH) \
		--port $(PORT) \
		--env RUST_LOG=info \
		-l app-name=$(APP_NAME) \
		-l app-version=$(APP_VERSION) \
		-l app-git-version=$(GIT_VERSION) \
		-l app-arch=$(ARCH) \
		-l app-base-image=$(BASE_IMAGE_TYPE) \
		-l app-llvm-target=$(LLVM_TARGET) \
		$(CONTAINER)
	$(BUILDAH) commit --rm $(CONTAINER) $(IMAGE_NAME)
	$(BUILDAH) images
	$(PODMAN) run $(IMAGE_NAME) $(IMAGE_BINARY_PATH) --version

image: clean build-image-default

image-static: LLVM_TARGET = $(shell RUSTC_BOOTSTRAP=1 $(RUSTC_PRINT_TARGET_CMD) --target $(TARGET_MUSL) | $(JQ_TARGET_CMD))
image-static: clean build-static prep-version-file build-image-static

.PHONY: check check-required check-optional check-target-dir
.PHONY: clean prep-version-file
.PHONY: build build-static build-prep-version-file
.PHONY: build-image-default build-image-static
.PHONY: image image-static
