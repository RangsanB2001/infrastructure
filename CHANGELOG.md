# Changelog

## Unreleased

- add a HomeLab Bytebase CI migration POC that reuses the existing Shared Library migration hook
- add versioned PostgreSQL migrations, Jenkins-to-Bytebase delegation, evidence, and acceptance tests
- add a Bytebase operations runbook and Compose validation to repository CI

## 0.1.0 - 2026-08-15

- initial Jenkins Shared Library project
- thin consumer Jenkinsfile generator
- build, test, package, approval, migration, deploy, verify and rollback flow
- scoped Jenkins credential bindings
- safe dry-run default and allow-listed environments
- Docker Compose consumer example, runbook and static safety checks
