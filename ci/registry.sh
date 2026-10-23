#!/bin/sh
# Shared registry operations. Callers use set -eu.
registry_digest() {
    if registry_result=$(docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>&1); then
        printf '%s\n' "$registry_result" | grep -Eq '^sha256:[a-f0-9]{64}$' || {
            echo "Invalid registry digest for $1" >&2
            return 2
        }
        printf '%s\n' "$registry_result"
    elif printf '%s\n' "$registry_result" | grep -Eqi 'manifest unknown|no such manifest'; then
        return 1
    else
        printf '%s\n' "$registry_result" >&2
        return 2
    fi
}

registry_labels() {
    registry_index=$(docker buildx imagetools inspect "$1" --raw) || return 2
    registry_platform=$(printf '%s' "$registry_index" | jq -er '.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64") | .digest') || return 2
    registry_config=$(docker buildx imagetools inspect "${1%@*}@${registry_platform}" --format '{{json .Image}}') || return 2
    printf '%s' "$registry_config" | jq -e '.config.Labels'
}

publish_verified() {
    docker buildx imagetools create --tag "$1" "$SOURCE_IMAGE"
    published_digest=$(registry_digest "$1")
    [ "$published_digest" = "$SOURCE_DIGEST" ] || {
        echo "Digest mismatch after publishing $1" >&2
        exit 1
    }
}
