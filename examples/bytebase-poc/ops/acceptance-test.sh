#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-static}"

case "${mode}" in
    static)
        bash ops/validate-migrations.sh

        grep -Fq "migrationCommand: 'cd examples/bytebase-poc && bash ops/bytebase-migrate.sh'" Jenkinsfile
        grep -Fq 'bytebase/bytebase-action:3.20.0' Jenkinsfile
        grep -Fq 'FAIL_ON_ERROR' ops/bytebase-migrate.sh
        grep -Fq 'rollout' ops/bytebase-migrate.sh

        if grep -Eqi '\bpsql\b' ops/bytebase-migrate.sh; then
            echo 'Migration path must not call psql directly.' >&2
            exit 40
        fi

        echo 'Static Jenkins -> Bytebase delegation checks passed.'
        ;;
    live)
        if [[ "${DRY_RUN:-true}" == 'true' ]]; then
            bash ops/verify-migration.sh
            exit 0
        fi

        if [[ ! -s evidence/bytebase-rollout.json ]]; then
            echo 'Missing Bytebase rollout evidence.' >&2
            exit 41
        fi

        if grep -Fq '"status":"NO_OUTPUT"' evidence/bytebase-rollout.json; then
            echo 'Bytebase rollout did not produce resource evidence.' >&2
            exit 42
        fi

        bash ops/verify-migration.sh
        echo 'Live Jenkins -> Bytebase -> PostgreSQL acceptance checks passed.'
        ;;
    *)
        echo "Unknown acceptance mode: ${mode} (expected static or live)" >&2
        exit 43
        ;;
esac
