#!/bin/sh

set -eu

update_kind=${1:-ansible}
mode=${2:---create-mr}
case "$mode" in
    --check) versions_content=$(cat versions.env) ;;
    --create-mr)
        : "${CI_API_V4_URL:?CI_API_V4_URL is required}"
        : "${CI_PROJECT_ID:?CI_PROJECT_ID is required}"
        : "${CI_DEFAULT_BRANCH:?CI_DEFAULT_BRANCH is required}"
        : "${GITLAB_API_TOKEN:?GITLAB_API_TOKEN is required}"

        api_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"
        auth_header="PRIVATE-TOKEN: ${GITLAB_API_TOKEN}"

        default_encoded=$(printf '%s' "$CI_DEFAULT_BRANCH" | jq -sRr @uri)
        base_ref=$(curl --fail --silent --show-error --header "$auth_header" \
            "${api_url}/repository/branches/${default_encoded}" | jq -er '.commit.id')
        versions_content=$(curl --fail --silent --show-error \
            --header "$auth_header" \
            "${api_url}/repository/files/versions.env/raw?ref=${base_ref}")
        ;;
    *)
        echo "Usage: $0 [ansible|alpine] [--check|--create-mr]" >&2
        exit 2
        ;;
esac
case "$update_kind" in
    ansible)
        current_ansible=$(printf '%s\n' "$versions_content" |
            sed -n 's/^ANSIBLE_VERSION=//p')

        latest_ansible=$(curl --fail --silent --show-error \
            "https://pypi.org/pypi/ansible/json" |
            jq --raw-output '.info.version // empty')

        if [ -z "$current_ansible" ] || [ -z "$latest_ansible" ]; then
            echo "Unable to determine the current or latest Ansible version" >&2
            exit 1
        fi

        if [ "$current_ansible" = "$latest_ansible" ]; then
            echo "Ansible ${current_ansible} is already configured"
            exit 0
        fi

        newer_version=$(printf '%s\n%s\n' "$current_ansible" "$latest_ansible" | sort -V | tail -n 1)
        if [ "$newer_version" != "$latest_ansible" ]; then
            echo "Configured Ansible ${current_ansible} is newer than PyPI ${latest_ansible}; no MR created"
            exit 0
        fi

        required_core=$(curl --fail --silent --show-error \
            "https://pypi.org/pypi/ansible/${latest_ansible}/json" |
            jq --raw-output '(.info.requires_dist // [])[] | select(startswith("ansible-core~=")) | split("~=")[1] | split(",")[0]' |
            head -n 1)

        if [ -z "$required_core" ]; then
            echo "Unable to determine the compatible ansible-core version for ${latest_ansible}" >&2
            exit 1
        fi

        current_core=$(printf '%s\n' "$versions_content" |
            sed -n 's/^ANSIBLE_CORE_VERSION=//p')
        required_core_family=$(printf '%s' "$required_core" | cut -d. -f1,2)
        current_core_family=$(printf '%s' "$current_core" | cut -d. -f1,2)

        if [ "$current_core_family" = "$required_core_family" ] &&
            [ "$(printf '%s\n%s\n' "$current_core" "$required_core" | sort -V | tail -n 1)" = "$current_core" ]; then
            ansible_core="$current_core"
        else
            ansible_core="$required_core"
        fi

        branch="automation/ansible-${latest_ansible}"
        commit_message="build(ansible): update to ${latest_ansible}"
        updated_versions=$(printf '%s\n' "$versions_content" |
            sed "s/^ANSIBLE_VERSION=.*/ANSIBLE_VERSION=${latest_ansible}/" |
            sed "s/^ANSIBLE_CORE_VERSION=.*/ANSIBLE_CORE_VERSION=${ansible_core}/")
        change_note="Upgrade Ansible to ${latest_ansible} with ansible-core ${ansible_core}."
        ;;
    trivy)
        current_trivy=$(sed -n 's/^TRIVY_IMAGE[[:space:]]*?*=[[:space:]]*//p' Makefile | head -n 1)
        current_version=$(printf '%s' "$current_trivy" | sed -n 's|^aquasec/trivy:\([0-9]*\.[0-9]*\.[0-9]*\)@sha256:[a-f0-9]*$|\1|p')
        current_digest=$(printf '%s' "$current_trivy" | sed -n 's|^aquasec/trivy:[0-9]*\.[0-9]*\.[0-9]*@\(sha256:[a-f0-9]*\)$|\1|p')
        [ -n "$current_version" ] && [ -n "$current_digest" ] || {
            echo "Expected a versioned and digest-pinned Trivy image in Makefile" >&2
            exit 1
        }
        release=$(curl --fail --silent --show-error \
            --header 'Accept: application/vnd.github+json' \
            --header 'User-Agent: docker-ansible-alpine-ci' \
            https://api.github.com/repos/aquasecurity/trivy/releases/latest)
        latest_trivy=$(printf '%s' "$release" | jq -er '.tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) | ltrimstr("v")')
        if sh ci/is-ansible-version-at-least.sh "$latest_trivy" "$current_version"; then
            :
        else
            status=$?
            [ "$status" -eq 1 ] || exit "$status"
            echo "Configured Trivy ${current_version} is newer than GitHub ${latest_trivy}; no update created"
            exit 0
        fi
        # shellcheck source=ci/registry.sh
        . "$(dirname "$0")/registry.sh"
        trivy_digest=$(registry_digest "aquasec/trivy:${latest_trivy}")
        new_image="aquasec/trivy:${latest_trivy}@${trivy_digest}"
        if [ "$new_image" = "$current_trivy" ]; then
            echo "Trivy ${latest_trivy} is already configured"
            exit 0
        fi
        branch="automation/trivy-${latest_trivy}-${trivy_digest#sha256:}"
        updated_versions=$versions_content
        commit_message="ci(trivy): update to ${latest_trivy}"
        change_note="Update the Trivy scanner to ${new_image}."
        ;;
    alpine)
        current_image=$(printf '%s\n' "$versions_content" | sed -n 's/^ALPINE_IMAGE=//p')
        current_version=$(printf '%s' "$current_image" | sed -n 's/^alpine:\([0-9]*\.[0-9]*\.[0-9]*\)@sha256:[a-f0-9]*$/\1/p')
        [ -n "$current_version" ] || {
            echo "Expected a pinned Alpine patch version" >&2
            exit 1
        }
        alpine_series=${current_version%.*}
        # shellcheck source=ci/registry.sh
        . "$(dirname "$0")/registry.sh"
        digest=$(registry_digest "alpine:${alpine_series}")
        # Resolve the index by digest, not by the moving branch tag.
        index=$(docker buildx imagetools inspect "alpine@${digest}" --raw)
        latest_alpine=$(printf '%s' "$index" | jq -er '[.manifests[] | select(.platform.os == "linux") | .annotations["org.opencontainers.image.version"]] | unique | if length == 1 then .[0] else error("Inconsistent Alpine versions") end')
        case "$latest_alpine" in
            "$alpine_series".*) ;;
            *)
                echo "Alpine series changed unexpectedly" >&2
                exit 1
                ;;
        esac
        sh ci/is-ansible-version-at-least.sh "$latest_alpine" "$current_version"
        new_image="alpine:${latest_alpine}@${digest}"
        if [ "$new_image" = "$current_image" ]; then
            echo "Alpine ${latest_alpine} is already configured"
            exit 0
        fi
        branch="automation/alpine-${latest_alpine}-${digest#sha256:}"
        commit_message="build(alpine): update to ${latest_alpine}"
        updated_versions=$(printf '%s\n' "$versions_content" | sed "s|^ALPINE_IMAGE=.*|ALPINE_IMAGE=${new_image}|")
        change_note="Update Alpine to ${new_image}."
        ;;
    *)
        echo "Usage: $0 [ansible|alpine]" >&2
        exit 2
        ;;
esac

if [ "$mode" = --check ]; then
    printf '%s\n' "$change_note"
    exit 0
fi

branch_encoded=$(printf '%s' "$branch" | jq --raw-input --raw-output '@uri')
existing_mrs=$(curl --fail --silent --show-error \
    --header "$auth_header" \
    --get \
    --data-urlencode "state=opened" \
    --data-urlencode "source_branch=${branch}" \
    "${api_url}/merge_requests")

if [ "$(printf '%s\n' "$existing_mrs" | jq 'length')" -gt 0 ]; then
    echo "An open MR already exists for ${branch}"
    exit 0
fi

branch_status=$(curl --silent --show-error \
    --header "$auth_header" \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${api_url}/repository/branches/${branch_encoded}")

case "$branch_status" in
    200)
        echo "Using existing automation branch ${branch}"
        ;;
    404)
        curl --fail --silent --show-error \
            --request POST \
            --header "$auth_header" \
            --data-urlencode "branch=${branch}" \
            --data-urlencode "ref=${base_ref}" \
            "${api_url}/repository/branches" >/dev/null
        ;;
    *)
        echo "Unable to inspect automation branch ${branch} (HTTP ${branch_status})" >&2
        exit 1
        ;;
esac

release_date=$(date -u '+%Y-%m-%d')
changelog_content=$(curl --fail --silent --show-error \
    --header "$auth_header" \
    "${api_url}/repository/files/CHANGELOG.md/raw?ref=${base_ref}")
updated_changelog=$(printf '%s\n' "$changelog_content" | awk \
    -v note="$change_note" -v release_date="$release_date" '
    /^## \[/ && !inserted {
        print "## [" release_date "]"
        print ""
        print "### Changed"
        print "- " note
        print ""
        inserted = 1
    }
    { print }
')

branch_versions=$(curl --fail --silent --show-error --header "$auth_header" \
    "${api_url}/repository/files/versions.env/raw?ref=${branch_encoded}")
branch_changelog=$(curl --fail --silent --show-error --header "$auth_header" \
    "${api_url}/repository/files/CHANGELOG.md/raw?ref=${branch_encoded}")
commit_payload=$(jq -n --arg branch "$branch" --arg message "$commit_message" \
    --arg versions "$updated_versions" --arg changelog "$updated_changelog" \
    --arg old_versions "$branch_versions" --arg old_changelog "$branch_changelog" '
    {branch: $branch, commit_message: $message, actions: [
      (if $versions != $old_versions then
        {action: "update", file_path: "versions.env", content: $versions}
       else empty end),
      (if $changelog != $old_changelog then
        {action: "update", file_path: "CHANGELOG.md", content: $changelog}
       else empty end)
    ]}')
if [ "$update_kind" = alpine ]; then
    for file in Dockerfile .gitlab-ci.yml; do
        file_content=$(curl --fail --silent --show-error --header "$auth_header" \
            "${api_url}/repository/files/${file}/raw?ref=${branch_encoded}")
        new_content=$(printf '%s\n' "$file_content" | sed -E "s|alpine:[0-9]+\\.[0-9]+(\\.[0-9]+)?@sha256:[a-f0-9]{64}|${new_image}|g")
        if [ "$file_content" != "$new_content" ]; then
            commit_payload=$(printf '%s' "$commit_payload" | jq --arg file "$file" --arg content "$new_content" \
                '.actions += [{action: "update", file_path: $file, content: $content}]')
        fi
    done
elif [ "$update_kind" = trivy ]; then
    for file in Makefile .gitlab-ci.yml; do
        file_content=$(curl --fail --silent --show-error --header "$auth_header" \
            "${api_url}/repository/files/${file}/raw?ref=${branch_encoded}")
        new_content=$(printf '%s\n' "$file_content" | sed -E "s|aquasec/trivy:[0-9]+\\.[0-9]+\\.[0-9]+@sha256:[a-f0-9]{64}|${new_image}|g")
        if [ "$file_content" != "$new_content" ]; then
            commit_payload=$(printf '%s' "$commit_payload" | jq --arg file "$file" --arg content "$new_content" \
                '.actions += [{action: "update", file_path: $file, content: $content}]')
        fi
    done
fi
if [ "$(printf '%s' "$commit_payload" | jq '.actions | length')" -gt 0 ]; then
    curl --fail --silent --show-error --request POST \
        --header "$auth_header" --header "Content-Type: application/json" \
        --data "$commit_payload" "${api_url}/repository/commits" >/dev/null
fi

description="Automated ${update_kind} update.

${change_note}

The regular build and security tests must pass before merging."

curl --fail --silent --show-error \
    --request POST \
    --header "$auth_header" \
    --data-urlencode "source_branch=${branch}" \
    --data-urlencode "target_branch=${CI_DEFAULT_BRANCH}" \
    --data-urlencode "title=${commit_message}" \
    --data-urlencode "description=${description}" \
    --data-urlencode "remove_source_branch=true" \
    "${api_url}/merge_requests" |
    jq --raw-output '"Created MR: !" + (.iid | tostring) + " " + .web_url'
