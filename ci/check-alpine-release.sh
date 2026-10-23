#!/bin/sh
set -eu
exec sh "$(dirname "$0")/check-upstream-release.sh" alpine "$@"
