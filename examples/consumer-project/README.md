# Consumer starter

ไฟล์ชุดนี้ถูกออกแบบให้สร้างผ่าน `scripts/New-PipelineConsumer.ps1` แล้วนำไปวางใน
application repository

ก่อนเปิดใช้ deploy จริง:

1. แก้ project/test paths และ commands ใน `Jenkinsfile`
2. เปลี่ยน URL และ registry placeholders
3. ผูก credential IDs ใน Jenkins โดยไม่เก็บ secret ใน Git
4. ทำให้ `MIGRATION_COMMAND` idempotent และทดสอบบน staging
5. ให้ release registry หรือ deployment inventory เติม `PREVIOUS_IMAGE_TAG`
6. เริ่มด้วย `DRY_RUN=true`, ตรวจ output แล้วจึงอนุมัติ mutation

`ops/*.sh` เป็น adapter ตัวอย่างสำหรับ Docker Compose สามารถแทนที่ด้วย Helm,
kubectl, Terraform, Ansible หรือ PowerShell โดยต้องรักษา exit-code contract:

- `0` สำเร็จ
- non-zero ล้มเหลว และ Jenkins ต้องไม่แสดงผลสำเร็จปลอม
