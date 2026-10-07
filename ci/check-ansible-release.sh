#!/bin/sh

set -eu

: "${CI_API_V4_URL:?CI_API_V4_URL is required}"
: "${CI_PROJECT_ID:?CI_PROJECT_ID is required}"
: "${CI_DEFAULT_BRANCH:?CI_DEFAULT_BRANCH is required}"
: "${GITLAB_API_TOKEN:?GITLAB_API_TOKEN is required}"

api_url="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"
auth_header="PRIVATE-TOKEN: ${GITLAB_API_TOKEN}"

versions_content=$(curl --fail --silent --show-error \
    --header "$auth_header" \
    "${api_url}/repository/files/versions.env/raw?ref=${CI_DEFAULT_BRANCH}")
current_ansible=$(printf '%s\n' "$versions_content" \
    | sed -n 's/^ANSIBLE_VERSION=//p')

latest_ansible=$(curl --fail --silent --show-error \
    "https://pypi.org/pypi/ansible/json" \
    | jq --raw-output '.info.version // empty')

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
    "https://pypi.org/pypi/ansible/${latest_ansible}/json" \
    | jq --raw-output '(.info.requires_dist // [])[] | select(startswith("ansible-core~=")) | split("~=")[1] | split(",")[0]' \
    | head -n 1)

if [ -z "$required_core" ]; then
    echo "Unable to determine the compatible ansible-core version for ${latest_ansible}" >&2
    exit 1
fi

current_core=$(printf '%s\n' "$versions_content" \
    | sed -n 's/^ANSIBLE_CORE_VERSION=//p')
required_core_family=$(printf '%s' "$required_core" | cut -d. -f1,2)
current_core_family=$(printf '%s' "$current_core" | cut -d. -f1,2)

if [ "$current_core_family" = "$required_core_family" ] \
    && [ "$(printf '%s\n%s\n' "$current_core" "$required_core" | sort -V | tail -n 1)" = "$current_core" ]; then
    ansible_core="$current_core"
else
    ansible_core="$required_core"
fi

branch="automation/ansible-${latest_ansible}"
branch_encoded=$(printf '%s' "$branch" | jq --raw-input --raw-output '@uri')
existing_mrs=$(curl --fail --silent --show-error \
    --header "$auth_header" \
    --get \
    --data-urlencode "state=opened" \
    --data-urlencode "source_branch=${branch}" \
    "${api_url}/merge_requests")

if [ "$(printf '%s\n' "$existing_mrs" | jq 'length')" -gt 0 ]; then
    echo "An open MR already exists for ${latest_ansible}"
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
            --data-urlencode "ref=${CI_DEFAULT_BRANCH}" \
            "${api_url}/repository/branches" >/dev/null
        ;;
    *)
        echo "Unable to inspect automation branch ${branch} (HTTP ${branch_status})" >&2
        exit 1
        ;;
esac

updated_versions=$(printf '%s\n' "$versions_content" \
    | sed "s/^ANSIBLE_VERSION=.*/ANSIBLE_VERSION=${latest_ansible}/" \
    | sed "s/^ANSIBLE_CORE_VERSION=.*/ANSIBLE_CORE_VERSION=${ansible_core}/")

release_date=$(date -u '+%Y-%m-%d')
changelog_content=$(curl --fail --silent --show-error \
    --header "$auth_header" \
    "${api_url}/repository/files/CHANGELOG.md/raw?ref=${CI_DEFAULT_BRANCH}")
updated_changelog=$(printf '%s\n' "$changelog_content" | awk \
    -v version="$latest_ansible" \
    -v core="$ansible_core" \
    -v release_date="$release_date" '
    /^## \[/ && !inserted {
        print "## [" version "] - " release_date
        print ""
        print "### Changed"
        print "- Upgraded Ansible to " version "."
        print "- Pinned compatible Ansible Core to " core "."
        print ""
        inserted = 1
    }
    { print }
')

commit_message="build(ansible): update to ${latest_ansible}"

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
if [ "$(printf '%s' "$commit_payload" | jq '.actions | length')" -gt 0 ]; then
    curl --fail --silent --show-error --request POST \
        --header "$auth_header" --header "Content-Type: application/json" \
        --data "$commit_payload" "${api_url}/repository/commits" >/dev/null
fi

description=$(cat <<EOF
Automated update detected on PyPI.

- Ansible: ${current_ansible} -> ${latest_ansible}
- ansible-core: ${ansible_core}

The regular build and security tests must pass before merging.
EOF
)

curl --fail --silent --show-error \
    --request POST \
    --header "$auth_header" \
    --data-urlencode "source_branch=${branch}" \
    --data-urlencode "target_branch=${CI_DEFAULT_BRANCH}" \
    --data-urlencode "title=${commit_message}" \
    --data-urlencode "description=${description}" \
    --data-urlencode "remove_source_branch=true" \
    "${api_url}/merge_requests" \
    | jq --raw-output '"Created MR: !" + (.iid | tostring) + " " + .web_url'
