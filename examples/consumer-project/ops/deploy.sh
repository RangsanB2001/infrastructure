#!/usr/bin/env bash
set -Eeuo pipefail

: "${APPLICATION_NAME:?APPLICATION_NAME is required}"
: "${TARGET_ENV:?TARGET_ENV is required}"
: "${CONTAINER_REGISTRY:?CONTAINER_REGISTRY is required}"

COMPOSE_FILE="${COMPOSE_FILE:-deploy/docker-compose.yml}"
IMAGE_TAG="${IMAGE_TAG:-${BUILD_TAG:-}}"
: "${IMAGE_TAG:?IMAGE_TAG or BUILD_TAG is required}"
export IMAGE_TAG

mkdir -p evidence

if [[ "${DRY_RUN:-true}" == "true" ]]; then
    echo "DRY RUN: validate ${COMPOSE_FILE} for ${APPLICATION_NAME}/${TARGET_ENV} with image ${IMAGE_TAG}"
    docker compose -f "${COMPOSE_FILE}" config --quiet
    exit 0
fi

: "${REGISTRY_USERNAME:?REGISTRY_USERNAME Jenkins credential is required}"
: "${REGISTRY_PASSWORD:?REGISTRY_PASSWORD Jenkins credential is required}"

printf '%s' "${REGISTRY_PASSWORD}" | docker login "${CONTAINER_REGISTRY}" \
    --username "${REGISTRY_USERNAME}" --password-stdin

docker compose -f "${COMPOSE_FILE}" pull
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans
docker logout "${CONTAINER_REGISTRY}" >/dev/null 2>&1 || true

printf '{"application":"%s","environment":"%s","image_tag":"%s","build_tag":"%s"}\n' \
    "${APPLICATION_NAME}" "${TARGET_ENV}" "${IMAGE_TAG}" "${BUILD_TAG:-}" \
    > evidence/deployment.json
