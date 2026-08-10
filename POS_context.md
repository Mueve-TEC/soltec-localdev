# POS Invoicing (Argentina) — Development Context

> Follow-up doc for agentic sessions working on **POS + ARCA electronic invoicing** in
> `soltec-localdev-odoo19`. Read this first.
>
> **2026-08-10 update**: ARCA homologation is back up (HTTP 200, `FEDummy` OK) and
> the end-to-end POS→CAE path now works after the totals fix below. Refund path
> still pending a live re-test.
>
> Supermodule branch `19.0` · submodule `submodules/odoo-argentina` branch `19.0`.

## Objective / status

Make POS invoicing work end-to-end on Odoo 19 for an Argentine (ARCA) company,
including the migrated module `l10n_ar_pos_afipws_fe`.

**Status (2026-08-10):** normal POS invoicing → ARCA CAE is **working** on
homologation. Two POS invoices (`FA-B 00006-00000001` for 169.40 and
`FA-B 00006-00000002` for 6.17) returned `afip_result=A` with CAE
`86320746773270` / `86320746774506` on DB `admin1`, POS config 2 ("nueva",
journal 11 / PtoVta 6, `arcaws=wsfe`). The refund (credit note with
`reversed_entry_id`) path has not been re-tested live yet.

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
- `926dc855` — `[FIX-adhoc] l10n_ar_fiscal_ws_fe: pass base_lines to _l10n_ar_get_amounts for ARCA totals`
  - `models/account_move.py:247` was calling `inv._l10n_ar_get_amounts()` with no
    `base_lines`. Core Odoo 19's `_l10n_ar_get_amounts(self, base_lines=None)` does
    `base_lines = base_lines or []` and aggregates over that **empty list**, so every
    ARCA amount (`ImpNeto`, `ImpIVA`, `ImpTotConc`, `ImpOpEx`, `ImpTrib`) came back
    **0**. `ImpTotal` was still read from `self.amount_total`, so the request sent
    `ImpTotal=N` with all other amounts=0 → ARCA rejects with:
    `10048` (ImpTotal ≠ ImpTotConc+ImpNeto+ImpOpEx+ImpTrib+ImpIVA) and
    `10018` (if ImpIVA=0 the `Iva`/`AlicIva` object is mandatory, Id iva=3).
  - This blocked **every** POS invoice (and any invoice via this path), for products
    with or without IVA taxes — it is not a B2C / Consumidor Final issue (AR B
    invoices *do* report IVA, included in price).
  - Fix: pass the rounded tax base lines the same way core's `_get_vat` does:
    `base_lines = inv._get_rounded_base_and_tax_lines()[0]` then
    `amounts = inv._l10n_ar_get_amounts(base_lines=base_lines)`.
  - **Requires `-u l10n_ar_fiscal_ws_fe`** (Python change, picked up by upgrading the
    module or restarting Odoo with the new code on the addons path).

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

> **2026-08-10**: done successfully on DB `admin1`, POS config 2 ("nueva",
> journal 11 / PtoVta 6, `arcaws=wsfe`). Two `FA-B` invoices returned CAE
> (`afip_result=A`). Use this config as the reference working setup.

Env: `admin1` DB. Company **"My Company"** (`partner_id=1`, country AR, resp. type
1 = IVA Responsable Inscripto, VAT `20431432227`), POS config 2
`invoice_journal_id = 11` ("Factura POS", `00006`, `arcaws=wsfe`, PtoVta 6,
homologation certs "Using DB certificates", `arcaws.env.type=homologation`).
Cert alias `ARCA WS` (CUIT `20431432227`, `in_house`, `confirmed`).

1. **Confirm ARCA homologation is up** (must be HTTP 200):
   ```bash
   docker compose exec web python3 -c "import urllib.request;
   print(urllib.request.urlopen('https://wswhomo.afip.gov.ar/wsfev1/service.asmx?WSDL', timeout=15).status)"
   ```
   Or check `FEDummy` via zeep:
   ```bash
   docker compose exec web python3 -c "
   from zeep import Client
   print(Client('https://wswhomo.afip.gov.ar/wsfev1/service.asmx?WSDL').service.FEDummy())"
   ```
2. **Resolve the date desync (error 10016)** — see "Blockers" #3 above (only relevant
   if reusing a PtoVta that has already advanced a date).
3. Sell + invoice in POS UI → expect ARCA log
   `Running arg electronic invoice on homologation mode` → `CAE solicitado con exito`.
4. Refund the order → open the credit note (`move_type='out_refund'`) and check
   `reversed_entry_id` = original invoice id:
   ```bash
   docker compose exec db psql -U odoo -d admin1 -x \
     -c "SELECT id, name, move_type, reversed_entry_id, afip_auth_code FROM account_move WHERE move_type='out_refund' ORDER BY id DESC LIMIT 1;"
   ```

Fast shell repro of the posting path:
```bash
docker compose exec web odoo shell -d admin1 \
  --addons-path=/mnt/custom-addons,/usr/lib/python3/dist-packages/odoo/addons \
  --db_host=db --db_user=odoo --db_password=odoo --no-http <<'EOF'
inv = env['account.move'].browse(12)  # draft FA-B, no CAE
inv.invoice_date = '2026-08-10'
try:
    inv._post()
    env.cr.commit()
    print('POST OK', inv.name, inv.afip_result, inv.afip_auth_code)
except Exception as e:
    env.cr.rollback()
    print('EXCEPTION:', repr(e))
EOF
```

### Verified results (2026-08-10, after `926dc855`)

| move | name | amount_untaxed | amount_total | afip_result | afip_auth_code |
| ---- | ---- | -------------- | ------------ | ----------- | -------------- |
| 16 | FA-B 00006-00000001 | 140.00 | 169.40 | A | 86320746773270 |
| 18 | FA-B 00006-00000002 | 5.10 | 6.17 | A | 86320746774506 |

Both from POS orders `261-2-000001` / `261-2-000002` in session 6 ("nueva/00004").
Note: the earlier draft move 12 stayed draft because it predated the fix and its
lines had no taxes reflowed; a fresh POS order is the correct way to validate.

## Blockers

1. **ARCA homologation — RESOLVED (2026-08-10).** `wswhomo.afip.gov.ar/wsfev1` is
   now serving HTTP 200; `FEDummy` returns `AppServer/DbServer/AuthServer = OK`;
   `FECAESolicitar` returns CAE. The earlier 500s were transient on ARCA's side.
2. **Totals mismatch (ARCA errors 10048 + 10018) — RESOLVED by `926dc855`.** See
   "What is already done" above. Root cause was `_l10n_ar_get_amounts()` called
   with no `base_lines`, not a tax/product config issue and not a B2C issue.
3. **Date desync (ARCA error 10016)** — invoice `FA-C 00001-00000007` (journal 10)
   was authorized with `invoice_date = 2026-08-07` (tomorrow, from earlier manual
   testing). ARCA rejects any new invoice dated < last authorized date, so POS
   orders dated 2026-08-06 fail with
   `(10016) El numero o fecha del comprobante no se corresponde con el proximo a autorizar`.
   Unblock: set the POS order's `date_order` ≥ 2026-08-07, or wait until then, or
   use a fresh PtoVta / doc-type (e.g. FCE) that hasn't advanced. PtoVta 6 used by
   the "nueva" config is a clean point of sale and did not hit this.
4. **Company "ads" (`admin` DB) resp. type 5 = Consumidor Final** — maps to `[]`
   issued letters in `l10n_ar._get_journal_letter`, so the sale journal has no
   document types and every POS invoice is rolled back with the doc-type
   constraint. Set resp. type 1 (Responsable Inscripto) or 6 to invoice there.
   (DB `admin1` company is resp. type 1 and works.)

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
