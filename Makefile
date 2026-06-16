# Docker Ansible Alpine - Build and Test Pipeline (Local Development)

# Target variables with sensible defaults
ALPINE_VERSION     ?= 3.22
ANSIBLE_VERSION    ?= 12.2.0
ANSIBLE_LINT_VERSION ?= 25.12.0
MITOGEN_VERSION    ?= 0.3.49

# Variables (fallbacks for local development)
CI_PROJECT_NAME    ?= docker-ansible-alpine
CI_REGISTRY        ?= registry.gitlab.com
CI_REGISTRY_IMAGE  ?= $(CI_REGISTRY)/pad92/$(CI_PROJECT_NAME)
CI_COMMIT_SHA      ?= $(shell git rev-parse HEAD 2>/dev/null || echo "latest")

# Detect branch and tags if run locally
CI_COMMIT_TAG      ?= $(shell git describe --tags --exact-match 2>/dev/null)
CI_COMMIT_BRANCH   ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)

# Dynamically set build version for Ansible
ifeq ($(CI_COMMIT_TAG),)
  BUILD_ANSIBLE_VERSION ?= $(ANSIBLE_VERSION)
else
  BUILD_ANSIBLE_VERSION ?= $(CI_COMMIT_TAG)
endif

# Targets
.PHONY: all setup-buildx login build test test-ansible test-mitogen test-trivy clean

all: build test

# Register QEMU handlers and configure Buildx builder
setup-buildx:
	docker run --rm --privileged multiarch/qemu-user-static --reset -p yes || true
	docker buildx create --driver docker-container --use || true

# Registry authentications (optional for pulling base images if credentials provided)
login:
	@if [ -n "$(CI_REGISTRY_USER)" ] && [ -n "$(CI_JOB_TOKEN)" ]; then \
		docker login -u "$(CI_REGISTRY_USER)" -p "$(CI_JOB_TOKEN)" "$(CI_REGISTRY)"; \
	fi
	@if [ -n "$(DOCKER_HUB_PASSWORD)" ] && [ -n "$(DOCKER_HUB_USER)" ]; then \
		echo "$(DOCKER_HUB_PASSWORD)" | docker login -u "$(DOCKER_HUB_USER)" --password-stdin; \
	fi

# Build image locally and load it into local docker daemon (no push)
build: setup-buildx login
	docker buildx build \
		--provenance=false \
		--pull \
		--load \
		--build-arg ALPINE_VERSION="$(ALPINE_VERSION)" \
		--build-arg ANSIBLE_VERSION="$(BUILD_ANSIBLE_VERSION)" \
		--build-arg ANSIBLE_LINT_VERSION="$(ANSIBLE_LINT_VERSION)" \
		--build-arg MITOGEN_VERSION="$(MITOGEN_VERSION)" \
		--build-arg BUILD_NAME="$(CI_PROJECT_NAME)" \
		--build-arg BUILD_DATE="$$(date '+%FT%T.%s%z')" \
		--build-arg BUILD_VCSREF="$$(echo $(CI_COMMIT_SHA) | cut -c1-8)" \
		-t "$(CI_REGISTRY_IMAGE):$(CI_COMMIT_SHA)" \
		.

# Tests
test: test-ansible test-mitogen test-trivy

test-ansible:
	docker run --rm "$(CI_REGISTRY_IMAGE):$(CI_COMMIT_SHA)" ansible --version
	docker run --rm "$(CI_REGISTRY_IMAGE):$(CI_COMMIT_SHA)" ansible-lint --version

test-mitogen:
	docker run --rm "$(CI_REGISTRY_IMAGE):$(CI_COMMIT_SHA)" python3 -c "import ansible_mitogen"

test-trivy:
	@mkdir -p "$(CURDIR)/trivy-cache"
	docker run --rm \
		-e TRIVY_USERNAME="$(CI_REGISTRY_USER)" \
		-e TRIVY_PASSWORD="$(CI_JOB_TOKEN)" \
		-v "/var/run/docker.sock:/var/run/docker.sock" \
		-v "$(CURDIR)/trivy-cache:/root/.cache" \
		aquasec/trivy:latest image \
		--exit-code 1 --severity CRITICAL --no-progress "$(CI_REGISTRY_IMAGE):$(CI_COMMIT_SHA)"
	docker run --rm \
		-e TRIVY_USERNAME="$(CI_REGISTRY_USER)" \
		-e TRIVY_PASSWORD="$(CI_JOB_TOKEN)" \
		-v "/var/run/docker.sock:/var/run/docker.sock" \
		-v "$(CURDIR)/trivy-cache:/root/.cache" \
		aquasec/trivy:latest image \
		--exit-code 0 --severity HIGH --no-progress "$(CI_REGISTRY_IMAGE):$(CI_COMMIT_SHA)"

# Cleanup local buildx configurations
clean:
	docker buildx rm || true
	rm -rf "$(CURDIR)/trivy-cache"
