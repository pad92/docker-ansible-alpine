#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 CANDIDATE_VERSION CURRENT_VERSION" >&2
    exit 2
fi

awk -v candidate="$1" -v current="$2" '
    BEGIN {
        candidate_count = split(candidate, candidate_parts, ".")
        current_count = split(current, current_parts, ".")

        if (candidate_count != 3 || current_count != 3) {
            exit 2
        }

        for (i = 1; i <= 3; i++) {
            if (candidate_parts[i] !~ /^[0-9]+$/ || current_parts[i] !~ /^[0-9]+$/) {
                exit 2
            }
        }

        for (i = 1; i <= 3; i++) {
            if (candidate_parts[i] + 0 > current_parts[i] + 0) {
                exit 0
            }
            if (candidate_parts[i] + 0 < current_parts[i] + 0) {
                exit 1
            }
        }

        exit 0
    }
'
