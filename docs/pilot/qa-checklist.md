# Pilot QA checklist — accountant app (Etapa 4)

Scope: the single-organization smoke test and the multi-organization formal
pilot described in `PLAN.md` (Etapa 4). The app itself (phases 1–3) is
implemented and covered by automated tests; this checklist is the operational
gate. No pilot has been run with real accountants yet.

Use a dedicated database (the local demo database is `demo_ar`) and
record the evidence referenced below before signing off.

## 1. Blocking gates (Etapa 0)

Do not start the smoke test while any gate is open.

| Gate                                              | Verification                                                                                                                                                                          | Evidence                                    |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| Secret scan clean in every project repository     | `make secret-scan SECRET_SCAN_PATHS=". ../invoice-item-extractor ../facturas-backend-UNC-PSI ../ocr-scripts"` and `make pilot-check DB=<db> PILOT_SECRET_SCAN=1`                      | New dated record under `docs/security/`     |
| UNC-PSI credentials revoked and rotated           | Revoke the exposed Google OAuth client secret and service-account key at the provider; purge the files from the working tree and history; store replacements outside the repositories | Dated, redacted note under `docs/security/` |
| Confidentiality agreement signed per organization | In the organization form: `agreement_signed`, `agreement_date`, `agreement_version`; consents `consent_storage` and `consent_evaluation` (training is separate and optional)          | Signed agreement + organization record      |
| Backups configured and restore verified           | Section 6 of this checklist                                                                                                                                                           | Dated drill record                          |
| HTTPS and restricted access                       | Deployment checklist for the pilot host                                                                                                                                               | Deployment record                           |

The current secret-scan findings are recorded in
`docs/security/secret-scan-2026-11-13.md` (follow-up of the 2026-11-04 run); the
pilot gate stays closed until the revocation/rotation actions are confirmed.

## 2. Automated checks (run first)

```bash
bash copy_addons.sh          # or: make sync
make up
make test DB=demo_ar MODULE=account_invoice_ai_evaluation
make test DB=demo_ar MODULE=account_invoice_ai_platform
make pilot-check DB=demo_ar
make pilot-check DB=demo_ar PILOT_SECRET_SCAN=1   # security gate
```

Run the two test commands sequentially, never in parallel against the same
database. Expected results:

- `account_invoice_ai_platform`: 29 tests, 0 failed.
- Combined run (`account_invoice_ai_evaluation` + platform): 83 tests, 0 failed.
- `make pilot-check`: all checks pass; `Pilot data` is skipped while the
  database has fewer than two active organizations.
- The secret-scan gate passes only after the Etapa 0 findings are closed.

`pilot-check` verifies the running services, database, installed modules,
record rules for every AI model, private document attachments, a live
multi-organization probe (temporary organizations/users created and rolled
back) and a backup/restore drill. It never leaves a scratch database or
filestore behind.

## 3. Test data

Minimum for the single-org smoke test:

- One organization with agreement/consents granted and one company configured
  as Argentine: fiscal country `AR`, `l10n_ar` chart of accounts, purchase
  journal, suppliers, products, taxes, expense accounts and the company's ARCA
  responsibility. Without an AR fiscal country/responsibility the app skips
  the l10n_ar validation rules (document-type availability, aliquots, etc.).
- Supplier partners with CUIT, identification type and ARCA responsibility,
  including at least one Responsable Inscripto and one Monotributo supplier.
- Users: one Accountant Validator, one Reviewer, one Organization
  Administrator. Optionally one Platform Manager and one Researcher.
- 20–30 invoices covering: digital PDF with text layer, scanned PDF, JPEG/PNG
  photo, TIFF, multi-page PDF, credit note, invoice without a readable QR,
  duplicate file (same hash), invoice with a CUIT mismatch, and one invoice
  whose total does not match the line sum.
- The `demo_ar` database already contains the demo users, organizations and
  companies described in the handoff; passwords are not stored in the
  repository. Reset them locally if needed and do not commit the new password.

For the formal pilot: 2–3 organizations and 500+ real invoices, with the
agreement and consents recorded for each organization.

## 4. Single-organization smoke test

Run the full flow twice: once as the Accountant Validator and once with a
Reviewer. Record each result.

| ID   | Scenario                                 | Expected result                                                                                                                                                     | OK  |
| ---- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| 4.1  | Sign in as Accountant Validator          | Lands on the Invoice Platform home; no evaluation-console menus; the Odoo app switcher/brand is hidden                                                              |     |
| 4.2  | Sign in as Platform Manager              | Full backend is available, including the evaluation console                                                                                                         |     |
| 4.3  | Open **Nuevo lote**                      | Organization/company default to the user's context; name/notes optional; drag-and-drop zone accepts multiple files                                                  |     |
| 4.4  | Upload the 20–30 sample invoices         | Per-file status is visible; oversized or unsupported files are rejected with a clear message; duplicates are flagged, not silently skipped                          |     |
| 4.5  | Submit and open the workspace            | Batch and documents are created; QR prefill runs; processing can continue while earlier files are reviewed                                                          |     |
| 4.6  | Review header fields                     | Supplier, document type, point of sale, number, dates, currency, subtotal, VAT, other taxes and total are editable; warnings are inline                             |     |
| 4.7  | Edit lines                               | Add/remove lines; edit description, code, quantity, UoM, unit price, discount; select product, account and taxes; matching suggestions appear for the selected line |     |
| 4.8  | Autosave                                 | “Guardando/Guardado” reflects changes; leaving and returning keeps the edits                                                                                        |     |
| 4.9  | Hard blocks                              | Confirm is blocked without supplier, document type, POS/number, invoice date, at least one complete line or with total <= 0                                         |     |
| 4.10 | Confirm a normal invoice                 | Exactly one draft vendor bill is created/updated and linked; the document advances; batch counters update; the bill is **not** posted                               |     |
| 4.11 | Reopen a confirmed document (draft bill) | A new annotation version is created and the document returns to review; the same draft bill is reused                                                               |     |
| 4.12 | Flag for review                          | A note is required; the document moves to the reviewer queue with a visible reason                                                                                  |     |
| 4.13 | Reviewer: return to accountant           | Note is required; the document shows “Devuelto” with the note in the accountant queue                                                                               |     |
| 4.14 | Reviewer: exclude/reject                 | Reason is required; the document leaves the pending queue and the batch counter updates                                                                             |     |
| 4.15 | Reviewer: second review                  | Another reviewer (or the Platform Manager) can complete it; the requester cannot complete or confirm their own second review                                        |     |
| 4.16 | Force-close a batch                      | Flagged documents block normal closing; a manager can force-close with a reason                                                                                     |     |
| 4.17 | Activities                               | Reviewer/return actions create Odoo activities; opening an activity and using **Open in app** reaches the workspace                                                 |     |
| 4.18 | Batch summary                            | Confirmed/flagged/failed counts, total amount and links to the generated bills match the documents                                                                  |     |
| 4.19 | “Sin lote” queue                         | A document created outside a batch appears there and can be reviewed or moved into a batch                                                                          |     |
| 4.20 | Correction log                           | Header/line edits are recorded field by field (old/new value, user, category) without exposing them to accountants as evaluation jargon                             |     |
| 4.21 | QR recipient/CAE                         | Recipient CUIT, CAE and exchange rate are shown; an invoice addressed to another company blocks confirmation for accountants and requires a reviewer reason         |     |
| 4.22 | Document type by responsibility          | A Monotributo supplier only offers C/E-compatible types; an invalid A/B type is flagged and cannot be confirmed without a reviewer reason                           |     |
| 4.23 | Taxes, aliquots and fiscal position      | Extracted tax labels map to l10n_ar AFIP groups, the supplier fiscal position is applied and Factura A/B purchase aliquot rules are flagged per line                |     |

## 5. Multi-organization isolation

The automated coverage is in
`account_invoice_ai_evaluation/tests/test_security.py` (record rules, RPC/
attachment access and HTTP downloads) and in the live probe of
`make pilot-check`. Complete these manual checks with users from two
organizations (A and B) before the formal pilot:

| ID  | Scenario                                                  | Expected result                                                                                     | OK  |
| --- | --------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | --- |
| 5.1 | Lists, home, “Mis pendientes”, reviewer queue and batches | User A only sees organization A data                                                                |     |
| 5.2 | Direct record URL for a document/batch/annotation of B    | Access denied (404/403), not just hidden from menus                                                 |     |
| 5.3 | Attachment download URL of a B document                   | Denied for user A; allowed for a B user in the same organization                                    |     |
| 5.4 | Export a dataset                                          | Only authorized, consented organization data is exported; a cross-organization export is impossible |     |
| 5.5 | Activities and notifications                              | No activity or notification leaks records between organizations                                     |     |
| 5.6 | Platform Manager                                          | Sees all organizations (global fallback)                                                            |     |
| 5.7 | Researcher                                                | Sees only approved annotations/exports; no access to original documents or runs                     |     |
| 5.8 | Duplicate detection                                       | A document from B is never used to block a document from A                                          |     |

Watch for the known gap: the accountant shell hides the evaluation-console
menus, but it does not yet restrict the console actions by group. Record any
access obtained by direct URL so it can be closed during hardening.

## 6. Backup and restore drill

`make pilot-check DB=<db>` performs a local drill on every run:

1. `pg_dump -Fc` of the database.
2. Restore into `<db>_restore_check` (created and dropped automatically).
3. Copy the filestore to the scratch database.
4. Load the Odoo registry and compare document, batch and annotation counts.
5. Read every document attachment after the restore.
6. Drop the scratch database and filestore copy.

Before the formal pilot, also perform one **offsite** restore (provider or
storage snapshot) and record:

- Date, operator and source/destination.
- Database size, filestore size and restore duration (RTO).
- Counts and attachment spot-checks after restore.
- Data-loss window accepted for the pilot (RPO).
- Whether the backup is encrypted and who can access it.

Do not use `make down-clean` while validating backups: it deletes the volumes.

## 7. Dataset and metrics validation

- Confirming a document creates/updates its annotation (ground truth) and keeps
  older annotation versions.
- Correction records exist for the header and line fields changed during the
  smoke test.
- Create a JSONL/CSV export; verify the manifest, content hash, consent
  enforcement and the deterministic train/validation/test splits (keyed by
  document hash).
- Spot-check exported examples against the source documents and annotations.
- Open the operational metrics wizard and confirm durations, strategy coverage,
  error rate and correction rate are populated.

## 8. Known limitations accepted for v1

- High-value review threshold is deferred; all exceptions are reviewed
  manually.
- No explicit batch/document assignment, no email notifications, no app
  dashboard and no mobile-first layout.
- No line-to-PDF highlighting (no bounding boxes are extracted).
- Evaluation-console actions are hidden by the shell but not yet restricted by
  group.
- Document type names (`INVOICES A`, etc.) may appear in English because they
  come from `l10n_ar` data; this is not an app translation.
- Activities open the document form; the **Open in app** button bridges to the
  workspace.
- Confirmation creates a **draft** bill; it never posts automatically.
- Online ARCA validation (padrón lookup, CAE check) requires the optional
  `l10n_ar_fiscal_ws` / `l10n_ar_fiscal_ws_fe` modules plus certificates. The
  padrón button only appears when those modules are installed; the CAE is
  stored for traceability in the meantime.

## 9. Sign-off

| Role                             | Name | Date | Result / notes |
| -------------------------------- | ---- | ---- | -------------- |
| QA / pilot lead                  |      |      |                |
| Accountant Validator             |      |      |                |
| Reviewer                         |      |      |                |
| Organization Administrator       |      |      |                |
| Platform Manager (security gate) |      |      |                |
