# Docker Ansible Alpine - Build and Test Pipeline (Local Development)

# Load the single source of truth. Builds stop if it is missing.
include versions.env

# Variables (fallbacks for local development)
CI_PROJECT_NAME    ?= docker-ansible-alpine
BUILDER_NAME       ?= $(CI_PROJECT_NAME)-builder
CI_REGISTRY        ?= registry.gitlab.com
CI_REGISTRY_IMAGE  ?= $(CI_REGISTRY)/pad92/$(CI_PROJECT_NAME)
BUILD_CONTEXT_HASH := $(shell git ls-files -z | xargs -0 -r git hash-object 2>/dev/null | sha256sum | cut -c1-16)
IMAGE_TAG          ?= $(if $(CI_COMMIT_SHA),$(CI_COMMIT_SHA),$(BUILD_CONTEXT_HASH))
BUILD_VCSREF       ?= $(if $(CI_COMMIT_SHA),$(CI_COMMIT_SHA),$(BUILD_CONTEXT_HASH))
BUILDER_STATE_FILE ?= $(CURDIR)/.buildx-builder-created

ifeq ($(strip $(BUILD_CONTEXT_HASH)),)
$(error Unable to calculate the build context hash; run this target from a Git checkout with sha256sum installed)
endif

# Targets
.PHONY: all help setup-buildx login check-versions build test test-ansible test-mitogen test-trivy clean

.DEFAULT_GOAL := help

help:
	@echo "Docker Ansible Alpine - available targets:"
	@echo "  make build          Build the image locally"
	@echo "  make test           Build the image and run all tests"
	@echo "  make test-ansible   Check Ansible and Ansible-Lint"
	@echo "  make test-mitogen   Check the Mitogen import"
	@echo "  make test-trivy     Scan the image with Trivy"
	@echo "  make clean          Remove the local builder and Trivy cache"

all: build test

# Configure the local Buildx builder. This project performs a native build.
setup-buildx:
	@if ! docker buildx inspect "$(BUILDER_NAME)" >/dev/null 2>&1; then \
			docker buildx create --name "$(BUILDER_NAME)" --driver docker-container --use || exit $$?; \
			printf '%s\n' "$(BUILDER_NAME)" > "$(BUILDER_STATE_FILE)"; \
	fi
	docker buildx use "$(BUILDER_NAME)"

# Registry authentications (optional for pulling base images if credentials provided)
login:
	@if [ -n "$(CI_REGISTRY_USER)" ] && [ -n "$(CI_JOB_TOKEN)" ]; then \
		printf '%s' "$(CI_JOB_TOKEN)" | docker login --username "$(CI_REGISTRY_USER)" --password-stdin "$(CI_REGISTRY)"; \
	fi
	@if [ -n "$(DOCKER_HUB_PASSWORD)" ] && [ -n "$(DOCKER_HUB_USER)" ]; then \
		printf '%s' "$(DOCKER_HUB_PASSWORD)" | docker login -u "$(DOCKER_HUB_USER)" --password-stdin; \
	fi

check-versions:
	@test -n "$(ALPINE_IMAGE)"
	@test -n "$(ANSIBLE_VERSION)"
	@test -n "$(ANSIBLE_CORE_VERSION)"
	@test -n "$(ANSIBLE_LINT_VERSION)"
	@test -n "$(MITOGEN_VERSION)"
	@test "$(ALPINE_IMAGE)" = "$$(sed -n 's/^ALPINE_IMAGE=//p' versions.env)"
	@test "$(ANSIBLE_VERSION)" = "$$(sed -n 's/^ANSIBLE_VERSION=//p' versions.env)"
	@test "$(ANSIBLE_CORE_VERSION)" = "$$(sed -n 's/^ANSIBLE_CORE_VERSION=//p' versions.env)"
	@test "$(ANSIBLE_LINT_VERSION)" = "$$(sed -n 's/^ANSIBLE_LINT_VERSION=//p' versions.env)"
	@test "$(MITOGEN_VERSION)" = "$$(sed -n 's/^MITOGEN_VERSION=//p' versions.env)"
	@grep -q '^ARG ANSIBLE_VERSION$$' Dockerfile
	@grep -q '^ARG ANSIBLE_CORE_VERSION$$' Dockerfile
	@grep -q '^ARG ANSIBLE_LINT_VERSION$$' Dockerfile
	@grep -q '^ARG MITOGEN_VERSION$$' Dockerfile

# Build image locally and load it into local docker daemon (no push)
build: check-versions setup-buildx login
	@if docker image inspect "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)" >/dev/null 2>&1; then \
		echo "Image $(CI_REGISTRY_IMAGE):$(IMAGE_TAG) already exists locally, skipping build."; \
	else \
		status=0; \
		docker buildx build \
			--provenance=false \
			--pull \
			--load \
			--build-arg ALPINE_IMAGE="$(ALPINE_IMAGE)" \
			--build-arg ANSIBLE_VERSION="$(ANSIBLE_VERSION)" \
			--build-arg ANSIBLE_CORE_VERSION="$(ANSIBLE_CORE_VERSION)" \
			--build-arg ANSIBLE_LINT_VERSION="$(ANSIBLE_LINT_VERSION)" \
			--build-arg MITOGEN_VERSION="$(MITOGEN_VERSION)" \
			--build-arg BUILD_NAME="$(CI_PROJECT_NAME)" \
			--build-arg BUILD_DATE="$$(date '+%FT%T.%s%z')" \
			--build-arg BUILD_VCSREF="$$(printf '%s' "$(BUILD_VCSREF)" | cut -c1-8)" \
			-t "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)" \
			. || status=$$?; \
		exit $$status; \
	fi

# Tests
test: test-ansible test-mitogen test-trivy

test-ansible: build
	@set -e; expected="$(ANSIBLE_VERSION)"; \
	actual="$$(docker run --rm "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)" python3 -c 'import importlib.metadata as m; print(m.version("ansible"))')"; \
	test "$$actual" = "$$expected"; \
	expected_core="$(ANSIBLE_CORE_VERSION)"; \
	actual_core="$$(docker run --rm "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)" python3 -c 'import importlib.metadata as m; print(m.version("ansible-core"))')"; \
	test "$$actual_core" = "$$expected_core"
	docker run --rm "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)" ansible --version
	docker run --rm "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)" ansible-lint --version

test-mitogen: build
	docker run --rm "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)" python3 -c "import ansible_mitogen"

test-trivy: build
	@mkdir -p "$(CURDIR)/trivy-cache"
	docker run --rm \
		-e TRIVY_USERNAME="$(CI_REGISTRY_USER)" \
		-e TRIVY_PASSWORD="$(CI_JOB_TOKEN)" \
		-v "/var/run/docker.sock:/var/run/docker.sock" \
		-v "$(CURDIR)/trivy-cache:/root/.cache" \
		aquasec/trivy@sha256:cffe3f5161a47a6823fbd23d985795b3ed72a4c806da4c4df16266c02accdd6f image \
			--exit-code 1 --severity CRITICAL --no-progress "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)"
	docker run --rm \
		-e TRIVY_USERNAME="$(CI_REGISTRY_USER)" \
		-e TRIVY_PASSWORD="$(CI_JOB_TOKEN)" \
		-v "/var/run/docker.sock:/var/run/docker.sock" \
		-v "$(CURDIR)/trivy-cache:/root/.cache" \
		aquasec/trivy@sha256:cffe3f5161a47a6823fbd23d985795b3ed72a4c806da4c4df16266c02accdd6f image \
			--exit-code 1 --severity HIGH --no-progress "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)"

# Cleanup local buildx configurations
clean:
	@if [ -f "$(BUILDER_STATE_FILE)" ] && [ "$$(cat "$(BUILDER_STATE_FILE)")" = "$(BUILDER_NAME)" ]; then \
		docker buildx rm "$(BUILDER_NAME)" || exit $$?; \
		rm -f "$(BUILDER_STATE_FILE)"; \
	else \
		echo "Preserving builder $(BUILDER_NAME): it was not created by this Makefile."; \
	fi
	docker run --rm -v "$(CURDIR):/workspace" "$(ALPINE_IMAGE)" sh -c "rm -rf /workspace/trivy-cache" || rm -rf "$(CURDIR)/trivy-cache"
