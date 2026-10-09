#!/bin/sh

set -eu

compare="$(dirname "$0")/is-ansible-version-at-least.sh"

assert_at_least() {
    if ! sh "$compare" "$1" "$2"; then
        echo "Expected $1 to be at least $2" >&2
        exit 1
    fi
}

assert_older() {
    if sh "$compare" "$1" "$2"; then
        echo "Expected $1 to be older than $2" >&2
        exit 1
    else
        status=$?
        if [ "$status" -ne 1 ]; then
            echo "Expected a valid non-newer comparison, got status $status" >&2
            exit 1
        fi
    fi
}

assert_invalid() {
    if sh "$compare" "$1" "$2"; then
        echo "Expected invalid version input to fail: $1 vs $2" >&2
        exit 1
    else
        status=$?
        if [ "$status" -ne 2 ]; then
            echo "Expected invalid-version status 2, got status $status" >&2
            exit 1
        fi
    fi
}

assert_at_least 14.5.0 13.99.99
assert_at_least 14.5.1 14.5.0
assert_at_least 14.5.0 14.5.0
assert_older 14.4.9 14.5.0
assert_invalid 14.5 14.4.0
assert_invalid 14.5.0-rc1 14.4.0

echo "Ansible latest-promotion comparison tests passed"
