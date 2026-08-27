# Bytebase CI Database Migration POC Runbook

## เป้าหมายและขอบเขต

พิสูจน์ flow ต่อไปนี้บน HomeLab โดยไม่เปลี่ยน orchestration หลักของ Shared Library:

```text
Jenkins
  -> Bytebase SQL review
  -> Bytebase release / plan / rollout
  -> PostgreSQL migration
  -> schema verification + evidence
```

POC นี้เป็น schema-only consumer จึงใช้ `noop-deploy.sh` ใน application deploy stage
และตั้ง `rollbackOnFailure: false` โดยตั้งใจ การ rollback application image ไม่ได้ย้อน schema
ที่ commit แล้ว ต้องใช้ forward-fix หรือ reverse migration ที่ review แยกต่างหาก

## Component และ version

| Component | Version / contract | หน้าที่ |
| --- | --- | --- |
| Jenkins Shared Library | commit `35b5d7e5ec74044684982ff3c5779123acfffdf0` | orchestration, dry-run, credential scope, evidence |
| Bytebase server | `3.20.0` | SQL review, release, plan, rollout, audit/revision |
| bytebase-action | `3.20.0` | CI client ที่ Jenkins เรียกผ่าน ephemeral container |
| PostgreSQL | `17.6-alpine` | target database ของ POC |

ก่อน upgrade Bytebase ให้อ่าน release notes, backup volume `bytebase-data` และขยับ
server/action ไปด้วยกัน หลัง upgrade ให้รัน dry-run และ live acceptance ใหม่

## Prerequisites

- Docker Engine 20.10.24 ขึ้นไป พร้อม Docker Compose v2
- Jenkins Linux agent label `linux && docker`
- Jenkins agent ใช้ Docker daemon เดียวกับ Compose stack หรือเข้าถึง Docker network
  `bytebase-poc` ได้
- Shared Library ชื่อ `infra-ops-pipeline` ชี้มาที่ repository นี้
- port `8080` และ `55432` ว่าง หรือแก้ใน `.env`

script ใช้ `docker create` + `docker cp` แทน workspace bind mount จึงทำงานได้กับ Jenkins
ที่อยู่ใน container และ mount Docker socket โดยไม่ต้องให้ host/container มี workspace path ตรงกัน

## 1. Start stack

จาก `examples/bytebase-poc`:

```powershell
Copy-Item .env.example .env
notepad .env
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d
docker compose --env-file .env ps
```

เปลี่ยน `POSTGRES_PASSWORD` ก่อน start ทุกครั้ง ค่าใน `.env.example` เป็น placeholder เท่านั้น
Compose สร้าง named volumes แยกสำหรับ PostgreSQL และ Bytebase metadata

ตรวจ log เมื่อ service ไม่พร้อม:

```powershell
docker compose --env-file .env logs --tail 100 postgres
docker compose --env-file .env logs --tail 100 bytebase
```

## 2. First-time Bytebase setup

เปิด `http://localhost:8080`:

1. สร้าง workspace admin สำหรับ HomeLab
2. สร้าง environment ชื่อ `Dev` และใช้ resource ID `dev`
3. เพิ่ม PostgreSQL instance:
   - Instance name: `homelab-postgres`
   - Resource ID used by this HomeLab: `homelab-postgres-d8hm`
   - Host: `postgres`
   - Port: `5432`
   - Username / Password: `POSTGRES_USER` และ `POSTGRES_PASSWORD` จาก `.env`
   - Environment: `dev`
4. ตรวจว่า Bytebase discover database `homelab_app`
5. ใช้ project ชื่อ `poc-mrigation-ci-cd` (resource ID `poc-mrigation-ci-cd-7nxf`)
   แล้ว transfer `homelab_app` เข้า project
6. ใน project settings สำหรับ POC:
   - เปิด `Require plan check no error`
   - ปิด `Require issue approval` เฉพาะ environment `dev` เพื่อให้ Jenkins รัน POC จบได้
   - อย่าเปิด automatic rollout สำหรับ GitOps flow; `bytebase-action` เป็นผู้สั่ง stage
7. ตั้ง SQL Review policy ขั้นต่ำให้ syntax/error เป็น blocking และเพิ่ม rule ตามมาตรฐานทีม

resource names ต้องตรง `examples/bytebase-poc/Jenkinsfile`:

```text
projects/poc-mrigation-ci-cd-7nxf
instances/homelab-postgres-d8hm/databases/homelab_app
environments/dev
```

หากใช้ ID อื่น ให้แก้เฉพาะค่า `BYTEBASE_PROJECT`, `BYTEBASE_TARGETS` และ
`BYTEBASE_TARGET_STAGE` ใน Jenkinsfile

## 3. Create least-privilege CI identity

ใน Bytebase ไปที่ project `homelab` -> Manage -> Service Accounts:

1. สร้าง project-level service account เช่น `jenkins-homelab@service.bytebase.com`
2. ให้ role `GitOps Service Agent`
3. copy service key ตอนที่ Bytebase แสดง และเก็บเข้า Jenkins ทันที
4. ไม่ใช้ Workspace Admin/DBA สำหรับ pipeline

ใน Jenkins สร้าง credential:

| Field | Value |
| --- | --- |
| Kind | Username with password |
| ID | `bytebase-homelab-ci` |
| Username | service account email |
| Password | Bytebase service key |
| Scope | folder/job ของ POC |

Jenkins Shared Library จะ bind credential เฉพาะ migration/deploy node และ mask ค่าใน log
ตัว script ส่ง service key เข้า action container ผ่าน environment variable ตาม contract ของ
`bytebase-action`; ไม่วาง secret เป็น command argument หรือ source-controlled variable

## 4. Configure Jenkins job

สร้าง Pipeline from SCM หรือ Multibranch Pipeline ชี้ repository นี้และกำหนด Script Path:

```text
examples/bytebase-poc/Jenkinsfile
```

Jenkinsfile pin Shared Library ด้วย commit SHA ของ baseline เดิม เมื่อ publish POC เป็น release
แล้วควรเปลี่ยนเป็น immutable release tag ของทีม เช่น `v0.2.0`

agent ต้องมองเห็น Docker network:

```powershell
docker network inspect bytebase-poc
```

หาก Bytebase อยู่คนละ Docker host ให้:

- เปลี่ยน `BYTEBASE_URL` เป็น URL ที่ Jenkins agent เข้าถึงได้
- เอา `--network` design ไปปรับใน `ops/bytebase-migrate.sh` หรือสร้าง network ที่ route ได้
- ใช้ TLS/reverse proxy และห้ามส่ง service key ผ่าน HTTP ข้ามเครื่อง

## 5. Run flow

### Dry-run / SQL review

รัน Jenkins ด้วย:

```text
TARGET_ENV=dev
DRY_RUN=true
```

ผลที่คาดหวัง:

1. validate รูปแบบและลำดับ migration
2. สร้าง ephemeral `bytebase-action` container
3. Bytebase `check --check-release FAIL_ON_ERROR`
4. ได้ `evidence/bytebase-check.json`
5. ไม่มี release/rollout และ schema ยังไม่เปลี่ยน

### Real rollout

รัน Jenkins ด้วย:

```text
TARGET_ENV=dev
DRY_RUN=false
```

ผลที่คาดหวัง:

1. SQL review ผ่าน
2. `bytebase-action rollout` สร้าง Bytebase release, plan และ rollout
3. action รอจน stage `environments/dev` เสร็จ
4. Bytebase apply migration ตาม version และบันทึก revision
5. Jenkins query แบบ read-only เพื่อยืนยัน table/columns/index
6. Jenkins archive `evidence/bytebase-*.json` และ `schema-verification.json`

## Acceptance tests

| ID | วิธีทดสอบ | Expected result |
| --- | --- | --- |
| AT-01 | `docker compose --env-file .env config --quiet` | Compose valid |
| AT-02 | รัน `tests/bytebase-poc-tests.ps1` จาก root | structure, pinning, secret boundary, naming ผ่าน |
| AT-03 | Jenkins `DRY_RUN=true` | SQL review ผ่าน, ไม่มี schema mutation |
| AT-04 | เพิ่ม SQL ที่ผิด syntax แล้ว dry-run | Bytebase check fail และ Jenkins เป็น failure |
| AT-05 | Jenkins `DRY_RUN=false` | `public.customer` มี 4 columns และ unique partial index |
| AT-06 | รัน real rollout ซ้ำด้วย migration ชุดเดิม | Bytebase skip revision เดิมและ job ยังผ่าน |
| AT-07 | ดู Bytebase CI/CD / Releases และ Changelog | เห็น release/plan/rollout/revision ที่ trace กลับ commit ได้ |

Static acceptance บน Linux:

```bash
bash ops/acceptance-test.sh static
```

หลัง real rollout Jenkins เรียก live acceptance ให้อัตโนมัติ หากต้องการตรวจเองบน deploy
agent ให้มี `evidence/bytebase-rollout.json` แล้วรัน:

```bash
DRY_RUN=false \
COMPOSE_PROJECT_NAME=bytebase-poc \
POC_POSTGRES_DB=homelab_app \
POC_POSTGRES_USER=bytebase_poc \
bash ops/acceptance-test.sh live
```

## Failure handling

### Bytebase check fail

- เปิด `evidence/bytebase-check.json` และ plan check ใน Bytebase
- แก้โดยสร้าง/แก้ migration ที่ยังไม่เคย rollout
- ห้าม bypass error เพื่อให้ acceptance ผ่าน

### Rollout fail ก่อน execute

- ตรวจ service account role, project/target/stage IDs และ Docker network
- ตรวจว่า server/action version เข้ากัน
- retry ได้หลังแก้ configuration เพราะ revision จะถูกสร้างเฉพาะ migration ที่สำเร็จ

### Rollout fail หลังบาง migration สำเร็จ

- หยุด deploy application
- ตรวจ task/revision ต่อไฟล์ใน Bytebase ก่อน retry
- ใช้ forward-fix migration version ใหม่เป็นค่าเริ่มต้น
- ใช้ reverse migration เฉพาะเมื่อ review และซ้อมแล้ว; อย่าลบ Bytebase revision ด้วยมือ

### Drift จากการแก้ PostgreSQL ตรง

- sync schema ใน Bytebase และตรวจ drift/changelog
- หยุด pipeline หาก state จริงไม่ตรง migration history
- สร้าง reconciliation migration ที่ review ได้แทนการแก้ revision record

## Evidence ที่ต้องเก็บ

```text
evidence/bytebase-check.json
evidence/bytebase-rollout.json
evidence/migration-summary.json
evidence/deployment.json
evidence/schema-verification.json
```

ห้าม archive `.env`, service key, PostgreSQL password หรือ full Docker inspect output

## Stop and cleanup

หยุด service โดยเก็บ data:

```powershell
docker compose --env-file .env down
```

การลบ volumes จะลบทั้ง database และ Bytebase audit/revision history จึงไม่รวมไว้ในคำสั่ง
cleanup ปกติ ถ้าต้อง reset POC ให้ backup evidence/metadata ก่อน แล้วลบ volumes ด้วยคำสั่งที่
ผู้ดูแลตรวจ target ชัดเจนแล้วเท่านั้น

## Official references

- [Deploy Bytebase with Docker](https://docs.bytebase.com/get-started/self-host/deploy-with-docker)
- [Migration-based GitOps release](https://docs.bytebase.com/gitops/migration-based-workflow/release)
- [Bytebase action command and flag contract](https://github.com/bytebase/bytebase/blob/main/action/README.md)
- [Service accounts](https://docs.bytebase.com/administration/service-account)
- [Roles and permissions](https://docs.bytebase.com/administration/roles)
