# Secret scan - 2026-11-04

## Scope

Command (gitleaks through the Docker fallback, default rules, redacted output):

```bash
make secret-scan SECRET_SCAN_PATHS=". ../invoice-item-extractor ../facturas-backend-UNC-PSI ../ocr-scripts"
```

## Result

| Path | Result |
| --- | --- |
| `soltec-localdev19-ocr` | No leaks found |
| `invoice-item-extractor` | No leaks found |
| `ocr-scripts` | No leaks found |
| `facturas-backend-UNC-PSI` | 2 findings (see below) |

## Findings (redacted)

1. `client_secret_969194689681-qfq5aa7f2staifhlaqrg55dgfd403fd4.apps.googleusercontent.com.json`
   - Rule: `generic-api-key`
   - Field: `client_secret`
2. `facturas-473114-e176fe9714ba.json`
   - Rule: `private-key`
   - Field: `private_key`

No secret value is reproduced in this document or in the command output.

## Required actions before the pilot (PLAN.md Etapa 0)

- Revoke the exposed Google OAuth client secret and issue a new one.
- Invalidate the exposed service-account private key and issue a new one.
- Replace the affected files with placeholders or remove them from the working
  tree and from repository history.
- Re-run `make secret-scan` over all project repositories and datasets until it
  exits successfully.
- Store the replacement credentials outside the repositories.

This is a blocking issue for the pilot until revocation and rotation are
confirmed.
