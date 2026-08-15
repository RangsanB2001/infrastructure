# Adoption Guide

## 1. เตรียม Jenkins

ขั้นต่ำควรมี Jenkins Pipeline, Git, Credentials Binding และ JUnit plugins รวมถึง agent
ที่มี tool ของ deployment target เช่น Docker, kubectl, Helm, Terraform หรือ PowerShell

สร้าง Global Trusted Pipeline Library ชื่อ `infra-ops-pipeline` ชี้ไป repository นี้ และ
กำหนด default version เป็น release tag ที่ผ่านการทดสอบ หลีกเลี่ยง implicit loading เพื่อให้
consumer ระบุ version เองใน source control

## 2. กำหนด agent boundary

- build agent เข้าถึง source/package feed แต่ไม่จำเป็นต้องเข้าถึง production
- deploy agent เข้าถึง target environment เท่าที่ต้องใช้
- production credentials ใช้ folder/job scope และ least privilege
- ห้าม reuse production credential ใน dev/uat

## 3. สร้าง consumer

ใช้ generator จาก root ของ Shared Library:

```powershell
./scripts/New-PipelineConsumer.ps1 `
  -ApplicationName 'my-service' `
  -Destination 'D:\work\my-service' `
  -ProjectFile 'src\MyService\MyService.csproj' `
  -TestProjectFile 'tests\MyService.Tests\MyService.Tests.csproj'
```

Generator จะปฏิเสธ directory ที่มีไฟล์อยู่แล้วเพื่อลดความเสี่ยงเขียนทับงาน

## 4. เติม environment contract

ต่อหนึ่ง environment ต้องระบุ agent, deploy command, verify command และ rollback command
ถ้ามี migration ให้แยก command และ approval ออกจาก deploy ไม่ซ่อน migration ไว้ใน
application startup

Credential configuration ต้องบรรจุเฉพาะ Jenkins credential ID:

```groovy
credentials: [[
    type: 'usernamePassword',
    id: 'container-registry-prod',
    usernameVariable: 'REGISTRY_USERNAME',
    passwordVariable: 'REGISTRY_PASSWORD'
]]
```

รองรับ `string`, `file` และ `usernamePassword`

## 5. Promotion path

1. เปิด Multibranch Pipeline หรือ Pipeline from SCM
2. รัน `dev` ด้วย `DRY_RUN=true`
3. รัน `dev` แบบ mutation และตรวจ evidence
4. promote artifact fingerprint เดิมไป `uat`
5. ซ้อม migration และ rollback บน staging
6. เปิด production หลัง runbook, owner และ monitoring พร้อม

อย่า rebuild คนละ artifact ต่อ environment หากต้องการ provenance ที่ตรวจสอบย้อนหลังได้

## 6. Definition of done

- Jenkinsfile ของ consumer เหลือ configuration และไม่มี business logic
- secret ไม่อยู่ใน Git, parameter หรือ log
- approval ไม่ถือ executor
- deploy, verify และ rollback คืน non-zero เมื่อไม่สำเร็จ
- migration idempotent หรือมี recovery plan ที่ซ้อมแล้ว
- health check และ read-only smoke test สะท้อนความพร้อมใช้งานจริง
- evidence ระบุ application, environment, build, commit และ deployed version
- Shared Library ถูก pin ด้วย tag และมี migration note เมื่อ breaking change
