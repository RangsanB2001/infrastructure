#!/usr/bin/env bash
set -Eeuo pipefail

: "${BYTEBASE_URL:?BYTEBASE_URL is required}"
: "${BYTEBASE_PROJECT:?BYTEBASE_PROJECT is required}"
: "${BYTEBASE_TARGETS:?BYTEBASE_TARGETS is required}"
: "${BYTEBASE_DOCKER_NETWORK:?BYTEBASE_DOCKER_NETWORK is required}"
: "${BYTEBASE_ACTION_IMAGE:?BYTEBASE_ACTION_IMAGE is required}"
: "${BYTEBASE_SERVICE_ACCOUNT:?BYTEBASE_SERVICE_ACCOUNT Jenkins credential is required}"
: "${BYTEBASE_SERVICE_ACCOUNT_SECRET:?BYTEBASE_SERVICE_ACCOUNT_SECRET Jenkins credential is required}"

migration_directory="${MIGRATION_DIRECTORY:-migrations}"
action_container_id=''

mkdir -p evidence
bash ops/validate-migrations.sh

cleanup() {
    if [[ -n "${action_container_id}" ]]; then
        docker rm --force "${action_container_id}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

run_bytebase_action() {
    local command_name="$1"
    local evidence_file="$2"
    shift 2

    if ! docker image inspect "${BYTEBASE_ACTION_IMAGE}" >/dev/null 2>&1; then
        echo "Pulling Bytebase action image ${BYTEBASE_ACTION_IMAGE}..." >&2
        docker pull "${BYTEBASE_ACTION_IMAGE}" >&2
    fi

    action_container_id="$(
        docker create \
            --network "${BYTEBASE_DOCKER_NETWORK}" \
            --env BYTEBASE_SERVICE_ACCOUNT \
            --env BYTEBASE_SERVICE_ACCOUNT_SECRET \
            "${BYTEBASE_ACTION_IMAGE}" \
            "${command_name}" \
            --url "${BYTEBASE_URL}" \
            --project "${BYTEBASE_PROJECT}" \
            --targets "${BYTEBASE_TARGETS}" \
            --file-pattern '/migrations/*.sql' \
            --output /bytebase-result.json \
            "$@"
    )" || {
        echo 'Unable to create the Bytebase action container.' >&2
        action_container_id=''
        return 20
    }

    if [[ ! "${action_container_id}" =~ ^[[:xdigit:]]{64}$ ]]; then
        echo 'docker create returned an invalid container ID.' >&2
        action_container_id=''
        return 21
    fi

    docker cp "${migration_directory}" "${action_container_id}:/migrations"

    local action_status=0
    docker start --attach "${action_container_id}" || action_status=$?

    if ! docker cp "${action_container_id}:/bytebase-result.json" "${evidence_file}" 2>/dev/null; then
        printf '{"command":"%s","status":"NO_OUTPUT","exit_code":%s}\n' \
            "${command_name}" "${action_status}" > "${evidence_file}"
    fi

    docker rm "${action_container_id}" >/dev/null
    action_container_id=''
    return "${action_status}"
}

run_bytebase_action \
    check \
    evidence/bytebase-check.json \
    --check-release FAIL_ON_ERROR

if [[ "${DRY_RUN:-true}" == 'true' ]]; then
    printf '{"mode":"check-only","dry_run":true,"project":"%s","targets":"%s"}\n' \
        "${BYTEBASE_PROJECT}" "${BYTEBASE_TARGETS}" > evidence/migration-summary.json
    echo 'DRY_RUN=true: Bytebase SQL review passed; rollout was not created.'
    exit 0
fi

: "${BYTEBASE_TARGET_STAGE:?BYTEBASE_TARGET_STAGE is required for a real rollout}"

run_bytebase_action \
    rollout \
    evidence/bytebase-rollout.json \
    --target-stage "${BYTEBASE_TARGET_STAGE}"

printf '{"mode":"rollout","dry_run":false,"project":"%s","targets":"%s","target_stage":"%s"}\n' \
    "${BYTEBASE_PROJECT}" "${BYTEBASE_TARGETS}" "${BYTEBASE_TARGET_STAGE}" \
    > evidence/migration-summary.json

echo 'Bytebase rollout completed successfully.'
