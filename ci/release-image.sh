#!/bin/sh
set -eu
# shellcheck source=ci/registry.sh
. "$(dirname "$0")/registry.sh"
. ./versions.env
: "${TESTED_IMAGE:?Missing tested image digest}"
: "${CI_REGISTRY_IMAGE:?}"
: "${CI_COMMIT_SHA:?}"
: "${CI_DEFAULT_BRANCH:?}"
: "${CI_PIPELINE_ID:?}"
SOURCE_IMAGE=$TESTED_IMAGE
SOURCE_DIGEST=${SOURCE_IMAGE##*@}
for check in ansible mitogen trivy-amd64 trivy-arm64; do
    [ "$(cat "validation/${check}.txt")" = "$SOURCE_IMAGE" ] || {
        echo "Missing or stale validation: ${check}" >&2
        exit 1
    }
done
[ "$SOURCE_IMAGE" = "${CI_REGISTRY_IMAGE}@${SOURCE_DIGEST}" ] || exit 1
[ "$(registry_digest "$SOURCE_IMAGE")" = "$SOURCE_DIGEST" ] || exit 1

# This job must hold the shared release resource_group before checking the head.
head=$(git ls-remote --exit-code origin "refs/heads/${CI_DEFAULT_BRANCH}")
head=$(printf '%s\n' "$head" | awk 'NR == 1 { print $1 }')
if [ "$head" != "$CI_COMMIT_SHA" ]; then
    echo "Skipping obsolete pipeline: default branch has advanced"
    exit 0
fi
source_labels=$(registry_labels "$SOURCE_IMAGE")
[ "$(printf '%s' "$source_labels" | jq -r '."org.opencontainers.image.version"')" = "$ANSIBLE_VERSION" ] || exit 1
[ "$(printf '%s' "$source_labels" | jq -r '."org.opencontainers.image.revision"')" = "$CI_COMMIT_SHA" ] || exit 1
[ "$(printf '%s' "$source_labels" | jq -r '."io.gitlab.ci.pipeline.id"')" = "$CI_PIPELINE_ID" ] || exit 1

set -- "$CI_REGISTRY_IMAGE"
if [ -n "${DOCKER_HUB_USER:-}" ] && [ -n "${DOCKER_HUB_PASSWORD:-}" ]; then
    set -- "$@" "${DU_REGISTRY_IMAGE:-pad92/ansible-alpine}"
fi

# Reject older retries even if they were built from the same commit.
for registry in "$@"; do
    if alias_digest=$(registry_digest "${registry}:${ANSIBLE_VERSION}"); then
        labels=$(registry_labels "${registry}@${alias_digest}")
        previous_pipeline=$(printf '%s' "$labels" | jq -r '."io.gitlab.ci.pipeline.id" // "0"')
        case "$previous_pipeline" in '' | *[!0-9]*) exit 1 ;; esac
        if [ "$previous_pipeline" -gt "$CI_PIPELINE_ID" ]; then
            echo "Skipping pipeline older than ${registry}:${ANSIBLE_VERSION}"
            exit 0
        fi
    else
        status=$?
        [ "$status" -eq 1 ] || exit "$status"
    fi
done

# GitLab is the revision ledger. Keep numbered tags in its retention policy.
revision=1
while :; do
    release_tag="${ANSIBLE_VERSION}-${revision}"
    if existing=$(registry_digest "${CI_REGISTRY_IMAGE}:${release_tag}"); then
        [ "$existing" != "$SOURCE_DIGEST" ] || break
        revision=$((revision + 1))
    else
        status=$?
        [ "$status" -eq 1 ] || exit "$status"
        break
    fi
done

# Preflight all fixed tags before writing. A partial release reuses the same tag.
for registry in "$@"; do
    if existing=$(registry_digest "${registry}:${release_tag}"); then
        [ "$existing" = "$SOURCE_DIGEST" ] || {
            echo "Refusing to overwrite ${registry}:${release_tag}" >&2
            exit 1
        }
    else
        status=$?
        [ "$status" -eq 1 ] || exit "$status"
    fi
done
for registry in "$@"; do
    publish_verified "${registry}:${release_tag}"
done
for registry in "$@"; do
    publish_verified "${registry}:${ANSIBLE_VERSION}"
    if latest_digest=$(registry_digest "${registry}:latest"); then
        labels=$(registry_labels "${registry}@${latest_digest}")
        latest_version=$(printf '%s' "$labels" | jq -er '."org.opencontainers.image.version"')
        if sh ci/is-ansible-version-at-least.sh "$ANSIBLE_VERSION" "$latest_version"; then :; else
            status=$?
            [ "$status" -eq 1 ] || exit "$status"
            echo "Keeping ${registry}:latest at newer Ansible ${latest_version}"
            continue
        fi
        latest_pipeline=$(printf '%s' "$labels" | jq -r '."io.gitlab.ci.pipeline.id" // "0"')
        case "$latest_pipeline" in '' | *[!0-9]*) exit 1 ;; esac
        if [ "$ANSIBLE_VERSION" = "$latest_version" ] && [ "$latest_pipeline" -gt "$CI_PIPELINE_ID" ]; then
            echo "Keeping newer latest pipeline ${latest_pipeline}"
            continue
        fi
    else
        status=$?
        [ "$status" -eq 1 ] || exit "$status"
    fi
    publish_verified "${registry}:latest"
done
printf 'Published %s from %s\n' "$release_tag" "$SOURCE_IMAGE"
