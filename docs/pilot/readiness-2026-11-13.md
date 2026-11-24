# Pilot readiness record - 2026-11-13

Local readiness run for `demo_ar` (Argentina demo database) before the Etapa 4 pilot.

## Commands

```bash
make test DB=demo_ar MODULE=account_invoice_ai_evaluation
make test DB=demo_ar MODULE=account_invoice_ai_platform
make pilot-check DB=demo_ar
make pilot-check DB=demo_ar PILOT_SECRET_SCAN=1
```

## Result

**Conditional.** All local checks pass, but the Etapa 0 security gate remains
blocked by the `../facturas-backend-UNC-PSI` findings.

| Check                | Result                                                                                                                                  |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Evaluation tests     | 64 tests, 0 failed                                                                                                                      |
| Platform tests       | 29 tests, 0 failed                                                                                                                      |
| Combined suite       | 83 tests, 0 failed                                                                                                                      |
| Services / database  | db and web running; `demo_ar` exists                                                                                                    |
| Modules              | `account_invoice_ai_evaluation`, `account_invoice_ai_platform`, `l10n_ar_factura_items`, `l10n_ar_factura_qr` installed                 |
| Record rules         | 11 AI models covered                                                                                                                    |
| Private attachments  | 5 documents, 5 attachments readable and private                                                                                         |
| Isolation probe      | Temporary organizations/users created and rolled back; no cross-organization access                                                     |
| Pilot data           | 2 active organizations, 3 companies (12 platform users)                                                                                 |
| Backup/restore drill | Dump, restore to scratch DB and filestore copy verified; 5 documents, 3 batches and all attachments were readable                       |
| l10n_ar validations  | All companies use the `ar_ri` chart, AR fiscal country, ARS and `es_AR`; document-type, aliquot, tax, currency and UoM rules are active |
| Secret scan          | 2 findings in `../facturas-backend-UNC-PSI`; see `docs/security/secret-scan-2026-11-13.md`                                              |

## Next actions

1. Close the Etapa 0 findings (revoke/rotate credentials, remove the files from
   the tree and history) and re-run the scan until it passes.
2. Run the single-organization smoke checklist in `docs/pilot/qa-checklist.md`
   with the pilot team.
3. Run the manual multi-org isolation checks with the two demo organizations
   and one offsite restore drill.
