# Infra Operations Pipeline Template

Reusable Jenkins Shared Library สำหรับมาตรฐาน build, test, approval, migration,
deploy, verification และ rollback โดยให้ Jenkinsfile ของแต่ละระบบเก็บเฉพาะสิ่งที่
แตกต่างจริง

## สิ่งที่โปรเจกต์นี้แก้ให้

- ไม่ต้องคัดลอก pipeline flow ไปทุก repository
- approval เกิดนอก `node` จึงไม่จอง executor ระหว่างรอ
- deploy ทุก environment ใช้ contract เดียวกัน แต่กำหนด command และ agent แยกได้
- secret ถูก bind เฉพาะ deploy stage และไม่เก็บค่าจริงใน source control
- production เริ่มต้นด้วย `DRY_RUN=true` และรองรับ automatic rollback เมื่อ verify fail
- Shared Library ถูก pin ด้วย version เพื่อไม่ให้การแก้ส่วนกลางกระทบทุก job พร้อมกัน

## โครงสร้าง

```text
vars/infraPipeline.groovy             public API ของ Shared Library
src/com/company/infra/config/         config schema และ validation
src/com/company/infra/core/           orchestration flow
src/com/company/infra/runtime/        command/credential adapter
examples/consumer-project/            thin Jenkinsfile และ deploy scripts ตัวอย่าง
scripts/New-PipelineConsumer.ps1      สร้าง starter files ให้ repository ใหม่
tests/template-tests.ps1              static safety และ structure checks
docs/                                 adoption, runbook, release policy และ playbook
```

## เริ่มใช้งานเร็ว

### 1. สร้าง repository สำหรับ Shared Library

นำโปรเจกต์นี้ขึ้น Git จากนั้นตั้งค่าใน Jenkins:

```text
Manage Jenkins
  -> System
  -> Global Trusted Pipeline Libraries
  -> Name: infra-ops-pipeline
  -> Default version: v0.1.0
  -> Retrieval method: Modern SCM / Git
```

แนะนำให้ปิด implicit loading แล้วให้ consumer pin version ใน Jenkinsfile อย่างชัดเจน

### 2. สร้าง starter ให้ application repository

```powershell
./scripts/New-PipelineConsumer.ps1 `
  -ApplicationName "market-data-api" `
  -Destination "D:\work\market-data-api" `
  -LibraryName "infra-ops-pipeline" `
  -LibraryVersion "v0.1.0"
```

สคริปต์จะสร้าง `Jenkinsfile` และ `ops/*.sh` โดยไม่เขียนทับ directory ที่มีไฟล์อยู่แล้ว

### 3. แก้ config ของระบบ

แก้เฉพาะส่วนต่อไปนี้ใน Jenkinsfile ที่สร้างขึ้น:

- build/test/package commands
- Jenkins agent labels
- environment URLs
- credential IDs (ชื่ออ้างอิงเท่านั้น ไม่ใช่ secret)
- deploy, migration, verify และ rollback commands

### 4. ตรวจ template

```powershell
./tests/template-tests.ps1
```

## Pipeline flow

```text
Validate request
  -> Checkout / Build / Test / Package
  -> Approval (outside node)
  -> Migration approval (outside node, when enabled)
  -> Deploy
  -> Verify / Smoke test
  -> Archive evidence

On failure after mutation starts
  -> Automatic rollback
  -> Preserve original failure
```

## Public API

Consumer เรียก `infraPipeline(Map config)` ดูตัวอย่างเต็มที่
[`examples/consumer-project/Jenkinsfile`](examples/consumer-project/Jenkinsfile)

ฟิลด์หลัก:

| Field | Required | ความหมาย |
| --- | --- | --- |
| `applicationName` | yes | ชื่อระบบที่ใช้ใน log และ build description |
| `buildAgent` | yes | label ของ agent สำหรับ checkout/build/test/package |
| `commands.build/test/package` | yes | งานจริงที่รันบน agent |
| `environments` | yes | deploy contract แยกตาม environment |
| `defaultEnvironment` | no | ค่าเริ่มต้นของ `TARGET_ENV`; default `dev` |
| `artifactIncludes` | no | files ที่ stash จาก build ไป deploy |
| `testResults` | no | JUnit glob; เว้นว่างได้ |
| `rollbackOnFailure` | no | rollback เมื่อ deploy/verify fail; default `true` |
| `pipelineTimeoutMinutes` | no | timeout ของ run ทั้งเส้น; default 60 |

Environment contract:

| Field | Required | ความหมาย |
| --- | --- | --- |
| `agentLabel` | yes | agent ที่เข้าถึง target environment ได้ |
| `deployCommand` | yes | deploy implementation ของระบบ |
| `verifyCommand` | yes | health/contract verification หลัง deploy |
| `rollbackCommand` | when rollback enabled | คืน version ที่ทราบว่าใช้งานได้ |
| `approvalRequired` | no | manual gate ก่อน deploy |
| `migrationCommand` | no | migration ที่รันก่อน deploy |
| `migrationApprovalRequired` | no | gate แยกสำหรับ migration |
| `credentials` | no | Jenkins credential binding เฉพาะ deploy node |

## Safety defaults

- `DRY_RUN` default เป็น `true`
- deploy environment ต้องเลือกจาก allow-list ที่ประกาศใน code
- config ถูก validate ก่อนจอง build agent
- approval และ migration approval มี timeout
- deploy/verify failure ไม่ถูกกลืนเป็น success
- rollback failure ไม่ทับสาเหตุ failure เดิม
- scripts ตัวอย่างไม่บรรจุ credential และจะ fail หาก placeholder สำคัญยังไม่ได้ตั้งค่า

อ่านขั้นตอน onboarding ที่ [`docs/ADOPTION.md`](docs/ADOPTION.md) และเหตุฉุกเฉินที่
[`docs/OPERATIONS-RUNBOOK.md`](docs/OPERATIONS-RUNBOOK.md) ก่อนเปิดระบบใหม่ให้กรอก
[`docs/PIPELINE-PROFILE.md`](docs/PIPELINE-PROFILE.md) เพื่อบันทึก owner, environment,
migration, rollback และ observability contract

## ขอบเขต

Shared Library นี้เป็น control plane: มันจัดลำดับ, timeout, credential binding,
approval และผลลัพธ์ของ stage ส่วน build/deploy/data processing จริงต้องอยู่ใน script,
container, .NET/Python/Go tool หรือ deployment tool ของระบบนั้น

สำหรับ Kubernetes, Windows Service, Terraform หรือ data pipeline ให้เปลี่ยน external
commands โดยรักษา success/failure contract เดิม ไม่เพิ่มเงื่อนไขตามชื่อ application ใน
Shared Library
