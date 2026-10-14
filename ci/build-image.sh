#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <image:tag> [<image:tag> ...]" >&2
  exit 2
fi
image_tag_1="$1"
image_tag_2="${2:-}"
if [ "$#" -gt 2 ]; then
  echo "Usage: $0 <image:tag> [<image:tag>]" >&2
  exit 2
fi

test -n "${ALPINE_IMAGE:-}"
test -n "${ANSIBLE_VERSION:-}"
test -n "${ANSIBLE_CORE_VERSION:-}"
test -n "${ANSIBLE_LINT_VERSION:-}"
test -n "${MITOGEN_VERSION:-}"
grep -q '^ARG ANSIBLE_VERSION$' Dockerfile
grep -q '^ARG ANSIBLE_CORE_VERSION$' Dockerfile
grep -q '^ARG ANSIBLE_LINT_VERSION$' Dockerfile
grep -q '^ARG MITOGEN_VERSION$' Dockerfile

docker run --privileged multiarch/qemu-user-static --reset -p yes
docker buildx create --driver docker-container --use

set -- docker buildx build \
  --provenance=false \
  --pull \
  --push \
  --build-arg "ALPINE_IMAGE=${ALPINE_IMAGE}" \
  --build-arg "ANSIBLE_VERSION=${ANSIBLE_VERSION}" \
  --build-arg "ANSIBLE_CORE_VERSION=${ANSIBLE_CORE_VERSION}" \
  --build-arg "ANSIBLE_LINT_VERSION=${ANSIBLE_LINT_VERSION}" \
  --build-arg "MITOGEN_VERSION=${MITOGEN_VERSION}" \
  --build-arg "BUILD_NAME=${CI_PROJECT_NAME}" \
  --build-arg "BUILD_DATE=$(date '+%FT%T.%s%z')" \
  --build-arg "BUILD_VCSREF=$(printf '%s' "${CI_COMMIT_SHA}" | cut -c1-8)" \
  --platform=linux/amd64,linux/arm64

set -- "$@" --tag "$image_tag_1"
if [ -n "${image_tag_2}" ]; then
  set -- "$@" --tag "$image_tag_2"
fi

"$@" .
