# Pilot QA checklist - accountant app (Etapa 4)

> Updated 2026-11-24 for the integrated branches: single-role flow
> (platform v19.0.1.7.0), chart-of-accounts packages and guided client setup
> (v19.0.1.8.0), and the item-matching module. The 2026-11-13 readiness record
> is historical; it predates these changes.

Scope: the single-organization smoke test and the multi-organization formal
pilot described in `PLAN.md` (Etapa 4). The app (phases 1-3) is implemented
and covered by automated tests; this checklist is the operational pilot gate,
not a development blocker. No pilot has been run with real accountants yet.

Both local checkouts share the `19.0-dev` supermodule branch:

- **OCR / pilot checkout** (`~/odoo/beca-2026/soltec-localdev19-ocr`):
  `WEB_PORT=8069`, `PGADMIN_PORT=5050`, database `demo_ar`. Run the pilot
  checks here.
- **Main checkout** (`soltec-localdev-odoo19`): defaults `8070`/`5051`, used
  for the matching WIP. Adjust paths and database names when running checks
  here.

Use a dedicated database (the pilot database is `demo_ar`) and record the
evidence referenced below before signing off. Never run two upgrades or test
suites against the same database in parallel.

## 0. Development pre-flight

These steps are enough to start coding; they are **not** the pilot gate.

1. Build and start the stack (both checkouts use the same compose file):
   ```bash
   make build          # Dockerfile now uses soltec-odoo 19.0.10-dev
   make up
   ```
2. Sync the submodules into `custom-addons/` after any branch switch:
   ```bash
   make sync
   ```
3. Apply the modules to the database you are using:
   ```bash
   make upgrade DB=<db> MODULE=account_invoice_ai_evaluation,account_invoice_ai_platform
   make install DB=<db> MODULE=l10n_ar_invoice_match   # only when testing matching
   ```
   `make test` performs the upgrade itself; use `make upgrade` for a quick
   apply without running tests.
4. Run the automated checks below before changing code. The secret-scan gate
   (section 1) is required before the pilot, not before development.
5. Keep the branch discipline: the main checkout works on
   `19.0-invoice-match`, the OCR checkout on `19.0-accountant-app`; use
   `make ticket-new` for isolated work and never edit `custom-addons/` by hand.

## 1. Blocking gates (Etapa 0)

Do not start the smoke test while any gate is open.

| Gate                                              | Verification                                                                                                                                                                          | Evidence                                    |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| Secret scan clean in every project repository     | From the OCR checkout: `make secret-scan SECRET_SCAN_PATHS=". ../invoice-item-extractor ../facturas-backend-UNC-PSI ../ocr-scripts"` and `make pilot-check DB=<db> PILOT_SECRET_SCAN=1` | New dated record under `docs/security/`     |
| UNC-PSI credentials revoked and rotated           | Revoke the exposed Google OAuth client secret and service-account key at the provider; purge the files from the working tree and history; store replacements outside the repositories | Dated, redacted note under `docs/security/` |
| Confidentiality agreement signed per organization | In the organization form: `agreement_signed`, `agreement_date`, `agreement_version`; consents `consent_storage` and `consent_evaluation` (training is separate and optional)          | Signed agreement + organization record      |
| Backups configured and restore verified           | Section 6 of this checklist                                                                                                                                                           | Dated drill record                          |
| HTTPS and restricted access                       | Deployment checklist for the pilot host                                                                                                                                               | Deployment record                           |

The current secret-scan findings are recorded in
`docs/security/secret-scan-2026-11-13.md` (follow-up of the 2026-11-04 run); the
pilot gate stays closed until the revocation/rotation actions are confirmed.
The main checkout may not have the adjacent repositories listed above; use its
own paths or run the scan from the OCR checkout.

## 2. Automated checks (run first)

```bash
bash copy_addons.sh          # or: make sync
make build                   # only after a Dockerfile change
make up
make test DB=demo_ar MODULE=account_invoice_ai_evaluation
make test DB=demo_ar MODULE=account_invoice_ai_platform
make test DB=demo_ar MODULE=l10n_ar_invoice_match   # optional, if installed
make pilot-check DB=demo_ar
make pilot-check DB=demo_ar PILOT_SECRET_SCAN=1   # security gate
```

Run the test commands sequentially, never in parallel against the same
database. Expected results:

- `account_invoice_ai_platform`: all green. The suite now includes the
  accountant flow, chart-of-accounts packages, guided client setup and the
  platform shell. Record the actual test count; do not rely on the 2026-11-13
  count.
- `account_invoice_ai_evaluation` + platform: all green (record the combined
  count).
- `l10n_ar_invoice_match` (when installed): all green.
- `make pilot-check`: all checks pass; `Pilot data` is skipped while the
  database has fewer than two active organizations.
- The secret-scan gate passes only after the Etapa 0 findings are closed.

`pilot-check` verifies the running services, database, installed modules,
record rules for every AI model, private document attachments, a live
multi-organization probe (temporary organizations/users created and rolled
back) and a backup/restore drill. It never leaves a scratch database or
filestore behind. The compose command runs Odoo with `--workers=0`, so
`HttpCase` tests can reach the test server.

## 3. Test data

Minimum for the single-org smoke test:

- One organization with agreement/consents granted and one company configured
  as Argentine: fiscal country `AR`, `l10n_ar` chart of accounts, purchase
  journal, suppliers, products, taxes, expense accounts and the company's ARCA
  responsibility. Without an AR fiscal country/responsibility the app skips
  the l10n_ar validation rules (document-type availability, aliquots, etc.).
- Supplier partners with CUIT, identification type and ARCA responsibility,
  including at least one Responsable Inscripto and one Monotributo supplier.
- Users: one Accountant Validator, one Organization Administrator and one
  Platform Manager. Optionally one Researcher. There is **no Reviewer** role
  since v19.0.1.7.0.
- At least one company created through the guided client-setup wizard and one
  existing company with a chart-of-accounts package applied (see 4.21/4.22).
- For matching: a supplier with vendor catalog entries, products, an active
  supplier rule and a bill with extractable items. Configure the fuzzy scorer
  and thresholds in the invoice-matching settings.
- 20-30 invoices covering: digital PDF with text layer, scanned PDF, JPEG/PNG
  photo, TIFF, multi-page PDF, credit note, invoice without a readable QR,
  duplicate file (same hash), invoice with a CUIT mismatch, and one invoice
  whose total does not match the line sum.
- The `demo_ar` database already contains the demo organizations, companies
  and users described in the handoff; passwords are not stored in the
  repository. Reset them locally if needed and do not commit new passwords.

For the formal pilot: 2-3 organizations and 500+ real invoices, with the
agreement and consents recorded for each organization.

## 4. Single-organization smoke test

Run the flow as the Accountant Validator, then repeat the manager-only rows
with the Platform Manager. There is no reviewer queue, second review or Odoo
activities in the current flow. Record each result.

| ID   | Scenario                                 | Expected result                                                                                                                                                     | OK  |
| ---- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| 4.1  | Sign in as Accountant Validator          | Lands on the Invoice Platform home; no evaluation-console menus; the Odoo app switcher/brand is hidden                                                              |     |
| 4.2  | Sign in as Platform Manager              | Full backend is available, including the evaluation console, settings and chart-of-accounts packages                                                               |     |
| 4.3  | Open **Nuevo lote**                      | Organization/company default to the user's context; name/notes optional; drag-and-drop zone accepts multiple files                                                  |     |
| 4.4  | Upload the 20-30 sample invoices         | Per-file status is visible; the UI rejects oversized/unsupported files and flags duplicates. Server-side enforcement is still a hardening item (see 8)             |     |
| 4.5  | Submit and open the workspace            | Batch and documents are created; QR prefill runs; processing can continue while earlier files are reviewed                                                          |     |
| 4.6  | Review header fields                     | Supplier, document type, point of sale, number, dates, currency, subtotal, VAT, other taxes and total are editable; warnings are inline                             |     |
| 4.7  | Edit lines                               | Add/remove lines; edit description, code, quantity, UoM, unit price, discount; select product, account and taxes; matching suggestions appear for the selected line |     |
| 4.8  | Autosave                                 | "Guardando/Guardado" reflects changes; leaving and returning keeps the edits                                                                                        |     |
| 4.9  | Hard blocks                              | Confirm is blocked without supplier, document type, POS/number, invoice date, at least one complete line or with total <= 0                                         |     |
| 4.10 | Confirm a normal invoice                 | Exactly one draft vendor bill is created/updated and linked; the document advances; batch counters update; the bill is **not** posted                               |     |
| 4.11 | Reopen a confirmed document (draft bill) | A new annotation version is created and the document returns to review; the same draft bill is reused                                                               |     |
| 4.12 | Exclude with a reason                    | The reason is required; the document leaves the pending queue; the batch counter and finished state update                                                          |     |
| 4.13 | Self-override a blocking exception       | A duplicate, QR supplier/recipient CUIT mismatch or unavailable document type blocks confirmation until the validator enters a mandatory reason; the reason is recorded in the chatter and review notes |     |
| 4.14 | Force-close a batch                      | Pending documents block normal closing; only a Platform Manager can force-close, with a reason                                                                       |     |
| 4.15 | Batch summary                            | Confirmed/excluded/failed counts, total amount and links to the generated bills match the documents                                                                  |     |
| 4.16 | "Sin lote" queue                         | A document created outside a batch appears there and can be reviewed or moved into a batch                                                                          |     |
| 4.17 | Correction log                           | Header/line edits are recorded field by field (old/new value, user, category) without exposing them to accountants as evaluation jargon                             |     |
| 4.18 | QR recipient/CAE                         | Recipient CUIT, CAE and exchange rate are shown; an invoice addressed to another company blocks confirmation until a reason is entered                              |     |
| 4.19 | Document type by responsibility          | A Monotributo supplier only offers C/E-compatible types; an invalid A/B type blocks confirmation until a reason is entered                                           |     |
| 4.20 | Taxes, aliquots and fiscal position      | Extracted tax labels map to l10n_ar AFIP groups, the supplier fiscal position is applied and Factura A/B purchase aliquot rules are flagged per line                |     |
| 4.21 | Apply a chart-of-accounts package        | Applying a package creates the missing accounts/groups, skips codes already present and is idempotent; taxes, fiscal positions and existing accounts are untouched   |     |
| 4.22 | Guided client setup                      | An Organization Administrator creates a root company, sets the ARCA responsibility, loads the `ar_ri` chart and applies the selected packages; organization users get access |     |
| 4.23 | Item matching (if installed)             | Extracted lines show the matching state, method, score and candidates; the chatter summary lists every item; changing a product records a correction and can suggest a rule (never auto-activated) |     |
| 4.24 | Direct evaluation-console URL            | A validator cannot open the console from direct URLs; record any access obtained (known gap, see 8)                                                                |     |
| 4.25 | Unsupported file / oversized upload      | The UI rejects the file with a clear message; record whether a direct RPC upload bypasses the limit (known gap, see 8)                                              |     |

## 5. Multi-organization isolation

The automated coverage is in
`account_invoice_ai_evaluation/tests/test_security.py` (record rules, RPC/
attachment access and HTTP downloads) and in the live probe of
`make pilot-check`. Complete these manual checks with users from two
organizations (A and B) before the formal pilot:

| ID  | Scenario                                                  | Expected result                                                                                     | OK  |
| --- | --------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | --- |
| 5.1 | Lists, home, "Mis pendientes", batches and corrections    | User A only sees organization A data                                                                |     |
| 5.2 | Direct record URL for a document/batch/annotation of B    | Access denied (404/403), not just hidden from menus                                                 |     |
| 5.3 | Attachment download URL of a B document                   | Denied for user A; allowed for a B user in the same organization                                    |     |
| 5.4 | Export a dataset                                          | Only authorized, consented organization data is exported; a cross-organization export is impossible |     |
| 5.5 | Chatter, corrections and matching records                 | No record, correction or notification leaks between organizations                                   |     |
| 5.6 | Platform Manager                                          | Sees all organizations (global fallback)                                                            |     |
| 5.7 | Researcher                                                | Sees only approved annotations/exports; no access to original documents or runs                     |     |
| 5.8 | Duplicate detection                                       | A document from B is never used to block a document from A                                          |     |
| 5.9 | Organization Administrator                                | Manages users, companies, agreements and packages of their own organization; cannot create organizations or change platform settings |     |
| 5.10 | Company assignment                                      | A user cannot move a company into an organization they do not belong to                             |     |

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
  smoke test, including product changes made through matching.
- Create a JSONL/CSV export; verify the manifest, content hash, consent
  enforcement and the deterministic train/validation/test splits (keyed by
  document hash).
- Spot-check exported examples against the source documents and annotations.
- Open the operational metrics wizard and confirm durations, strategy coverage,
  error rate, correction rate and matching top-1 are populated.

## 8. Known limitations accepted for v1

- Single role since v19.0.1.7.0: no Reviewer group, no reviewer queue, no
  second review and no Odoo activities. Blocking exceptions are self-overridden
  with a mandatory reason.
- High-value review threshold is deferred; all exceptions are reviewed
  manually.
- No explicit batch/document assignment, no email notifications, no app
  dashboard and no mobile-first layout.
- No line-to-PDF highlighting (no bounding boxes are extracted).
- Evaluation-console actions are hidden by the shell but not yet restricted by
  group. Closing this is part of phase-4 hardening.
- The upload size/count/type limits are enforced by the UI, not yet by the
  server RPC. Closing this is part of phase-4 hardening.
- Chart-of-accounts packages only create missing accounts/groups; they never
  touch taxes, fiscal positions or existing accounts.
- Matching (`l10n_ar_invoice_match`) is optional and independent of the
  platform; thresholds and the fuzzy scorer must be calibrated on annotated
  invoices before enabling automatic application broadly.
- Document type names (`INVOICES A`, etc.) may appear in English because they
  come from `l10n_ar` data; this is not an app translation.
- Confirmation creates a **draft** bill; it never posts automatically.
- Online ARCA validation (padron lookup, CAE check) requires the optional
  `l10n_ar_fiscal_ws` / `l10n_ar_fiscal_ws_fe` modules plus certificates. The
  padron button only appears when those modules are installed; the CAE is
  stored for traceability in the meantime.

## 9. Sign-off

| Role                             | Name | Date | Result / notes |
| -------------------------------- | ---- | ---- | -------------- |
| QA / pilot lead                  |      |      |                |
| Accountant Validator             |      |      |                |
| Organization Administrator       |      |      |                |
| Platform Manager (security gate) |      |      |                |
