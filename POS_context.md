# POS Invoicing (Argentina) — Development Context

> Follow-up doc for agentic sessions working on **POS + ARCA electronic invoicing** in
> `soltec-localdev-odoo19`. Read this first; the ARCA homologation server was **down
> (HTTP 500)** when this was written (2026-08-06) and the work could not be finished.
>
> Supermodule branch `19.0` · submodule `submodules/odoo-argentina` branch `19.0`.

## Objective / status

Make POS invoicing work end-to-end on Odoo 19 for an Argentine (ARCA) company,
including the migrated module `l10n_ar_pos_afipws_fe`. **Remaining blocker is
environmental, not code**: the ARCA homologation service returned 500 for every
request (even `FEDummy` / the WSDL GET), so the final end-to-end POS→CAE→refund
test could not run.

## What is already done (committed)

In `submodules/odoo-argentina` (branch `19.0`, nothing pushed):

- `c89e7eff3` + `526cd70b9` — added **`adhoc-modules/account-invoicing`** subtree
  (ingadhoc, branch `19.0`). Provides `account_background_post`, the missing dep of
  the vendored `account_ux` (was blocking fresh installs of the whole AR stack).
- `22ad61b6d` — `[FIX-adhoc] l10n_ar_pos_afipws_fe: migrate to Odoo 19 and add tests`
  - manifest: `version 19.0.1.0.0`, `depends` `l10n_ar_afipws_fe`→`l10n_ar_fiscal_ws_fe`,
    `installable True`
  - `models/pos_order.py`: `journal_id.afip_ws`→`journal_id.arcaws`, `elif`→`if`
    after `raise`, docstrings
  - `tests/test_pos_order.py`: 3 TransactionCase tests (see "Run the tests")
- `e15eb1a57` — `[DOC]` registered `account-invoicing` in `scripts/pull-upstream.sh`,
  README, PLAN.
- `a1e47e998` — `[FIX-adhoc] l10n_ar_fiscal_ws_fe: surface ARCA <Errors> on rejected CAE requests`
  - `data/arcaws.xml`: `request_invoice_authorization` response_dict now extracts
    `afip_errors` from `Errors.Err` (ARCA puts rejections there, not in
    `FeDetResp...Observaciones`).
  - `models/account_move.py`: `_l10n_ar_format_arca_error()` combines observations +
    errors into `afip_message`; rejected invoices now log at ERROR level (previously
    the diagnostic was lost because the write rolled back with the `UserError`).
  - **Data change requires `-u l10n_ar_fiscal_ws_fe`** (already applied on
    `Monotributo_admin` and `test_pos`) or the response_dict in the DB is stale.

Supermodule (`soltec-localdev-odoo19`): `f39ab0e` — AGENTS.md doc update +
submodule pointer bump.

## The migrated module (`l10n_ar_pos_afipws_fe`)

Single override `pos.order._prepare_invoice_vals()`:
- For POS **refunds** of ARCA-authorized invoices (`journal_id.arcaws` +
  `afip_auth_code`, AR company, `out_invoice`), sets `reversed_entry_id` to the
  original invoice; raises `UserError` if >1 such invoice.
- **Not needed** for normal (non-refund) POS invoicing — that's core
  `point_of_sale` + `l10n_ar_fiscal_ws_fe` (ARCA CAE on `_post`).

## Run the tests

```bash
docker compose exec web odoo \
  --addons-path=/mnt/custom-addons,/usr/lib/python3/dist-packages/odoo/addons \
  -d test_pos --db_host=db --db_user=odoo --db_password=odoo \
  --test-enable --test-tags=/l10n_ar_pos_afipws_fe,/l10n_ar_fiscal_ws_fe \
  -u l10n_ar_pos_afipws_fe,l10n_ar_fiscal_ws_fe \
  --stop-after-init --http-port=8099 --log-level=info
```

Expect: `0 failed, 0 error(s) of 7 tests` (5 POS + 2 currency-rate).

`test_pos` = fresh DB with the full AR stack. Note: its company is **US by default**;
`test_pos_order.py` sets `company.country_id = base.ar` and the sale journal to
`RAW_MAW` in `setUpClass`. `--http-port=8099` (or `--no-http`, which is ignored here)
is required because the running server owns 8069.

## Manual end-to-end test (when ARCA is back)

Env: `Monotributo_admin` DB. Company **"Ezequiel Ludueña"**, POS config 1
`invoice_journal_id = 10` ("Factura electrónica", `RAW_MAW`, `arcaws=wsfe`,
PtoVta 1, homologation certs "Using DB certificates").

1. **Confirm ARCA homologation is up** (must be HTTP 200):
   ```bash
   docker compose exec web python3 -c "import urllib.request;
   print(urllib.request.urlopen('https://wswhomo.afip.gov.ar/wsfev1/service.asmx?WSDL', timeout=15).status)"
   ```
2. **Resolve the date desync (error 10016)** — see "Blockers" below.
3. Sell + invoice in POS UI → expect ARCA log
   `Running arg electronic invoice on homologation mode` → `CAE solicitado con exito`.
4. Refund the order → open the credit note (`move_type='out_refund'`) and check
   `reversed_entry_id` = original invoice id:
   ```bash
   docker compose exec db psql -U odoo -d Monotributo_admin -x \
     -c "SELECT id, name, move_type, reversed_entry_id, afip_auth_code FROM account_move WHERE move_type='out_refund' ORDER BY id DESC LIMIT 1;"
   ```

Fast shell repro of the posting path (order 4 = `261-1-000003`, stuck `paid`, no move):
```bash
docker compose exec web odoo shell -d Monotributo_admin \
  --addons-path=/mnt/custom-addons,/usr/lib/python3/dist-packages/odoo/addons \
  --db_host=db --db_user=odoo --db_password=odoo --no-http <<'EOF'
order = env['pos.order'].browse(4)
inv = order._create_invoice(order._prepare_invoice_vals())
try:
    inv.with_context(**order._get_invoice_post_context())._post()
    print('POST OK', inv.name, inv.afip_result, inv.afip_auth_code)
except Exception as e:
    print('EXCEPTION:', repr(e))
inv.button_cancel(); inv.unlink()
EOF
```

## Blockers

1. **ARCA homologation down** — `wswhomo.afip.gov.ar/wsfev1` returned HTTP 500 for
   `FEDummy`, `FECompUltimoAutorizado`, `FECAESolicitar` and even the WSDL GET.
   Nothing to fix client-side; wait and re-check.
2. **Date desync (ARCA error 10016)** — invoice `FA-C 00001-00000007` (journal 10)
   was authorized with `invoice_date = 2026-08-07` (tomorrow, from earlier manual
   testing). ARCA rejects any new invoice dated < last authorized date, so POS
   orders dated 2026-08-06 fail with
   `(10016) El numero o fecha del comprobante no se corresponde con el proximo a autorizar`.
   Unblock: set the POS order's `date_order` ≥ 2026-08-07, or wait until then, or
   use a fresh PtoVta / doc-type (e.g. FCE) that hasn't advanced.
3. **Company "ads" (`admin` DB) resp. type 5 = Consumidor Final** — maps to `[]`
   issued letters in `l10n_ar._get_journal_letter`, so the sale journal has no
   document types and every POS invoice is rolled back with the doc-type
   constraint. Set resp. type 1 (Responsable Inscripto) or 6 to invoice there.

## Environment notes / gotchas

- `custom-addons/` is **generated + gitignored**: edit in `submodules/<repo>/...`,
  then `bash copy_addons.sh`, then `docker compose restart web`.
- Shell/CLI must pass `--addons-path=/mnt/custom-addons,/usr/lib/python3/dist-packages/odoo/addons`
  and `-d <db> --db_host=db --db_user=odoo --db_password=odoo`; without
  `--addons-path`, custom modules are "not installable".
- In-place adhoc fixes use the `[FIX-adhoc] <module>: <desc>` commit prefix.
- **Another agent works on the same submodule.** At last check the working tree
  had uncommitted (not ours, DO NOT commit) changes:
  - `l10n_ar_fiscal_ws/models/arcaws.py` (removes `ormcache` from `get_arca_url`)
  - `l10n_ar_fiscal_ws/models/res_company.py` (reads `arcaws.env.type` via `search()`
    instead of cached `get_param()` — runtime env switch without server restart)
  Always use **selective `git add <paths>`**; never `git add -A`.
- Only commit when asked; commit to `submodules/odoo-argentina` (pushable origin
  `Mueve-TEC/odoo-argentina`). Supermodule commit = bump submodule pointer +
  doc changes.
