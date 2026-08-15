#!/usr/bin/env bash
set -Eeuo pipefail

: "${PREVIOUS_IMAGE_TAG:?PREVIOUS_IMAGE_TAG is required for rollback}"
: "${CONTAINER_REGISTRY:?CONTAINER_REGISTRY is required}"

if [[ "${PREVIOUS_IMAGE_TAG}" == \<* ]]; then
    echo "PREVIOUS_IMAGE_TAG was not resolved from the release registry" >&2
    exit 30
fi

COMPOSE_FILE="${COMPOSE_FILE:-deploy/docker-compose.yml}"
IMAGE_TAG="${PREVIOUS_IMAGE_TAG}"
export IMAGE_TAG

docker compose -f "${COMPOSE_FILE}" pull
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans

mkdir -p evidence
printf '{"environment":"%s","rollback_image_tag":"%s","status":"ATTEMPTED"}\n' \
    "${TARGET_ENV:-unknown}" "${PREVIOUS_IMAGE_TAG}" > evidence/rollback.json
