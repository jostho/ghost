# tested with make 4.2.1

# required binaries
CARGO := cargo
CC := gcc
BUILDAH := buildah
GIT := git
JQ := jq

GIT_BRANCH := $(shell $(GIT) rev-parse --abbrev-ref HEAD)
GIT_COMMIT := $(shell $(GIT) rev-parse --short HEAD)
GIT_VERSION := $(GIT_BRANCH)/$(GIT_COMMIT)

APP_NAME := $(shell $(CARGO) read-manifest | $(JQ) -r .name)
APP_VERSION := $(shell $(CARGO) read-manifest | $(JQ) -r .version)

UBI_BASE_IMAGE := registry.access.redhat.com/ubi8-minimal:8.2

IMAGE_BINARY_PATH := /usr/local/bin/$(APP_NAME)
PORT := 8000

TARGET_MUSL := x86_64-unknown-linux-musl

check:
	$(CARGO) --version
	$(CC) --version | head -1
	$(BUILDAH) --version
	$(GIT) --version
	$(JQ) --version

clean:
	$(CARGO) clean

build:
	$(CARGO) build --release

build-static:
	$(CARGO) build --release --target $(TARGET_MUSL)

build-image-default: BASE_IMAGE_TYPE = ubi
build-image-default: CONTAINER = $(APP_NAME)-$(BASE_IMAGE_TYPE)-build-1
build-image-default: BASE_IMAGE = $(UBI_BASE_IMAGE)
build-image-default: IMAGE_NAME = jostho/$(APP_NAME):v$(APP_VERSION)
build-image-default: LOCAL_BINARY_PATH = $(CURDIR)/target/release/$(APP_NAME)
build-image-default: build-image

build-image-static: BASE_IMAGE_TYPE = scratch
build-image-static: CONTAINER = $(APP_NAME)-$(BASE_IMAGE_TYPE)-build-1
build-image-static: BASE_IMAGE = $(BASE_IMAGE_TYPE)
build-image-static: IMAGE_NAME = jostho/$(APP_NAME)-static:v$(APP_VERSION)
build-image-static: LOCAL_BINARY_PATH = $(CURDIR)/target/$(TARGET_MUSL)/release/$(APP_NAME)
build-image-static: build-image

build-image:
	$(BUILDAH) from --name $(CONTAINER) $(BASE_IMAGE)
	$(BUILDAH) copy $(CONTAINER) $(LOCAL_BINARY_PATH) $(IMAGE_BINARY_PATH)
	$(BUILDAH) config \
		--cmd $(IMAGE_BINARY_PATH) \
		--port $(PORT) \
		--env RUST_LOG=info \
		-l app-name=$(APP_NAME) -l app-version=$(APP_VERSION) \
		-l app-git-version=$(GIT_VERSION) -l app-base-image=$(BASE_IMAGE_TYPE) \
		$(CONTAINER)
	$(BUILDAH) commit --rm $(CONTAINER) $(IMAGE_NAME)
	$(BUILDAH) images

image: clean build build-image-default

image-static: clean build-static build-image-static

.PHONY: check clean build build-static
.PHONY: build-image-default build-image-static build-image
.PHONY: image image-static
