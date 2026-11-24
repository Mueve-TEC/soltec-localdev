# Secret scan - 2026-11-13

Follow-up of `docs/security/secret-scan-2026-11-04.md`, run as the Etapa 0 gate
of the pilot readiness check.

## Scope

Command (gitleaks through the Docker fallback, default rules, redacted output):

```bash
make pilot-check DB=ai_eval PILOT_SECRET_SCAN=1
```

which runs the scan over:

```text
. ../invoice-item-extractor ../facturas-backend-UNC-PSI ../ocr-scripts
```

## Result

| Path                       | Result                          |
| -------------------------- | ------------------------------- |
| `soltec-localdev19-ocr`    | No leaks found                  |
| `invoice-item-extractor`   | No leaks found                  |
| `ocr-scripts`              | No leaks found                  |
| `facturas-backend-UNC-PSI` | 2 findings (same as 2026-11-04) |

## Findings (redacted)

1. `client_secret_969194689681-qfq5aa7f2staifhlaqrg55dgfd403fd4.apps.googleusercontent.com.json`
   - Rule: `generic-api-key`
   - Field: `client_secret` (line 1)
2. `facturas-473114-e176fe9714ba.json`
   - Rule: `private-key`
   - Field: `private_key` (line 5)

No secret value is reproduced in this document or in the command output.

## Gate status

**Blocked.** The revocation/rotation actions from the 2026-11-04 record are
still pending, and both files remain in the working tree of
`../facturas-backend-UNC-PSI`. The pilot cannot start until:

- The Google OAuth client secret is revoked and a new one is issued.
- The service-account private key is invalidated and a new one is issued.
- The affected files are removed from the working tree and from history.
- A new scan exits successfully over all project repositories.

This run is the current evidence for the security gate in
`docs/pilot/qa-checklist.md`.
