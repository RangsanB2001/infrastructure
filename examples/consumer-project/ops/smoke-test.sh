#!/usr/bin/env bash
set -Eeuo pipefail

: "${HEALTH_URL:?HEALTH_URL is required}"

if [[ "${DRY_RUN:-true}" == "true" ]]; then
    echo "DRY RUN: smoke test skipped"
    exit 0
fi

# Replace this endpoint with a read-only business smoke test for the application.
curl --fail --silent --show-error --max-time 15 "${HEALTH_URL}" >/dev/null
