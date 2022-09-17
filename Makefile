
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

# target for Containerfile.static
build-prep-static: LLVM_TARGET = $(shell RUSTC_BOOTSTRAP=1 $(RUSTC_PRINT_TARGET_CMD) --target $(TARGET_MUSL) | $(JQ_TARGET_CMD))
build-prep-static: build-static prep-version-file

build-image:
	$(BUILDAH) bud \
		--tag $(IMAGE_NAME) \
		--build-arg TARGET=$(TARGET) \
		--label app-name=$(APP_NAME) \
		--label app-version=$(APP_VERSION) \
		--label app-git-version=$(GIT_VERSION) \
		--label app-arch=$(ARCH) \
		--label app-base-image=$(BASE_IMAGE) \
		--label org.opencontainers.image.source=$(APP_REPOSITORY) \
		-f $(CONTAINER_FILE) .

build-image-default: BASE_IMAGE = debian
build-image-default: CONTAINER_FILE = Containerfile
build-image-default: TARGET = default
build-image-default: build-image

build-image-static: BASE_IMAGE = scratch
build-image-static: CONTAINER_FILE = Containerfile.static
build-image-static: TARGET = $(TARGET_MUSL)
build-image-static: build-image

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
image-static: clean build-image-static verify-image push-image

run-image: IMAGE_NAME = $(IMAGE_PREFIX)/$(APP_NAME):$(IMAGE_VERSION)
run-image: run-container

run-image-static: IMAGE_NAME = $(IMAGE_PREFIX)/$(APP_NAME)-static:$(IMAGE_VERSION)
run-image-static: run-container

.PHONY: check check-required check-optional check-target-dir
.PHONY: clean prep-version-file
.PHONY: build build-static build-prep build-prep-static
.PHONY: build-image build-image-default build-image-static
.PHONY: verify-image push-image
.PHONY: image image-static
.PHONY: run-image run-image-static run-container
