#!/usr/bin/env bash
set -Eeuo pipefail

: "${HEALTH_URL:?HEALTH_URL is required}"

if [[ "${HEALTH_URL}" == *"example."* ]]; then
    echo "HEALTH_URL still contains a template placeholder: ${HEALTH_URL}" >&2
    exit 10
fi

if [[ "${DRY_RUN:-true}" == "true" ]]; then
    echo "DRY RUN: would verify ${HEALTH_URL}"
    exit 0
fi

attempt=1
max_attempts="${VERIFY_MAX_ATTEMPTS:-12}"
sleep_seconds="${VERIFY_SLEEP_SECONDS:-5}"

until curl --fail --silent --show-error --max-time 10 "${HEALTH_URL}" >/dev/null; do
    if (( attempt >= max_attempts )); then
        echo "Health verification failed after ${attempt} attempts: ${HEALTH_URL}" >&2
        exit 20
    fi
    attempt=$((attempt + 1))
    sleep "${sleep_seconds}"
done

mkdir -p evidence
printf '{"health_url":"%s","attempts":%s,"status":"PASS"}\n' \
    "${HEALTH_URL}" "${attempt}" > evidence/verification.json
