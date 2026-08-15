# Operations Runbook

## ก่อน deploy

- ยืนยัน `TARGET_ENV`, commit SHA, artifact fingerprint และ release owner
- ตรวจ change ticket, maintenance window และ downstream dependency
- ตรวจ backup/restore point และ version ก่อนหน้า
- รัน `DRY_RUN=true` แล้ว review command plan
- สำหรับ migration ให้ยืนยัน lock behavior, duration และ backward compatibility บน staging

## ระหว่าง deploy

1. ติดตาม stage duration และ target health
2. ห้ามคัดลอก secret จาก Jenkins console ไปยัง ticket/chat
3. หาก approval timeout ให้เริ่ม run ใหม่ ไม่ bypass gate
4. หาก migration สำเร็จแต่ deploy fail ให้ใช้ recovery plan ของ migration ไม่สมมติว่า
   application rollback จะย้อน schema ได้

## Success criteria

- deploy command exit `0`
- health verification และ smoke test ผ่าน
- artifact/image version ใน target ตรง build ที่อนุมัติ
- error rate, latency และ dependency health อยู่ใน threshold
- evidence ถูก archive และมีผู้รับผิดชอบตรวจผล

## Failure และ rollback

Shared Library จะพยายาม automatic rollback เมื่อ target mutation เริ่มแล้วและ stage ต่อมา
ล้มเหลว แต่จะไม่เปลี่ยน failure ต้นเหตุเป็น success

ถ้า rollback ล้มเหลว:

1. หยุด promotion และประกาศ incident
2. freeze target deployment
3. ตรวจ `evidence/rollback.json` และ Jenkins console โดย mask secret
4. ใช้ tested manual recovery procedure ของระบบ
5. verify target state ก่อนประกาศ restored
6. เก็บ timeline, command, version และ decision owner

## Post-deploy observation

ขั้นต่ำ 15-30 นาทีหรือตาม criticality:

- availability และ health endpoint
- error rate / exception count
- latency และ saturation
- queue lag / job freshness สำหรับ worker และ data pipeline
- database connection, lock และ migration error
- business reconciliation หรือ data-quality result เมื่อเกี่ยวข้อง

## Evidence record

ทุก production run ควรตอบได้ว่าใคร deploy อะไร เมื่อไร ไปที่ไหน และผลเป็นอย่างไร:

```json
{
  "application": "my-service",
  "environment": "prod",
  "build_tag": "jenkins-my-service-421",
  "git_commit": "abc123",
  "artifact_digest": "sha256:...",
  "approved_by": "operator-id",
  "started_at": "2026-08-15T10:00:00Z",
  "finished_at": "2026-08-15T10:08:00Z",
  "status": "SUCCESS"
}
```
