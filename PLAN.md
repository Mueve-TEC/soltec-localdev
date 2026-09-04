# PLAN — Finish the Odoo-19 migration of the `odoo-argentina` modules

> **Scope (current pass, opened 2026-09-04):** the ARCA fiscal-ws pass below is
> **complete** (§STATUS). What remains for the 18→19 migration of
> `Mueve-TEC/odoo-argentina` is a short list of modules that still carry old
> version strings / unmigrated code, listed in §"Remaining migration work".
> This file is the hand-over document for the next agent; everything else the
> agent needs is already in `AGENTS.md` (env, commands, conventions) and
> `submodules/odoo-argentina/PLAN.md` (subtree mechanics). Do not duplicate
> either here.
>
> **Target executor:** an LLM with write access to `Mueve-TEC/odoo-argentina`
> branch `19.0`. Read this file and `AGENTS.md` in full before touching anything.

---

## Remaining migration work (current pass)

Verified against the working tree on 2026-09-04 (manifest versions + grep of
`<tree>`, `attrs=`, `read_group(`, xpaths against Odoo-19 core):

| Priority | Module | Manifest | State | Work |
| -------- | ------ | -------- | ----- | ---- |
| **1 (now)** | `l10n_ar_inflation_adjustment` (mueve-modules) | `18.0.1.0.0` | Views already converted to 18/19 syntax by `[MIG]` commits; 3 Odoo-19 breakers found | Fix 2 broken xpaths (account form `deprecated` field removed; search filter `activeacc` renamed `inactiveacc`), remove `<group>` wrapper in the index search view (banned in 19), `read_group` → `_read_group` (2 call sites in the wizard), bump version → `19.0.1.0.0`, fresh-DB install smoke |
| 2 | `account_payment_multi` (adhoc account-payment) | `18.0.1.1.0` | XML already list/attrs-clean | Version bump only (decide: `[FIX-adhoc]` bump or leave for upstream) |
| 3 | `account_financial_amount` (adhoc account-financial-tools) | `13.0.1.0.0` | One `attrs=` left in `wizard/res_config_settings_views.xml` | Inline the `attrs`, bump version |
| 4 | `l10n_ar_reports` (adhoc odoo-argentina-ce) | `16.0.1.0.0` | Genuinely unmigrated Odoo-16 code (2 `<tree>` views, `attrs=`, `states=`) | Full migration pass (biggest remaining item) |
| cleanup | `l10n_ar_tax_ratio` | — | **Orphan**: dropped upstream in the 19.0 re-import; only a stale `custom-addons/` copy remains (copy_addons.sh cannot prune it — manifest still present) | `rm -rf custom-addons/l10n_ar_tax_ratio` + document |
| ✅ done | `payment_sipago` (submodule `payment-sipago`) | was `16.0.1.1.0` | **Migrated 2026-09-04** (`feat: migrar a Odoo 19.0`): full `payment` API rework (`_search_by_reference`+`_process`+`_apply_updates`, `_create_child_transaction`, `payment_method_ids`, hooks `(env, code)`, foreign-xmlid `forcecreate`); 29/31 tests green (2 real-network `external` excluded) | none — submodule `19.0` branch; supermodule `.gitmodules` entry + pointer bumped |

Conventions for all of the above: edit in the submodule, `[FIX-adhoc]` prefix
for adhoc-modules in-place fixes, `[MIG]`/`[FIX]` for `mueve-modules/`, then
`bash copy_addons.sh` + install/upgrade smoke on a scratch DB.

---

# (Previous pass — COMPLETE) Polish `l10n_ar_fiscal_ws` + `l10n_ar_fiscal_ws_fe` after the 18→19 migration session

> **Scope:** bug-fix and cleanup work on two ARCA (ex-AFIP) web-service modules
> after the migration session that ended on 2026-08-05. This file is the
> **only** hand-over document for the next agent; everything else the agent
> needs is already in `AGENTS.md` (env, commands, conventions) and
> `submodules/odoo-argentina/PLAN.md` (subtree mechanics). Do not duplicate
> either here.
>
> **Target executor:** an LLM with write access to `Mueve-TEC/odoo-argentina`
> branch `19.0`. Read this file and `AGENTS.md` in full before touching anything.

---

> ## ✅ STATUS (2026-08-06): THIS PASS IS COMPLETE — DO NOT RE-DO IT
>
> All P1–P9 / F1–F6 / T1 items below were executed and **merged** upstream via
> PR `Mueve-TEC/odoo-argentina#2` (`ar_fe_fiscal_ws` → `19.0`), plus these
> extra `[FIX-adhoc]` follow-ups on top:
>
> - homologation-cert warning (padrón direct/mass popup + wizard banner)
> - persist connection TA before the dummy/pos `ArcaError` raise
> - CAE `response_dict` None-safe on rejected/observed results (`CAEFchVto`)
> - "Check rate" no-crash when ARCA returns no cotización (button hidden when
>   `currency_id.name == 'ARS'`)
> - invoice-date warning before the CAE request
> - wizard skippable when ARCA reports a per-partner error (RG 4280/18)
> - **live environment reads** (`arcaws.env.type` applies without restart) and
>   **hard `UserError`** on invalid env values
> - CAE rejection surfacing of ARCA `<Errors>` (`_l10n_ar_format_arca_error`)
> - POS module migration (`l10n_ar_pos_afipws_fe` → 19.0) by the POS agent
>
> `l10n_ar_fiscal_ws` = `19.0.1.8.1`; `l10n_ar_fiscal_ws_fe` = `19.0.1.1.0`;
> `l10n_ar_pos_afipws_fe` = `19.0.1.0.0`.
> 28+ automated tests green (all mock `call_arca_method`).
>
> **Still deferred (only these):** F6 (`en.po`), C1/C2 cosmetic renames,
> D1 OpenUpgrade migrations, and the real-ARCA production homologation smoke.
> The `submodules/odoo-argentina` pointer was since bumped and committed in
> the supermodule (see AGENTS.md); the next agent should NOT re-run the
> steps below.

---

## 0. Starting state (verified at end of session 2026-08-05)

All session work is already committed **and pushed** to
`Mueve-TEC/odoo-argentina` branch `19.0`. The seven commits land on top of
`b52e84330 [FIX] pre-commit config`:

```
afcd9c15a [FIX-adhoc] l10n_ar_fiscal_ws: fix button text
84634308a [FIX-adhoc] l10n_ar_fiscal_ws: fix province + city mapping from real ARCA A5 responses
e2236dd07 [FIX-adhoc] l10n_ar_fiscal_ws: fix imp_iva + monotributo + CABA matching pyafipws A5
34d21b274 [FIX-adhoc] l10n_ar_fiscal_ws: cherry-pick best of padrón PRs #6/#8/#9/#10
18955ec61 [FIX-adhoc] l10n_ar_fiscal_ws: finish Padrón partner update (a5 -> constancia_inscripcion)
9dd3209be [FIX-adhoc] l10n_ar_fiscal_ws_fe: remove unreachable legacy pyafipws code
44a05d857 [FIX-adhoc] l10n_ar_fiscal_ws_fe: fix broken 'Check rate' button
```

Manifest versions in the tree right now:

| Module                 | Path (under `submodules/odoo-argentina/adhoc-modules/odoo-argentina-ce/`) | `version`                     |
| ---------------------- | ------------------------------------------------------------------------- | ----------------------------- |
| `l10n_ar_fiscal_ws`    | `l10n_ar_fiscal_ws/__manifest__.py`                                       | `19.0.1.8.0`                  |
| `l10n_ar_fiscal_ws_fe` | `l10n_ar_fiscal_ws_fe/__manifest__.py`                                    | `19.0.1.0.0` ← **needs bump** |

Working tree of the submodule should be clean (`git -C submodules/odoo-argentina status --short` empty). If the agent committed but did not push, push before starting:

```bash
cd submodules/odoo-argentina && git push origin 19.0
```

### What already works (do not re-break)

Verified on **real ARCA homologation** (CUIT 20306606108, Córdoba monotributista):

- LoginCms via QWeb template + `cryptography` PKCS7 → zeep `Client.service.loginCms`
- `getPersonaList_v2` dispatched through `arcaws.method → call_arca_method → call_arca_service → zeep`
- `zeep.helpers.serialize_object` runs before `safe_eval` on `response_dict`
- Name (`apellido, nombre` or `razonSocial`) ✅
- Street (`domicilioFiscal.direccion`) ✅
- City = ARCA `localidad` (a barrio for CABA — user-confirmed preference)
- ZIP ✅
- **State matched via `domicilioFiscal.idProvincia` (int) → `_ARCA_PROVINCIA_ID_TO_CODE` → ISO 3166-2:AR `code`** (exact match, accent-proof). The map is in `res_partner.py` as a class attribute; do not remove it.
- Responsibility: RM (NI + monotributo), IVARI (impuesto 30), IVAE (impuesto 32), CF (NI, no mono). Impuestos union of `datosMonotributo.impuesto + datosRegimenGeneral.impuesto` (mirror of `pyafipws.ws_sr_padron.WSSrPadronA5`).
- zeep single-element arrays normalized dict→list (zeep quirk).
- Direct update `update_from_padron_arca` + `display_notification`
- Mass batched update `action_update_from_padron_mass` (batches of `_PADRON_BATCH_SIZE=100`)
- Wizard diff with `real_value`/`field_label`/`value_changed`/`change_indicator` and M2O/M2M handling
- FE: `do_pyafipws_request_cae` via `FECAESolicitar` data-driven method
- FE: "Check rate" button (`get_pyafipws_currency_rate`) via `FEParamGetCotizacion`
- OWL error dialog registered on `web._assets_core`
- `wsfecred` `arcaws` record restored with corrected URLs (production → `serviciosjava.afip.gob.ar`, homologation → `fwshomo.afip.gov.ar`)

### Real ARCA A5 response shape (confirmed via the since-removed debug log)

The `persona_data` dict (after zeep `serialize_object`) is an `OrderedDict` with
exactly these top-level keys:

```
datosGenerales: {
  apellido, nombre, razonSocial (None for FISICA with apellido/nombre),
  tipoPersona ("FISICA" | "JURIDICA"), tipoClave ("CUIT"),
  idPersona (int CUIT), estadoClave ("ACTIVO"),
  mesCierre (int),
  domicilioFiscal: {
    direccion, localidad (barrio for CABA), codPostal,
    descripcionProvincia (UPPERCASE, no accents: "CORDOBA", "TUCUMAN"),
    idProvincia (int, see _ARCA_PROVINCIA_ID_TO_CODE),
    tipoDomicilio ("FISCAL"), tipoDatoAdicional (None), datoAdicional (None)
  },
  caracterizacion: [], dependencia: None,
  esSucesion ("NO"), fechaContratoSocial: None, fechaFallecimiento: None
}
datosMonotributo: {
  actividad: [...], actividadMonotributista: {...},
  categoriaMonotributo: {descripcionCategoria, idCategoria, idImpuesto, periodo} | {},
  componenteDeSociedad: [],
  impuesto: [{descripcionImpuesto, estadoImpuesto ("AC"|"EX"|"NA"), idImpuesto, motivo, periodo}]
}
datosRegimenGeneral: {
  actividad: [...], categoriaAutonomo: None,
  impuesto: [{...same shape as datosMonotributo.impuesto...}],
  regimen: []
}
errorConstancia: None | dict
errorMonotributo: None | dict
errorRegimenGeneral: None | dict
```

Single-element SOAP arrays are serialized by zeep as a **dict**, not a list.
The existing `_as_list` helper inside `_transform_arca_persona_to_census`
normalizes this; any new code that iterates ARCA arrays must use the same pattern.

---

## 1. Reference implementation to mirror

The working v16 implementation is in
`Mueve-TEC/odoo-argentina` branch `16.0`, module `l10n_ar_padron/models.py`. It
calls `pyafipws.WSSrPadronA5.Consultar(cuit)`, which internally:

- unions `datosMonotributo.impuesto + datosRegimenGeneral.impuesto`
- builds `self.impuestos = [imp["idImpuesto"] for imp in impuestos]`
- in `analizar_datos`: `32→EX, 33→NI, 34→NA, 30→S, else→N`
- `monotributo = "S" if cat_mt else "N"` (just checks `categoriaMonotributo` dict non-empty)
- `provincia = PROVINCIAS.get(domicilio.get("idProvincia"), "")` — uses `idProvincia` for the lookup, not `descripcionProvincia`

The current v19 code in `res_partner.py` already mirrors this. **Do not regress
any of these mappings.**

pyafipws source (for cross-reference, do NOT import it):
`/tmp/opencode/pyafipws/ws_sr_padron.py` and `padron.py` (clone README in audit
history). The `PROVINCIAS` dict in `padron.py` matches the
`_ARCA_PROVINCIA_ID_TO_CODE` we already ship (just keyed by name string instead
of ISO code).

---

## 2. Remaining work (priority order)

For each item: severity, exact files/lines (relative to
`submodules/odoo-argentina/adhoc-modules/odoo-argentina-ce/`), root cause, fix.
**Always edit in the submodule, never in `custom-addons/`.** Run
`bash copy_addons.sh && make restart` after each item. Commit with
`[FIX-adhoc] <module>: <desc>` (see AGENTS.md §3 for the convention).

### P1 — high — Drop `title_case` wizard toggle

**Files:** `l10n_ar_fiscal_ws/wizard/res_partner_update_from_padron_wizard.py`,
`l10n_ar_fiscal_ws/wizard/res_partner_update_from_padron_wizard_view.xml`

**Why:** upstream PR #10 and PR #11 explicitly decided to preserve ARCA's
original casing and not apply `.title()`. The `title_case` boolean field
(lines 149-152), the `_get_default_title_case` helper (lines 108-112), and the
`.title()` call inside `change_partner` (line 187:
`if self.title_case and key in ("name", "city", "street"): new_value = new_value and new_value.title()`)
were carried forward from PR #11 but contradict that decision.

**Fix:** delete the field, the helper, the `if self.title_case:` block in
`change_partner`. If the wizard view has a `<field name="title_case"/>`, delete
that too. Do NOT leave the toggle on with `.title()` removed — that's just dead
state.

**Verify:** `grep -rn "title_case" l10n_ar_fiscal_ws/wizard/` returns nothing.
`make lint-odoo-ar` clean on those two files.

### P2 — high — Downgrade PII info-log in `change_partner`

**File:** `l10n_ar_fiscal_ws/wizard/res_partner_update_from_padron_wizard.py`

**Lines:** 173-179 — `_logger.info("=== Datos ARCA para %s ===\n Campos: %s\n Valores: %s", partner.name, ..., partner_vals)`

**Why:** dumps full partner PII (name, address, all returned vals) at INFO
level. Copilot flagged this on PRs #6, #8, #11. Production logs would fill with
personal data on every padrón update.

**Fix:** wrap in `if _logger.isEnabledFor(logging.DEBUG):` and switch to
`_logger.debug(...)`. Same pattern already used in
`get_data_from_padron_arca` (lines 563-571 in the current tree).

### P3 — high — Surface ARCA `errorConstancia` / `errorMonotributo` / `errorRegimenGeneral`

**File:** `l10n_ar_fiscal_ws/models/res_partner.py`,
`_validate_and_serialize_arca_response` and/or `get_data_from_padron_arca`

**Why:** pyafipws A5 lines 209-212 explicitly extends `self.errores` from
these three keys. When ARCA returns an error (e.g. "pendiente domicilio fiscal
electrónico RG 4280/18"), these keys hold a dict with an `error` field. The v19
code currently ignores them and produces the misleading
`UserError("ARCA no devolvió datos válidos")` instead of the real reason.

**Fix:** in `_validate_and_serialize_arca_response` (or right after it
returns `persona_data` in `get_data_from_padron_arca` and `action_update_from_padron_mass`),
collect:

```python
errors = []
for k in ("errorConstancia", "errorMonotributo", "errorRegimenGeneral"):
    e = persona_data.get(k)
    if e:
        errors.append(str(e.get("error") if isinstance(e, dict) else e))
if errors:
    raise UserError(_("ARCA reportó errores para el CUIT %s:\n%s") % (cuit, "\n".join(errors)))
```

Use the same pattern in the mass-update loop so a per-CUIT error gets recorded
in `error_details` instead of crashing the batch.

**Verify:** cannot easily reproduce an ARCA error without a special CUIT, but
unit-testable: write a `tests/test_padron_errors.py` that monkey-patches
`call_arca_method` to return a dict with `errorConstancia={"error": "X"}`
and asserts the raise.

### P4 — high — `l10n_ar_fiscal_ws_fe_min_ammount` is broken

**File:** `l10n_ar_fiscal_ws/models/res_partner.py:673-680`

**Why:** calls `ws.call_arca_service("ConsultarMontoObligadoRecepcion", {...}, auth="plain")`
directly. No `token`/`sign` passed; `auth="plain"` is not a valid kwarg for the
SOAP method. The `wsfecred` `arcaws` record was re-added today so the connection
succeeds, but the SOAP call itself will fail. No UI button references this
method (confirmed via `grep -rn "l10n_ar_fiscal_ws_fe_min_ammount" submodules`
— zero hits outside the model definition).

**Fix (preferred):** delete the method and the `mipyme_required` /
`mipyme_from_amount` fields (lines 18-22) since nothing calls them either.

**Fix (if MiPyME credit-invoice obligation lookup is actually needed):** add a
new `arcaws.method` record in `l10n_ar_fiscal_ws/data/arcaws.xml` for the
`wsfecred` service:

```xml
<record id="arcawsfecred_method_get_monto" model="arcaws.method">
    <field name="name">get_monto_obligado_recepcion</field>
    <field name="arcaws_id" ref="arcawsfecred"/>
    <field name="method_name">ConsultarMontoObligadoRecepcion</field>
    <field name="definition_dict">{
        "token": connection.token,
        "sign": connection.sign,
        "cuitRepresentada": int(company_id.partner_id.ensure_vat()),
        "cuitConsultada": int(extra_values["cuit"]),
        "fechaEmision": extra_values["fecha_emision"].strftime("%Y-%m-%d"),
    }</field>
    <field name="response_dict">result = ws_res</field>
</record>
```

then rewrite `l10n_ar_fiscal_ws_fe_min_ammount` to dispatch via
`method_id.call_arca_method(obj=self, extra_values={"cuit": self.l10n_ar_vat, "fecha_emision": fields.Date.today()})`.

Ask the project owner which path before doing it — deletion is safe if the feature
is unused; reimplementation needs ARCA homologation testing.

### P5 — med — `arcaws.connection` ACL too permissive

**File:** `l10n_ar_fiscal_ws/security/ir.model.access.csv`

**Line:** `access_arcaws_connection_manager,...,model_arcaws_connection,base.group_user,1,1,1,1`

**Why:** `arcaws.connection` records contain live ARCA auth tokens and signs.
Granting full CRUD to `base.group_user` (every internal user) lets any employee
read/steal/edit/delete the tokens.

**Fix:** change `base.group_user` → `base.group_system` on the `_manager`
line only. Keep the `_user` line as read-only.

### P6 — med — Manifest `external_dependencies` missing `zeep`

**File:** `l10n_ar_fiscal_ws/__manifest__.py:12`

**Current:** `"external_dependencies": {"python": ["OpenSSL"]},`

**Why:** `arcaws.py`, `arcaws_connection.py`, `res_company.py`, `res_partner.py`,
`exceptions.py` all `import zeep` at module load. Odoo's
`external_dependencies` check is install-time; if a future image lacks zeep,
the install will only fail at runtime import, not at the manifest check.

**Fix:** `"external_dependencies": {"python": ["OpenSSL", "zeep"]},`

### P7 — low — Wizard dead branches referencing non-existent fields

**File:** `l10n_ar_fiscal_ws/wizard/res_partner_update_from_padron_wizard.py`

**Lines:** 217 (`elif key in ("impuestos_padron", "actividades_padron"):`) and
247 (`if field.field in ("impuestos_padron", "actividades_padron"):`)

**Why:** `impuestos_padron` and `actividades_padron` do not exist on
`res.partner` (confirmed: `grep -rn "impuestos_padron\|actividades_padron"
submodules/odoo-argentina --include=*.py` returns only these two hits, both in
dead branches of the wizard). Never triggered because `_get_domain` (line 92)
filters to `name, street, city, zip, state_id, l10n_ar_afip_responsibility_type_id,
last_update_census`.

**Fix:** delete both blocks. The M2O branch on lines 191-216 already covers
`state_id` and `l10n_ar_afip_responsibility_type_id`; the else branch (229-240)
covers all other valid fields.

### P8 — low — `update_constancia` wizard field unused

**File:** `l10n_ar_fiscal_ws/wizard/res_partner_update_from_padron_wizard.py:146-147`

**Why:** declared as `update_constancia = fields.Boolean(default=True)` but
grep shows it's never read in `change_partner`, `_update`, or any view. Vestigial
from before the PR #11 refactor.

**Fix:** delete the field declaration. If the wizard view has a
`<field name="update_constancia"/>`, remove it too.

### P9 — low — Empty-string overwrites

**File:** `l10n_ar_fiscal_ws/models/res_partner.py`, `parse_census_vals`
around line 63-68

**Why:** `parse_census_vals` always includes `street`, `city`, `zip` with
empty-string defaults in the returned `vals` dict. If ARCA returns no
`domicilioFiscal` (or only partial), existing partner fields are overwritten
with `""`, silently erasing user data.

**Fix:** guard each key — only include it in `vals` if the ARCA value is
non-empty. Pseudocode:

```python
_direccion = get_value(census, "direccion")
if _direccion:
    vals["street"] = _direccion
# same for city, zip
```

Or after building vals: `vals = {k: v for k, v in vals.items() if v or k in keep_fields}`.

Note: `name` already has this guard (lines 71-73), `state_id` already conditional on
state match. Just bring `street`/`city`/`zip` to the same standard.

### F1 — med — Bump `l10n_ar_fiscal_ws_fe` manifest version

**File:** `l10n_ar_fiscal_ws_fe/__manifest__.py:3`

**Current:** `"version": "19.0.1.0.0",`

**Why:** commits `44a05d857` (Check rate button rewrite) and `9dd3209be`
(legacy code removal) shipped functional changes after `19.0.1.0.0`; the manifest
was never bumped. Odoo's upgrade mechanism uses the version bump to decide whether
to re-run views/data-migrations.

**Fix:** bump to `"19.0.1.1.0",`. If the agent also makes any other `_fe`
changes in this pass, bump minor accordingly (e.g. `19.0.1.2.0`).

### F2 — med — Remove raw `env.cr.commit()` inside business logic

**Files:**

- `l10n_ar_fiscal_ws/models/res_company.py:207` (`self.env.cr.commit()  # pylint: disable=invalid-commit`)
- `l10n_ar_fiscal_ws_fe/models/account_move.py:311` and `:329` (inside `do_pyafipws_request_cae`)

**Why:** Odoo 19's transaction model disallows ad-hoc commits within a web
request; can corrupt cursor state under concurrent calls. The CAE case has a
legitimate intent (CAE is irrevocable — once obtained, you don't want a later
exception in the same request to roll it back). The correct pattern in Odoo 19
is to register a post-commit hook:

```python
self.env.cr.post_initialize(_lambda_or_method)
```

or to use `@api.model_create_multi` / `with_context` patterns that ensure the
CAE write atomicity at the request boundary. The simplest defensible fix is to
**remove the commits** and rely on the standard request-level atomicity: if
the request fails after CAE is obtained, the next user retry will skip the
already-CAE'd invoice because `_post` filters
`not x.afip_auth_code` (line 201).

**Caution:** test the rejection path before merging — make sure that a CAE
obtained then a rejection in a sibling invoice leaves the DB in a consistent
state (the rejected invoice should not have `afip_auth_code` set; the approved
one should).

### F3 — low — Drop `base64.encodestring` monkey-patch

**File:** `l10n_ar_fiscal_ws_fe/models/account_move.py:13`

**Current:** `base64.encodestring = base64.encodebytes`

**Why:** global module-load side-effect to keep `base64.encodestring` (removed
in Python 3.9) working. There is exactly one call site (`account_move.py:177`,
`base64.encodestring(json.dumps(qr_dict, ...).encode("ascii"))` inside
`_compute_qr_code`). Cleaner to update the call site and remove the patch.

**Fix:** at the single call site in `_compute_qr_code` change `base64.encodestring(...)`
→ `base64.encodebytes(...)`. Delete line 13. No other call sites in the module.

### F4 — med — `report_invoice.xml` disabled

**File:** `l10n_ar_fiscal_ws_fe/__manifest__.py:18,21`

```python
"data": [
    "data/arcaws.xml",
    "views/account_move_views.xml",
    "views/account_journal_view.xml",
    # "views/report_invoice.xml",        ← disabled
    "views/res_config_settings.xml",
    "views/menuitem.xml",
    # "wizard/account_validate_account_move.xml",   ← disabled, file also missing on disk
],
```

**Why:** the QR/CAE barcode block in `views/report_invoice.xml` would change
invoice PDFs to embed ARCA's QR code and CAE — a regulatory requirement for AR
electronic invoices. PR #11 (the upstream we ported) shipped it disabled; the
project owner must confirm whether Mueve needs it.

**Fix (if needed):**

1. Confirm with project owner: do Mueve's customers print ARCA QR on invoices?
2. If yes: uncomment line 18 ONLY (line 21 references a missing wizard file —
   leave it commented or recreate the file from the upstream diff).
3. Run `make upgrade DB=<db> MODULE=l10n_ar_fiscal_ws_fe` to register the new view.
4. Print an invoice that has `afip_auth_code` set, verify the QR renders.

**Fix (if not needed):** leave as-is; this item is **decide-and-document**, not
automatable.

### F5 — low — Dead commented buttons in journal view

**File:** `l10n_ar_fiscal_ws_fe/views/account_journal_view.xml:14-16`

Three commented-out `<button>` blocks referencing non-existent methods
(`get_pyafipws_zonas`, `get_pyafipws_NCM`, `get_pyafipws_post_invoice_numbers`).

**Fix:** delete the three commented lines.

### F6 — low — i18n only `es.po`

**Files:** `l10n_ar_fiscal_ws/i18n/es.po`, `l10n_ar_fiscal_ws_fe/i18n/es.po`

**Why:** no `en.po`, no `l10n_ar_*.po`. English-speaking users get untranslated
strings. Cosmetic; the upstream only ships `es.po`.

**Fix:** generate `l10n_ar_fiscal_ws.pot` via
`./odoo-bin -d <db> --i18n-export=/tmp/l10n_ar_fiscal_ws.pot --modules=l10n_ar_fiscal_ws --stop-after-init`,
then create `en.po` from the template. Or skip — only if English UI is a
requirement, which is unlikely for an AR localization.

### C1 — cosmetic — `pyafipws_*` method names

**Files:** `l10n_ar_fiscal_ws_fe/models/account_move.py` (`do_pyafipws_request_cae`,
`get_pyafipws_currency_rate`), `account_journal.py` (`test_pyafipws_dummy`,
`test_pyafipws_point_of_sales`, `get_pyafipws_cuit_document_classes`),
`views/account_move_views.xml:17`, `views/account_journal_view.xml:11-13`

**Why:** ARCA is the new official name; "pyafipws" prefixes are vestigial.
The UI buttons say "Dummy Test", "Check rate", "Get Points of Sale" — the
strings are fine; only the Python method names reference the old library. A
rename would touch the view `name=` attributes and any external callers
(none in this tree). Not blocking.

**Fix (optional):** rename to `do_arca_request_cae`, `get_arca_currency_rate`,
`test_arca_dummy`, etc. Keep the XML button `string=` labels as-is. **Only do
this if there are no other consumers of these method names in custom Mueve
modules** — grep `submodules/odoo-union` and `mueve-modules` first.

### C2 — cosmetic — POS-type codes

**File:** `l10n_ar_fiscal_ws_fe/models/account_journal.py:29-31,36`

Codificaciones `RAW_MAW`, `BFEWS`, `FEEWS` — likely typos for `WSFE`/`WSFEX`/`WSBFE`.
User-visible in the journal form's pos-system selector. Pre-existing, not blocking.

**Fix (optional):** normalize only if no live DB has the quirky codes already
stored in `account.journal.l10n_ar_afip_pos_system` columns (renaming selection
keys requires a data migration or the values silently become unset).

---

## 3. Tests plan (T1) — write after P1–P9 land

Both modules have **zero** automated tests. Concrete skeleton (place under
`l10n_ar_fiscal_ws/tests/` and `l10n_ar_fiscal_ws_fe/tests/`). OCA convention:
`@tagged('post_install')` and a custom `@tagged('l10n_ar_fiscal_ws')` /
`@tagged('l10n_ar_fiscal_ws_fe')` so you can filter.

```
l10n_ar_fiscal_ws/tests/
  __init__.py
  common.py                              # ArcaTestCommon: demo cert + env-type param
  test_login_cms_template.py            # render QWeb, no network
  test_call_arca_method_dispatch.py     # mock zeep Client.service, assert safe_eval runs
  test_padron_get_persona.py            # mock call_arca_method, assert parse_census_vals
  test_padron_responsibility.py         # 4 cases: RM/IVARI/IVAE/CF + NA edge
  test_padron_province.py               # idProvincia int → state_id match (accent-proof)
  test_padron_errors.py                 # errorConstancia etc. → UserError (P3 regression)
  test_padron_mass_batched.py           # batch boundary, persona_by_cuit None filter
  test_data_urls.py                     # wsfecred production_url != fwshomo (regression)

l10n_ar_fiscal_ws_fe/tests/
  __init__.py
  common.py
  test_currency_rate.py                 # regression for today's fix #1
  test_cae_happy_path.py                 # mocked FECAESolicitar → CAE set
  test_cae_rejection.py                  # mocked rejection → state + observations
  test_observations_parse.py             # l10n_ar_arca_ws_parse_observations
  test_qr_code_compute.py                # _compute_qr_code with afip_auth_code
```

Run with:

```bash
make test-install MODULE=l10n_ar_fiscal_ws,l10n_ar_fiscal_ws_fe \
  TEST_TAGS=/l10n_ar_fiscal_ws,/l10n_ar_fiscal_ws_fe
```

Mock pattern: `unittest.mock.patch('odoo.addons.l10n_ar_fiscal_ws.models.arcaws_method.Client')`
returning a stub with the SOAP method returning a canned dict; assert what
`call_arca_method` writes on the partner. Do **not** call real ARCA in tests.

---

## 4. Deferred / out of scope (do NOT do in this pass)

- **D1 — `migrations/19.0.1.x.0/` directories.** The project owner decided
  (this session) that only **fresh installs** are supported for now. If a
  customer needs to upgrade from the old 18.0 `l10n_ar_afipws`, table renames
  (`afipws_*` → `arcaws_*`) and `ir.model.data` xmlid renames need an
  OpenUpgrade-style `pre-migrate.py` with raw SQL. Skipping is the documented
  current state; do not add migration scripts preemptively.
- **F4 `report_invoice.xml`** — depends on a project-owner decision (see above).
- **C1, C2** — cosmetic; only if no live data depends on the names/codes.

---

## 5. Definition of done for this pass

> **All items below are DONE (2026-08-06) and merged via PR #2.** The only
> remaining item is the real-ARCA production smoke (deferred).

All of:

- [x] P1 — `grep -rn "title_case" submodules/odoo-argentina/adhoc-modules/odoo-argentina-ce/l10n_ar_fiscal_ws/` empty
- [x] P2 — wizard `change_partner` no longer logs PII at INFO
- [x] P3 — `errorConstancia`/`errorMonotributo`/`errorRegimenGeneral` raise UserError with their content (regression test `tests/test_padron_errors.py` passes)
- [x] P4 — `l10n_ar_fiscal_ws_fe_min_ammount` rewritten via `arcaws.method` (reimplemented, project owner confirmed)
- [x] P5 — `ir.model.access.csv` line for `arcaws_connection_manager` uses `base.group_system`
- [x] P6 — `l10n_ar_fiscal_ws/__manifest__.py` `external_dependencies` includes `zeep`
- [x] P7 — wizard dead `impuestos_padron`/`actividades_padron` branches deleted
- [x] P8 — `update_constancia` field + view entry removed
- [x] P9 — `parse_census_vals` no longer overwrites `street`/`city`/`zip` with empty strings
- [x] F1 — `l10n_ar_fiscal_ws_fe` manifest version bumped to `19.0.1.1.0`
- [x] F2 — `env.cr.commit()` removed from `res_company.py:207` and `account_move.py:311`; kept only on the CAE-success path (`account_move.py:329`, documented)
- [x] F3 — `base64.encodestring = base64.encodebytes` patch removed; call site updated
- [x] F5 — dead commented buttons in `account_journal_view.xml` removed
- [x] T1 — `test_padron_responsibility.py`, `test_padron_province.py`, `test_padron_errors.py`, `test_currency_rate.py`, `test_data_urls.py` written and passing (28+ tests green on `Monotributo_admin`, all mocked)
- [x] `make lint-odoo-ar` clean on touched files (ruff/format/xml/po; pylint-odoo has only pre-existing noise on legacy files — new test files rate ≥9.0)
- [ ] Real-ARCA production homologation smoke: padrón update on RM, IVARI, IVAE, CF partners; CAE request on one out-invoice; "Check rate" button; all four pass (partially done in homologation by the owner — deferred)
- [x] 13+ commits on `submodules/odoo-argentina` `19.0`, each with `[FIX-adhoc] <module>: <desc>` prefix, merged via PR #2

---

## 6. Things the agent must NOT do

- Do not edit anything in `custom-addons/` — edit in `submodules/odoo-argentina/adhoc-modules/odoo-argentina-ce/<module>/` then `bash copy_addons.sh && make restart`.
- Do not commit the supermodule pointer to `submodules/odoo-argentina` unless the project owner asks; bump-and-commit is a separate orchestration step.
- Do not touch `mueve-modules/` — out of scope for this pass.
- Do not import `pyafipws` or `pysimplesoap` anywhere — the migrated modules use `zeep` exclusively.
- Do not add `commit=` calls or open transactions inside computed fields.
- Do not rename `_ARCA_PROVINCIA_ID_TO_CODE` or change its keys — the ARCA `idProvincia` mapping is authoritative.
- Do not re-enable `l10n_ar_afipws` / `l10n_ar_afipws_fe` (the old 18.0 module names) — they exist only as stale `custom-addons/` copies that have already been deleted once.
- Do not bundle unrelated cleanups into a single commit — one logical fix = one commit, per the OCA-style commit hygiene AGENTS.md implies.
- Do not push without local `make lint-odoo-ar` clean and at least one fresh-DB install smoke.
