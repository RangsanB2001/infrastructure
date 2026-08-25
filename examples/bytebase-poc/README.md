# Bytebase CI database migration POC

POC นี้ต่อยอดจาก Jenkins Shared Library ใน repository เดิม โดยใช้ hook
`migrationCommand` ที่มีอยู่แล้ว แต่ให้ Bytebase เป็นผู้ review, rollout และบันทึก revision
ของ SQL แทนการให้ Jenkins ต่อ PostgreSQL แล้วรัน `psql` เอง

```text
Git migration files
        |
        v
Jenkins Shared Library
        |
        v
bytebase-action (ephemeral container)
        |
        v
Bytebase (SQL review + rollout + audit/revision)
        |
        v
PostgreSQL
```

## สิ่งที่เพิ่มใน POC

- `compose.yaml` — Bytebase `3.20.0` และ PostgreSQL `17.6-alpine`
- `migrations/` — migration แบบ versioned จำนวน 3 ไฟล์
- `Jenkinsfile` — thin consumer ของ Shared Library เดิม
- `ops/bytebase-migrate.sh` — `check` เมื่อ dry-run และ `check -> rollout` เมื่อรันจริง
- `ops/acceptance-test.sh` — static และ live acceptance checks
- [`../../docs/BYTEBASE-POC-RUNBOOK.md`](../../docs/BYTEBASE-POC-RUNBOOK.md) — ขั้นตอน setup/run/recover แบบละเอียด

ทั้ง Bytebase server และ `bytebase-action` ถูก pin ที่ `3.20.0` เพื่อให้ protocol เข้ากัน
และ upgrade ได้อย่างตั้งใจ

## Quick start

1. สร้าง local environment file แล้วเปลี่ยน password:

   ```powershell
   Copy-Item .env.example .env
   notepad .env
   ```

2. ตรวจ Compose และเปิด stack:

   ```powershell
   docker compose --env-file .env config --quiet
   docker compose --env-file .env up -d
   docker compose --env-file .env ps
   ```

3. เปิด `http://localhost:8080` แล้วทำ first-time setup ตาม runbook: เพิ่ม instance
   `homelab-postgres`, project `homelab`, environment `dev` และ project-level service
   account ที่มี role `GitOps Service Agent`

4. สร้าง Jenkins credential ชนิด Username with password ID `bytebase-homelab-ci`:

   - Username: email ของ Bytebase service account
   - Password: service key ที่ Bytebase แสดงตอนสร้าง account

5. สร้าง Jenkins Pipeline from SCM โดยใช้ `examples/bytebase-poc/Jenkinsfile` แล้วรัน:

   - `TARGET_ENV=dev`, `DRY_RUN=true` เพื่อตรวจ SQL โดยไม่เปลี่ยน schema
   - `TARGET_ENV=dev`, `DRY_RUN=false` เพื่อ rollout ผ่าน Bytebase

6. ตรวจผล:

   ```powershell
   docker compose --env-file .env exec postgres `
     psql -U bytebase_poc -d homelab_app -c '\d public.customer'
   ```

รายละเอียด Jenkins agent/network, Bytebase policy, acceptance criteria และ cleanup อยู่ใน
runbook หลัก

## Migration contract

ชื่อไฟล์ต้องเป็น:

```text
<12-14 digit version>_<description>.sql
```

ตัวอย่าง:

```text
202608250001_create_customer.sql
202608250002_add_customer_email.sql
```

ห้ามแก้เนื้อหา migration ที่ Bytebase rollout สำเร็จแล้ว ให้สร้าง version ใหม่เสมอ เพราะ
Bytebase ใช้ revision history และ checksum เพื่อป้องกันการ execute ซ้ำ

## Safety boundary

- Jenkins ถือเฉพาะ Bytebase service account; ไม่มี PostgreSQL password ใน Jenkinsfile
- `ops/bytebase-migrate.sh` ไม่เรียก `psql`
- การ query PostgreSQL ใน `verify-migration.sh` เป็น read-only acceptance check หลัง rollout
- POC ปิด automatic schema rollback เพราะ application rollback ไม่สามารถย้อน DDL ที่ commit
  ไปแล้วได้อย่างปลอดภัย
- `.env`, Bytebase metadata และ PostgreSQL data ไม่ถูก commit เข้า Git
