# Handoff — SolTec OCR accountant app

Date: 2026-11-13
Workspace: `/home/ezeluduena/odoo/beca-2026/soltec-localdev19-ocr`
Supermodule branch: `19.0-ocr`
Submodule: `submodules/odoo-argentina-invoice-ocr` (branch `19.0-dev`)

## Read first

- Design/UX spec: `submodules/odoo-argentina-invoice-ocr/docs/accountant-app-v1.md`
- Roadmap/status: `PLAN.md` (supermodule root; updated to v3)
- Submodule agent notes: `submodules/odoo-argentina-invoice-ocr/AGENTS.md`
- Module manifest: `submodules/odoo-argentina-invoice-ocr/account_invoice_ai_platform/__manifest__.py`

Do not duplicate those documents; they contain the agreed design, phases,
decisions and caveats.

## Current state

Implemented and tested (not committed):

- Phases 1–3 of the accountant app, in
  `account_invoice_ai_platform` (v19.0.1.6.0):
  batch upload/processing, accountant home, full-page “Nuevo lote”, two-pane
  review workspace, confirmation to a draft vendor bill, reviewer exception
  queue, return/exclude, second review, correction logging and Odoo activities.
- es_AR translations for both the evaluation core and the platform module.
- Domain backend remains in `account_invoice_ai_evaluation`; the app layer is
  separate.

State of the repo:

- Supermodule: `PLAN.md` and `Makefile` modified; the submodule gitlink is dirty.
- Submodule: `AGENTS.md` modified; `account_invoice_ai_platform/`,
  `account_invoice_ai_evaluation/i18n/` and `docs/accountant-app-v1.md` are
  untracked. Nothing committed.
- No commits were made in either repository.

Docker/DB:

- Services are running; Odoo is at http://localhost:8069.
- Demo database: `demo_ar` (Postgres container `db`), created with Argentina
  as country, ARS currency and `es_AR` as the active language. The old
  `ai_eval` database was backed up under `/tmp/opencode/backups/` and deleted.
- Organizations: `Estudio Contable Norte` (companies `Demo Norte SA`,
  `Demo Servicios SRL`) and `Estudio Contable Sur` (`Demo Sur SA`), all with
  the `ar_ri` chart and ARCA responsibility RI.
- Users: `admin`, `platform_manager`, `org_admin_a`, `org_admin_b`,
  `accountant_a1`, `accountant_a2`, `accountant_b1`, `reviewer_a1`,
  `reviewer_a2`, `reviewer_b1`, `researcher_a`, `researcher_b`. The admin
  keeps the full backend; the other demo users use the local demo password
  (reset locally if it is not recorded in the session).
- Demo data: 7 company-scoped suppliers (RI/Monotributo/Exento), AR products
  with IVA 21%, 3 batches with sample invoices (standard, A, multi-page,
  credit note) and one unbatched image document. The credit note is already
  waiting for a reviewer.

## Entry points / implementation notes

- Home client action: XML ID `account_invoice_ai_platform.action_ai_platform_home`,
  tag `account_invoice_ai_platform.home`.
- New batch: tag `account_invoice_ai_platform.new_batch`.
- Workspace: tag `account_invoice_ai_platform.workspace`; context accepts
  `batch_id`, `no_batch: true`, `document_id` and `reviewer_queue: true`.
- Login landing for shell users is set in
  `account_invoice_ai_platform/models/ir_http.py`.
- The app shell hides the Odoo app switcher, brand and menu sections; the
  evaluation console remains for managers/researchers.
- Backend RPC helpers used by the UI are in
  `account_invoice_ai_platform/models/ai_document.py` and
  `ai_annotation.py` (`get_review_data`, `action_confirm_review`,
  `action_send_to_review`, reviewer actions, upload helpers).
- The document form has an **Open in app** button
  (`action_open_platform_workspace`) so activities link into the workspace.

## Testing / verification

Run sequentially (do not run two Odoo upgrades/tests against the same DB in
parallel; this caused a transient cron/data parse error):

```bash
make test DB=demo_ar MODULE=account_invoice_ai_platform   # 29 tests
make test DB=demo_ar MODULE=account_invoice_ai_evaluation # combined run reported 81
```

- Pre-commit passes in the submodule for the changed files.
- UI was verified with Playwright (scripts under `/tmp/opencode/pwtest/`):
  home, new batch, multi-file upload, workspace, line/product editing,
  reviewer queue, return and reviewer confirmation; no console errors.
- After changing JS/XML/SCSS, run a module upgrade before restarting web:
  `docker compose exec -T web odoo ... -d demo_ar -u account_invoice_ai_platform --stop-after-init`,
  otherwise the old asset bundle attachment is served. A restart alone does not
  regenerate assets.

## Known gaps / pending work

- High-value review threshold is deferred.
- Explicit batch/document assignment, email notifications, line-to-PDF
  highlighting, app dashboard and mobile layout are deferred.
- Accountants can still reach evaluation-console actions by direct URL; the
  shell only hides the menus. If strict separation is required, restrict those
  actions/menus by group and re-test access rules.
- Document type names are now translated to Spanish for the types offered by the
  app (invoices, debit/credit notes, receipts and tickets A/B/C/M). Other l10n_ar
  types are not offered and may still display in English.
- Activities open the document form; the “Open in app” button bridges to the
  workspace.
- Next milestone is the pilot (Etapa 4): manual QA with real invoices,
  multi-organization checks, backups/credential rotation verification, and
  dataset validation.

## Suggested skills (call the Skill tool)

- `odoo-development` — Python/ORM/XML changes.
- `odoo-web-guidelines` — JS/Owl/SCSS under `static/src/`.
- `odoo-automated-tests` — tests for new behavior.
- `odoo-security` — menu/action restrictions, attachment access, multi-tenancy.
- `odoo-review` — review of the uncommitted module changes.
- `odoo-git` — commit/branch conventions when the user asks to commit.

## Suggested first actions

1. `make up` and run the two test commands above.
2. Review the uncommitted diffs; commit only when explicitly asked.
3. Pick the next item from “Known gaps / pending work” or start pilot hardening.

## Progress — pilot QA preparation (2026-11-13, later session)

- Environment started and modules synced; tests pass (29 platform, 83
  combined).
- Added `scripts/pilot-check.sh` and `make pilot-check`: services/database,
  installed modules, record rules, private attachments, a live multi-org probe
  (rolled back) and a backup/restore drill with automatic cleanup.
- Added `docs/pilot/qa-checklist.md` (Etapa 4 gates, single-org smoke,
  multi-org isolation, backup/restore, dataset validation, sign-off).
- Re-ran the secret scan: `../facturas-backend-UNC-PSI` still has the same two
  findings, so the pilot gate remains blocked. Recorded in
  `docs/security/secret-scan-2026-11-13.md`.
- Document type selector now includes receipts (4/9/15) and tickets
  (81/82/83/110-120), with Spanish es_AR labels for all 26 types. `_get_move_type`
  uses the l10n_ar `internal_type`, so ticket credit notes create `in_refund`.
- l10n_ar integration (v19.0.1.6.0): QR recipient/CAE/exchange-rate
  traceability and validation, document-type availability by ARCA
  responsibility, supplier fiscal profile, AFIP tax/UoM/currency mapping,
  purchase aliquot warnings, fiscal position mapping and document-number
  validation. Optional padrón button when `l10n_ar_fiscal_ws` is installed.
  Tests: 29 platform / 83 combined.
- Created the `demo_ar` demo database (Argentina, ARS, es_AR) with two
  organizations, three `ar_ri` companies, twelve users across all roles,
  company-scoped suppliers and sample batches/documents. The old `ai_eval`
  database and filestore were backed up and deleted.
- Viewer: PDFs keep the inline iframe viewer; images are converted to a derived
  PDF preview for the same iframe, while the original image remains untouched.
  Previews are generated on upload and by the 19.0.1.6.0 migration, dropped
  on confirmation and regenerated when the document is reopened.
- Still uncommitted in both repositories; no commits were made.

## Progress — single-role flow (2026-11-19, reviewer removal)

- Removed the **Reviewer role** entirely (platform v19.0.1.7.0, evaluation
  v19.0.1.6.0): group, reviewer queue, send/return actions, second review,
  activities. Notifications are chatter-only.
- Confirm gates are now **self-override**: any validator confirms duplicates /
  QR supplier / recipient / doc-type exceptions with a mandatory reason
  (audited in chatter + review notes). Posted bills remain manager-reopen
  only. `action_exclude` is validator-gated.
- Console annotation approve/reject is Platform-Manager-only
  (`_check_manager`); the app confirm path bypasses it as before.
- Batch closes when every document is confirmed/excluded (no flagged count).
- Migrations: evaluation pre-migrate copies former reviewers into the
  validator group; platform post-migrate resets stuck `waiting_reviewer` /
  `returned` documents to `pending`/`in_progress`, deletes stale activities
  and drops the orphan columns.
- Tests updated (duplicate/CIUT override now validator-level; second-review
  and return tests removed). Docs updated: `docs/accountant-app-v1.md`,
  `PLAN.md`, both AGENTS.md, evaluation README, both es_AR.po purged.
- Demo credentials normalized (2026-11-19): every demo user's password now
  equals its login name; verified end-to-end via the Playwright smoke login.
