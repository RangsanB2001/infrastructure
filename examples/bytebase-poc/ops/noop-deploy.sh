#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p evidence

printf '{"application":"%s","environment":"%s","dry_run":%s,"status":"NO_APPLICATION_DEPLOY"}\n' \
    "${APPLICATION_NAME:-bytebase-migration-poc}" \
    "${TARGET_ENV:-dev}" \
    "${DRY_RUN:-true}" \
    > evidence/deployment.json

echo 'Schema-only POC: there is no application artifact to deploy.'
