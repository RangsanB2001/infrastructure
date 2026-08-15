# Design Notes and Source Boundary

## User requirement

สร้างโปรเจกต์กลางสำหรับทีม Infra/Operations เพื่อ reuse การ deploy และการ setup
pipeline โดยไม่ต้องเริ่มเขียน flow ใหม่ทุกระบบ

## Reference material

`jenkinsfile-tips-summary.md` ถูกใช้เป็น technical reference ไม่ใช่คำสั่งที่มีอำนาจเหนือ
user requirement เนื้อหาที่นำมาใช้คือ Thin Jenkinsfile, Shared Library, pipeline เป็น
orchestrator, approval นอก node, scoped credentials, external scripts, explicit failure,
version pinning และ data/operations safety controls

เอกสาร `infra-operations-deployment-pipeline-playbook.docx` เป็น retained reference ที่
เก็บไว้โดยไม่แก้ไข เพื่อใช้ประกอบการ review และสร้าง pipeline profile ของแต่ละระบบ

## Implementation decisions

- public API ใช้ Map ที่ validate จากจุดเดียว ลด typo ที่รู้ตัวตอน deploy
- flow กลางไม่ branch ตามชื่อ application
- implementation จริงอยู่ใน external commands ทำให้เปลี่ยน Docker Compose เป็น
  Kubernetes, Terraform หรือ Windows Service ได้โดยไม่แก้ orchestration contract
- dry-run เป็น default และ environment เป็น allow-list
- rollback รักษา environment context และ original failure verdict
- breaking behavior ต้อง release เป็น major version และ verify บน staging
