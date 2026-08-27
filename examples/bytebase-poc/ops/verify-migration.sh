#!/usr/bin/env bash
set -Eeuo pipefail

: "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME is required}"
: "${POC_POSTGRES_DB:?POC_POSTGRES_DB is required}"
: "${POC_POSTGRES_USER:?POC_POSTGRES_USER is required}"

mkdir -p evidence

if [[ "${DRY_RUN:-true}" == 'true' ]]; then
    printf '{"status":"SKIPPED","reason":"DRY_RUN"}\n' > evidence/schema-verification.json
    echo 'DRY_RUN=true: live PostgreSQL schema verification skipped.'
    exit 0
fi

# Compose requires the variable while parsing, but the read-only check runs through
# the local socket inside the existing PostgreSQL container and never uses this value.
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-not-used-for-local-verification}"

psql_in_postgres() {
    docker compose \
        --project-name "${COMPOSE_PROJECT_NAME}" \
        -f compose.yaml \
        exec -T postgres \
        psql \
        --username "${POC_POSTGRES_USER}" \
        --dbname "${POC_POSTGRES_DB}" \
        --set ON_ERROR_STOP=1 \
        --tuples-only \
        --no-align \
        --command "$1"
}

table_exists="$(psql_in_postgres "SELECT to_regclass('public.customer') IS NOT NULL;")"
column_count="$(psql_in_postgres "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'customer' AND column_name IN ('customer_id', 'name', 'created_at', 'email');")"
index_exists="$(psql_in_postgres "SELECT to_regclass('public.customer_email_uq') IS NOT NULL;")"

if [[ "${table_exists}" != 't' || "${column_count}" != '4' || "${index_exists}" != 't' ]]; then
    printf 'Schema verification failed: table=%s columns=%s index=%s\n' \
        "${table_exists}" "${column_count}" "${index_exists}" >&2
    exit 30
fi

printf '{"status":"PASS","table":"public.customer","column_count":%s,"index":"public.customer_email_uq"}\n' \
    "${column_count}" > evidence/schema-verification.json

echo 'PostgreSQL schema verification passed.'
