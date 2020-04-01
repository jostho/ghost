# tested with make 4.2.1

CARGO := /usr/bin/cargo
BUILDAH := /usr/bin/buildah
GIT := /usr/bin/git
JQ := /usr/bin/jq

TARGET := $(CURDIR)/target/release

GIT_COMMIT := $(shell $(GIT) rev-parse --short HEAD)
APP_NAME := $(shell $(CARGO) read-manifest | $(JQ) -r .name)
APP_VERSION := $(shell $(CARGO) read-manifest | $(JQ) -r .version)

CONTAINER := $(APP_NAME)-ubi-container-1
BASE_IMAGE := registry.access.redhat.com/ubi8/ubi-minimal:latest
IMAGE_NAME := jostho/$(APP_NAME):v$(APP_VERSION)
IMAGE_BINARY_PATH := /usr/local/bin/$(APP_NAME)
PORT := 8000

check:
	$(CARGO) --version
	$(BUILDAH) --version
	$(GIT) --version
	$(JQ) --version

clean:
	rm -rf $(TARGET)

build:
	$(CARGO) build --release

build-image:
	$(BUILDAH) from --name $(CONTAINER) $(BASE_IMAGE)
	$(BUILDAH) copy $(CONTAINER) $(TARGET)/$(APP_NAME) $(IMAGE_BINARY_PATH)
	$(BUILDAH) config \
		--cmd $(IMAGE_BINARY_PATH) --port $(PORT) \
		-l Name=$(APP_NAME) -l Version=$(APP_VERSION) -l Commit=$(GIT_COMMIT) \
		$(CONTAINER)
	$(BUILDAH) commit --rm $(CONTAINER) $(IMAGE_NAME)

clean-image:
	$(BUILDAH) rmi $(IMAGE_NAME)

image: clean build build-image

.PHONY: check clean build
.PHONY: build-image clean-image image
