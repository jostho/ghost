# tested with make 4.2.1

# required binaries
CARGO := /usr/bin/cargo
BUILDAH := /usr/bin/buildah
GIT := /usr/bin/git
JQ := /usr/bin/jq
PODMAN := /usr/bin/podman

GIT_BRANCH := $(shell $(GIT) rev-parse --abbrev-ref HEAD)
GIT_COMMIT := $(shell $(GIT) rev-parse --short HEAD)
GIT_VERSION := $(GIT_BRANCH)/$(GIT_COMMIT)

APP_NAME := $(shell $(CARGO) read-manifest | $(JQ) -r .name)
APP_VERSION := $(shell $(CARGO) read-manifest | $(JQ) -r .version)

UBI_TYPE := ubi8-minimal
BASE_IMAGE := registry.access.redhat.com/$(UBI_TYPE):8.2

CONTAINER := $(APP_NAME)-$(UBI_TYPE)-build-1
IMAGE_NAME := jostho/$(APP_NAME):v$(APP_VERSION)
IMAGE_BINARY_PATH := /usr/local/bin/$(APP_NAME)
PORT := 8000

TARGET := $(CURDIR)/target/release/$(APP_NAME)

check:
	$(CARGO) --version
	$(BUILDAH) --version
	$(GIT) --version
	$(JQ) --version
	$(PODMAN) --version

clean:
	$(CARGO) clean

build:
	$(CARGO) build --release

build-image:
	$(BUILDAH) from --name $(CONTAINER) $(BASE_IMAGE)
	$(BUILDAH) copy $(CONTAINER) $(TARGET) $(IMAGE_BINARY_PATH)
	$(BUILDAH) config \
		--cmd $(IMAGE_BINARY_PATH) \
		--port $(PORT) \
		-l app-name=$(APP_NAME) -l app-version=$(APP_VERSION) \
		-l app-git-version=$(GIT_VERSION) -l app-base-image=$(UBI_TYPE) \
		$(CONTAINER)
	$(BUILDAH) commit --rm $(CONTAINER) $(IMAGE_NAME)

clean-image:
	$(BUILDAH) rmi $(IMAGE_NAME)

image: clean build build-image

.PHONY: check clean build
.PHONY: build-image clean-image image
