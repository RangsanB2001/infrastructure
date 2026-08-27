#!/usr/bin/env bash
set -Eeuo pipefail

migration_directory="${MIGRATION_DIRECTORY:-migrations}"

if [[ ! -d "${migration_directory}" ]]; then
    echo "Migration directory does not exist: ${migration_directory}" >&2
    exit 10
fi

mapfile -t migration_files < <(find "${migration_directory}" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort)

if (( ${#migration_files[@]} == 0 )); then
    echo "No SQL migrations were found in ${migration_directory}" >&2
    exit 11
fi

previous_version=''
for migration_file in "${migration_files[@]}"; do
    if [[ ! "${migration_file}" =~ ^([0-9]{12,14})_[a-z0-9][a-z0-9_-]*\.sql$ ]]; then
        echo "Invalid migration filename: ${migration_file}" >&2
        echo 'Expected: <12-14 digit version>_<description>.sql' >&2
        exit 12
    fi

    version="${BASH_REMATCH[1]}"
    if [[ "${version}" == "${previous_version}" ]]; then
        echo "Duplicate migration version: ${version}" >&2
        exit 13
    fi
    previous_version="${version}"

    if [[ ! -s "${migration_directory}/${migration_file}" ]]; then
        echo "Migration file is empty: ${migration_file}" >&2
        exit 14
    fi
done

printf 'Validated %s ordered migration file(s).\n' "${#migration_files[@]}"
