# Pipeline Profile

คัดลอกไฟล์นี้ไปยัง consumer repository แล้วเติมข้อมูลก่อนเปิด production

## Identity

- Application / service:
- Repository:
- Business owner:
- Technical owner:
- Operations owner:
- Criticality / SLA:
- Change-ticket system:

## Environments

| Environment | Agent label | Target | Approval owner | Credential IDs | Health URL |
| --- | --- | --- | --- | --- | --- |
| dev |  |  |  |  |  |
| uat |  |  |  |  |  |
| prod |  |  |  |  |  |

## Artifact contract

- Artifact/image name:
- Immutable version format:
- Registry/repository:
- Build command:
- Test command:
- Package command:
- Retention period:
- Provenance/fingerprint evidence:

## Deployment contract

- Deploy strategy: Docker Compose / Kubernetes / Windows Service / Terraform / other
- Deploy command:
- Verify command:
- Read-only smoke test:
- Maximum deploy duration:
- Success criteria:
- Abort criteria:

## Migration contract

- Migration required: yes / no
- Backward-compatible: yes / no
- Idempotency behavior:
- Lock/downtime expectation:
- Backup/restore point:
- Recovery command/owner:

## Rollback contract

- Previous-version source:
- Rollback command:
- Maximum recovery time:
- Data/schema compatibility constraints:
- Manual recovery runbook:
- Last staging drill date:

## Observability and evidence

- Dashboard:
- Log query:
- Alert route:
- Error/latency thresholds:
- Evidence path:
- Post-deploy observation window:

## Sign-off

- Security review:
- Infrastructure review:
- Application owner review:
- Operations handover:
- Production enablement date:
