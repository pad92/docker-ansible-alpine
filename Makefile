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
TRIVY_IMAGE       ?= aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c
SCAN_PLATFORMS    ?= linux/amd64 linux/arm64
PYTHON            ?= python3
TRIVY_USERNAME    ?= $(CI_REGISTRY_USER)
TRIVY_PASSWORD    ?= $(CI_JOB_TOKEN)

# Pass API configuration to the shared update scripts without printing credentials.
export CI_API_V4_URL CI_PROJECT_ID CI_DEFAULT_BRANCH GITLAB_API_TOKEN
export CI_REGISTRY_IMAGE TRIVY_USERNAME TRIVY_PASSWORD

ifeq ($(strip $(BUILD_CONTEXT_HASH)),)
$(error Unable to calculate the build context hash; run this target from a Git checkout with sha256sum installed)
endif

# Targets
.PHONY: all help setup-buildx login check-versions build test test-ansible test-mitogen test-trivy test-ci check-ansible-release check-alpine-release check-trivy-release check-updates scan-published release clean

.DEFAULT_GOAL := help

help:
	@echo "Docker Ansible Alpine - available targets:"
	@echo "  make build          Build the image locally"
	@echo "  make test           Build the image and run all tests"
	@echo "  make test-ansible   Check Ansible and Ansible-Lint"
	@echo "  make test-mitogen   Check the Mitogen import"
	@echo "  make test-trivy     Scan the image with Trivy"
	@echo "  make test-ci        Validate CI scripts and run simulated release/update tests"
	@echo "  make check-ansible-release  Check upstream Ansible against local versions.env"
	@echo "  make check-alpine-release   Check upstream Alpine against local versions.env"
	@echo "  make check-trivy-release   Check the latest Trivy release and digest"
	@echo "  make check-updates  Check Ansible, Alpine, and Trivy (no GitLab token needed)"
	@echo "  make scan-published Scan the published latest digest on AMD64 and ARM64"
	@echo "  make release        Publish the tested revision (GitLab release job only)"
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
test: test-ci test-ansible test-mitogen test-trivy

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
		-v "$(CURDIR)/trivy-secret.yaml:/trivy-secret.yaml:ro" \
		"$(TRIVY_IMAGE)" image \
			--secret-config /trivy-secret.yaml --exit-code 1 --severity HIGH,CRITICAL --no-progress "$(CI_REGISTRY_IMAGE):$(IMAGE_TAG)"

# CI logic checks do not build images or contact registries.
test-ci:
	shellcheck -x ci/*.sh
	$(PYTHON) -m unittest discover -s ci/tests -v
	sh ci/test-ansible-version-at-least.sh

# Local checks only report updates; CI scripts keep their MR creation mode.
check-ansible-release:
	sh ci/check-ansible-release.sh --check

check-alpine-release:
	sh ci/check-alpine-release.sh --check

check-trivy-release:
	sh ci/check-trivy-release.sh --check

check-updates: check-ansible-release check-alpine-release check-trivy-release

# Resolve latest once so both platforms scan the same published image.
scan-published: login
	@mkdir -p "$(CURDIR)/trivy-cache"
	@set -eu; . ci/registry.sh; \
	digest="$$(registry_digest "$(CI_REGISTRY_IMAGE):latest")"; \
	for platform in $(SCAN_PLATFORMS); do \
		docker run --rm \
			-e TRIVY_USERNAME -e TRIVY_PASSWORD \
			-v "$(CURDIR)/trivy-cache:/root/.cache" \
			-v "$(CURDIR)/trivy-secret.yaml:/trivy-secret.yaml:ro" \
			"$(TRIVY_IMAGE)" image --image-src remote \
				--secret-config /trivy-secret.yaml --exit-code 1 \
				--severity HIGH,CRITICAL --no-progress --platform "$$platform" \
				"$(CI_REGISTRY_IMAGE)@$$digest"; \
	done

# The CI resource_group provides the lock required by revision allocation.
release:
	@test "$(GITLAB_CI)" = "true" && test "$(CI_JOB_NAME)" = "release_master" || \
		{ echo "Run release through the GitLab release_master job and its resource_group." >&2; exit 1; }
	sh ci/release-image.sh

# Cleanup local buildx configurations
clean:
	@if [ -f "$(BUILDER_STATE_FILE)" ] && [ "$$(cat "$(BUILDER_STATE_FILE)")" = "$(BUILDER_NAME)" ]; then \
		docker buildx rm "$(BUILDER_NAME)" || exit $$?; \
		rm -f "$(BUILDER_STATE_FILE)"; \
	else \
		echo "Preserving builder $(BUILDER_NAME): it was not created by this Makefile."; \
	fi
	docker run --rm -v "$(CURDIR):/workspace" "$(ALPINE_IMAGE)" sh -c "rm -rf /workspace/trivy-cache" || rm -rf "$(CURDIR)/trivy-cache"
