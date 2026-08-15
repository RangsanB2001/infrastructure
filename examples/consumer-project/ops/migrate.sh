#!/usr/bin/env bash
set -Eeuo pipefail

: "${MIGRATION_COMMAND:?MIGRATION_COMMAND is required}"

if [[ "${MIGRATION_COMMAND}" == \<* ]]; then
    echo "MIGRATION_COMMAND still contains a template placeholder" >&2
    exit 10
fi

if [[ "${DRY_RUN:-true}" == "true" ]]; then
    echo "DRY RUN: migration command validated but not executed"
    exit 0
fi

# MIGRATION_COMMAND is trusted, reviewed source-controlled configuration.
# Do not populate it from a free-text Jenkins parameter.
bash -Eeuo pipefail -c "${MIGRATION_COMMAND}"
