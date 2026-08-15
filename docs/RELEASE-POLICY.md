# Shared Library Release Policy

ใช้ Semantic Versioning และ Git tag:

- PATCH: bug fix ที่ไม่เปลี่ยน public config contract
- MINOR: เพิ่ม optional field, strategy หรือ stage ที่ backward-compatible
- MAJOR: เปลี่ยน required field, stage order, exit/result semantics หรือ credential behavior

Consumer ต้อง pin version เช่น `@v1.4.2` ห้ามใช้ `@main` หรือ `@latest` สำหรับ production

## Release process

1. รัน `tests/template-tests.ps1`
2. ทดลองกับ fixture consumer และ `DRY_RUN=true`
3. ทดสอบ dev แล้ว staging รวม failure/rollback paths
4. บันทึก breaking change และ migration instructions
5. tag release แบบ immutable
6. upgrade consumer เป็นกลุ่ม ไม่เปลี่ยนทั้งหมดพร้อมกัน

การเปลี่ยน flow order, success/failure verdict, persistence/migration semantics หรือ
credential scope ถือเป็น behavior change และต้องผ่าน staging verification
