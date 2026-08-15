# Security Policy

## Secrets

- เก็บค่าจริงใน Jenkins Credentials หรือ secret manager เท่านั้น
- source control เก็บได้เฉพาะ credential ID และชื่อตัวแปร
- จำกัด credential ตาม folder/job/environment และใช้ least privilege
- rotate ทันทีหากค่าจริงเคยปรากฏใน repository หรือ console log
- ห้ามส่ง secret ผ่าน free-text build parameter

## Pipeline changes

การแก้ Shared Library มี blast radius สูง ควรใช้ protected branch, required review,
signed/immutable release tag และแยกผู้อนุมัติ production จากผู้สร้าง change เมื่อทำได้

## Reporting

รายงานช่องโหว่ผ่านช่องทาง security ภายในองค์กร ห้ามเปิด issue สาธารณะที่มี credential,
internal URL, topology หรือ exploit detail
