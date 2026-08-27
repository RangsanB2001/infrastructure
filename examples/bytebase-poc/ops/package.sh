#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p out

file_count="$(find migrations -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')"
printf '{"component":"bytebase-migration-poc","migration_files":%s,"git_commit":"%s"}\n' \
    "${file_count}" "${GIT_COMMIT:-unknown}" > out/migration-package.json

echo "Packaged ${file_count} migration file(s)."
