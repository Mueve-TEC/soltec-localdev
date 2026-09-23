# MUEVE Modules Review Plan — Odoo 19 (branch `19.0-dev`)

> **Working document — do NOT commit** (AGENTS.md, Conventions #14: no loose
> planning notes in the supermodule). Durable outcomes go to the submodule docs
> (`POS_CONTEXT.md`, `MIGRATION_19.md`, `MIGRATION_NOTES.md`) or the commits.
> Update the tracker (§8) as phases complete; archive this file when Phase 4
> closes.

## 0. Objective

1. **Review** the 11 MUEVE modules with the official Odoo skills
   (`odoo-review`, `odoo-guidelines`, `odoo-web-guidelines`, `odoo-security`).
2. **Standardize pre-commit**: one consistent, OCA-appropriate stack applied to
   every repo that ships these modules (5 repos: four had diverging stacks,
   `payment-sipago` still has none).
3. **Define and implement a test strategy** for every module (initially 4 of 11
   modules had no tests at all; `delivery_correo_argentino` now has 26).

All module edits happen **only in `submodules/`**, then `bash copy_addons.sh`
(or `make sync`) + container restart; XML/data/security/manifest changes also
need `-u <module>` (see AGENTS.md "Editing modules"). Always `-d <db>` on CLI
runs. Commit only when asked, in each repo's own log style.

## 0.1 Status (living — last updated 2026-09-23)

**Done**

- **`delivery_correo_argentino` (Batch E):** reviewed, fixed, tested and
  committed. 1 HIGH, 4 MEDIUM, 10 LOW/INFO (all fixed except **MER-07**
  deferred); findings and evidence in §8.11. Test suite: **27 tests, all
  green** (`test_correo`).
- **Phase 0, one repo:** `odoo-argentina-envios` now has the canonical
  pre-commit config (`.pre-commit-config.yaml` + `package.json` /
  `.prettierrc.json`); `pre-commit run` on all files is green and the hook is
  installed.
- Follow-ups done: MiCorreo token 401 refresh, `i18n/es_AR.po`, and the module
  docs (D5/D9 reconciliation, ROADMAP prune). Open: **MER-07** only (needs a
  confirmed public tracking URL). Seven commits in the submodule
  (`97c7aaf..76353fc`, branch `19.0`), not pushed.

**Progress at a glance**

| Module | Review | Findings | Tests | Repo pre-commit |
|--------|--------|----------|-------|-----------------|
| `delivery_correo_argentino` | done | all fixed (MER-07 deferred) | 27 green | added |
| the other 10 | pending | — | per §5.2 | 4 repos pending |

## 1. Scope — module inventory (verified 2026-09-23)

Paths are relative to the repo root. `py/xml/js` = file counts.

| # | Module | Repo (submodule) | Path | py/xml/js | Tests today | i18n | Security | Version | Flags from inventory |
|---|--------|------------------|------|-----------|--------------|------|----------|---------|----------------------|
| 1 | `l10n_ar_fiscal_ws` | odoo-argentina | `submodules/odoo-argentina/adhoc-modules/odoo-argentina-ce/l10n_ar_fiscal_ws` | 20/15/**1** | 5 files (padron, certificate, data_urls) | es_AR.po | csv | 19.0.1.8.2 | ARCA core; `safe_eval` request templates (DB-stored, gotcha AGENTS.md #12); only module with `static/src` JS |
| 2 | `l10n_ar_fiscal_ws_fe` | odoo-argentina | `…/odoo-argentina-ce/l10n_ar_fiscal_ws_fe` | 12/6/0 | 4 files (move, currency, qr, rejection) | es_AR.po | **no csv** | 19.0.1.1.1 | Verify it only `_inherits`/`_inherit`s models with existing ACLs |
| 3 | `l10n_ar_pos_afipws_fe` | odoo-argentina | `…/odoo-argentina-ce/l10n_ar_pos_afipws_fe` | 6/0/0 | 1 file (pos_order) | es_AR.po | no csv | 19.0.1.0.1 | No views/XML — pure Python inheritance over POS |
| 4 | `l10n_ar_factura_qr` | odoo-ocr | `submodules/odoo-ocr/l10n_ar_factura_qr` | 6/7/0 | **none** | es_AR.po | xml + csv | 19.0.1.0.1 | **LGPL-3** (all others AGPL-3) — confirm intentional; deps image-baked (pyzbar, pdf2image, numpy) |
| 5 | `l10n_ar_inflation_adjustment` | odoo-argentina | `submodules/odoo-argentina/mueve-modules/l10n_ar_inflation_adjustment` | 7/7/0 | **none** | **none** | csv | 19.0.1.0.0 | No tests AND no i18n; wizard-driven accounting logic |
| 6 | `union_affiliation` | odoo-union | `submodules/odoo-union/union_affiliation` | 21/15/0 | 3 files (incl. `test_security.py`) | es_AR.po | csv | 19.0.1.2.0 | Has `migrations/` + `controllers/` + `wizards/`; base for modules 7–9 |
| 7 | `union_benefit_request` | odoo-union | `submodules/odoo-union/union_benefit_request` | 20/14/0 | 2 files | es_AR.po | csv | 19.0.1.1.0 | **`license` key not found** — verify/fix in manifest |
| 8 | `union_contribution` | odoo-union | `submodules/odoo-union/union_contribution` | 16/11/0 | 2 files | es_AR.po | csv | 19.0.1.1.0 | **`license` key not found** — verify/fix |
| 9 | `union_school_position` | odoo-union | `submodules/odoo-union/union_school_position` | 18/8/0 | 4 files | es_AR.po | csv | 19.0.1.1.0 | **`license` key not found** — verify/fix |
| 10 | `payment_sipago` | payment-sipago | `submodules/payment-sipago/payment_sipago` | 14/3/0 | 5 files (incl. `common.py`, integration) | es_AR.po | **no csv** | 19.0.1.0.0 | Webhook/checkout controller (CSRF/token review!); repo has `*_response_example.json` fixtures + `.env_example` |
| 11 | `delivery_correo_argentino` | **odoo-argentina-envios** | `submodules/odoo-argentina-envios/delivery_correo_argentino` | 10/3/0 | 1 file | **none** | **no security/ dir** | 19.0.1.0.0 | Repo is a 6th submodule NOT yet in AGENTS.md's tracked-submodules table |

Cross-module consumption (review with "code the diff never shows" in mind):

- `l10n_ar_fiscal_ws` is consumed by `l10n_ar_fiscal_ws_fe` and
  `l10n_ar_pos_afipws_fe` — signature/template changes ripple into both.
- `union_affiliation` is consumed by the other three union modules.
- `payment_sipago` extends Odoo 19 `payment` base (provider/transaction API).
- `delivery_correo_argentino` sits on top of `delivery` + the repo's
  `delivery-carrier/` tree (25 modules) — reviews must not break that stack.

## 2. Skill dispatch — how each module gets reviewed

Skills live in `~/.agents/skills/`. Load per session with the `skill` tool,
**except `odoo-security`**: the registry currently resolves that name to the
backup auditor (`odoo-security.bak-20260923`); the **official** house rules are
at `~/.agents/skills/odoo-security/SKILL.md` — read that file directly. The
`.bak`'s `scripts/` (`security_auditor.py`, `access_checker.py`,
`route_auditor.py`, `sudo_finder.py`, `sql_scanner.py`) remain useful as
**automated triage scanners** (Phase 1), but they are not the house rules.

### 2.1 Dispatch matrix (whole-module review = the "diff" is the module tree)

| Files in module | Skill / material to read |
|-----------------|--------------------------|
| `__manifest__.py` | `odoo-guidelines` → `guidelines/manifest.md` |
| `models/*.py`, `wizards/*.py` | `odoo-guidelines` → `guidelines/python.md`, `orm.md`, `fields.md`, `performance.md` |
| `controllers/*.py` | `odoo-guidelines` → `guidelines/controllers.md` **+** official `odoo-security` → "Routes: auth, POST, CSRF" |
| `views/*.xml`, `data/*.xml`, `security/*` | `odoo-guidelines` → `guidelines/xml.md`, `security.md` |
| QWeb reports (`report/`) | `odoo-guidelines` → `guidelines/reports.md` |
| `tests/*` | `odoo-guidelines` → `guidelines/tests.md` + this plan's §5 |
| `i18n/*.po` | `oca-checks-po` hook + `odoo-guidelines` → "Translate only static literals" (msgids in **English**, Spanish via `es_AR.po`) |
| `static/src/**` (JS/Owl/SCSS) | `odoo-web-guidelines` → `guidelines/javascript.md`, `scss.md` (today only `l10n_ar_fiscal_ws` has 1 JS + 1 JS-XML file) |
| `migrations/**` | `odoo-guidelines` → `guidelines/stable.md` + `odoo-oca-developer` → OpenUpgrade patterns |
| Everything security-sensitive | Official `odoo-security` sweep table: `sudo(`/`with_user(`, `cr.execute`/`SQL(`, domain injection, public (non-`_`) RPC-callable methods, `Markup(`/`t-raw`, password/token fields (`groups=`, `related_sudo`), `open()` vs `file_open`, `safe_eval`, `pickle`, `getattr/setattr`, secret comparison with `consteq`, mutable default args |

### 2.2 Per-module review workflow (uniform loop)

1. **Load** `skill(odoo-review)` (orchestrator) and read the sibling SKILL.mds
   fresh, per its Process section; read each mapped `guidelines/*.md` section
   **before** writing findings.
2. **Map** every file of the module tree to the sections above.
3. **Rules pass** — judge each file against its mapped sections.
4. **Merits pass** — per `odoo-review`: hunt the input/state that makes it
   wrong (edge values, rounding, timezones, empty and multi-record calls,
   concurrency, **the second run** — key for the inflation wizard and WSFE
   retries).
5. **Security pass** — run the `.bak` scanners for triage, then judge every
   hit against the official `odoo-security` skill (a hit is not a finding by
   itself).
6. **Version traps (Odoo 19)** — verify APIs against the 19.0 sources in the
   image before flagging/writing: no `attrs=`, no `<tree>` (list views), no
   `name_get`, `res.groups.privilege` (not `category_id`), and note the
   official skills may use `ir.access` (master) where 19 still says
   `ir.model.access` — confirm with `git grep` in the image sources.
7. **Consumers** — grep renamed/removed names, overridden methods and shared
   contracts (XML ids, context keys, `arcaws` templates) across the other
   module trees and `/mnt/extra-addons`.
8. **Record** findings in §8 with severity, `file:line`, defect, failure
   scenario, fix, and the guideline section it applies (or *judgement*).
   Every finding ends with a **Guidelines read:** line (odoo-review §Report).

### 2.3 Severity scale (shared with the security scanners)

CRITICAL (fix before anything ships) / HIGH (fix within the phase) / MEDIUM
(next release) / LOW (convenience). Every CRITICAL/HIGH fix lands with a
regression test (§5.2).

## 3. Pre-commit standardization — "MUEVE quality baseline v1"

### 3.1 Current state (verified)

| Repo | Config | pre-commit-hooks | OCA odoo-pre-commit-hooks | ruff | pylint-odoo | rstcheck | prettier |
|------|--------|------------------|---------------------------|------|------------|----------|----------|
| odoo-argentina | `.pre-commit-config.yaml` (adhoc stack at root) | v5.0.0 | v0.0.35 | v0.6.8 (120) | v9.1.3 (`--disable=E0401`, max-line 120) | v6.2.1 | no (deliberate: adhoc-subtree parity) |
| odoo-union | clone of the adhoc stack | v5.0.0 | v0.0.35 | v0.6.8 (120) | v9.1.3 (+ explicit disable set, max-line 120) | v6.2.1 | no |
| odoo-ocr | combined stack | v6.0.0 | v0.0.35 | **v0.13.0** (`ruff.toml`: **88**, single quotes) | v9.1.3 (`.pylintrc`, max-line **88**) | v6.2.1 | yes (3.6.2 + `@prettier/plugin-xml` 3.4.2) |
| payment-sipago | **none** (only `ruff.toml`, `.pretierrc.json`, `package.json` at root) | — | — | — | — | — | unused |
| odoo-argentina-envios | **none** (only `.ruff.toml`) -> `.pre-commit-config.yaml` added 2026-09-23 (Phase 0, this repo) | v6.0.0 | v0.0.35 | v0.13.0 (88) | v9.1.3 (shared disable set) | v6.2.1 | yes (3.6.2 + plugin-xml) |

Drift to eliminate: ruff v0.6.8 vs v0.13.0; line-length 88 vs 120; pylint arg
sets differ; prettier in two repos only; `payment-sipago` still with no hooks.
(`odoo-argentina-envios` was brought onto the canonical stack on 2026-09-23.)

### 3.2 Canonical stack (decision)

One template replicated in **all 5 repos** (pre-commit runs per git toplevel;
"applied in every module" = applied in every repo that ships the modules):

- **pre-commit-hooks v6.0.0** — same hook set as `odoo-ocr`'s config.
- **OCA `odoo-pre-commit-hooks` v0.0.35** (uniform today, keep):
  `oca-checks-odoo-module` with
  `--disable=xml-dangerous-qweb-replace-low-priority,xml-view-dangerous-replace-low-priority,xml-oe-structure-missing-id`
  and `oca-checks-po` with `--disable=po-pretty-format` (single `--disable`
  flag each — last-wins argparse semantics).
- **ruff-pre-commit v0.13.0** (`ruff` + `ruff-format`, `--fix
  --exit-non-zero-on-fix`). Config: a per-repo `pyproject.toml` with
  `target-version = py311`, `select = E,F,W,I,UP,B`, `ignore = E501,B008`,
  per-file-ignores for `__manifest__.py` and `migrations/*`, and
  `[tool.ruff.format] quote-style = "preserve"` (no full-tree quote rewrite).
  **A repo's existing `ruff.toml` / `.ruff.toml` is kept**, not deleted: it
  already carries the repo style (`odoo-argentina-envios` keeps 88). The
  pinned hook version is unified; line-length is not (see below).
- **pylint-odoo v9.1.3** — `--max-line-length=<repo>` plus one accumulated
  `--disable` list. Baseline shared with the own-code repos (from
  `odoo-union`): `C0103,C0114,C0115,C0116,C0209,C0415,R0801,R0903,R0904,R0911,`
  `R0912,R0913,R0914,R1702,R1705,R1710,R1719,R1725,W0104,W0212,W0511,W0621,W1404`,
  plus `E0401` (lint env lacks Odoo deps), `E0705` (false positive on
  `raise UserError(...) from error`, the cause being a `UserError` subclass),
  `W0223` (adapters intentionally leave unsupported operations inherited) and
  `W0613` (core hook signature `_get_close_locations(..., **kwargs)`); each
  disable keeps its justification comment. `adhoc-modules/` subtrees keep their
  upstream `pyproject.toml` pylint configs.
- **rstcheck v6.2.1**.
- **prettier 3.6.2 + `@prettier/plugin-xml` 3.4.2** (local `node` hook as in
  odoo-ocr) — in **every** repo, scoped to Mueve-owned code only. Prerequisite:
  a repo-root `package.json` with the two devDependencies, a `.prettierrc.json`
  (`xmlWhitespaceSensitivity: preserve`, `tabWidth: 4`, `printWidth: 88`) and
  `node_modules/` gitignored. Prettier 3 is ESM and ignores `NODE_PATH`, so the
  plugin only resolves from the repo root after `npm install` (odoo-ocr and
  odoo-argentina-envios already do this).
  - odoo-argentina: `files:` excludes `adhoc-modules/` (subtrees synced from
    ingadhoc; reformatting breaks future subtree merges).
  - odoo-argentina-envios: excludes `delivery-carrier/` (upstream OCA subtree)
    and `docs/` (API PDFs/manuals).
- **The OCA checks catch real code issues**: `oca-checks-odoo-module` flagged
  `xml-deprecated-data-node` on `<odoo><data noupdate="1">` — move
  `noupdate="1"` onto `<odoo>` and drop `<data>` (hit and fixed in
  odoo-argentina-envios).
- Shared `exclude:` block (svg, `static/lib/`, build/dist, LICENSE) as in the
  existing configs.

Rationale: OCA-appropriate = the OCA hook suite (`oca-checks-*` +
pylint-odoo) is the Odoo-specific core and is already the tree's de-facto
stack; unifying on the **newest** versions already in use minimizes new
surprises while ending the drift. **Line-length stays per repo for now**: 120
for `odoo-argentina` / `odoo-union` / supermodule, 88 for `odoo-ocr` /
`odoo-argentina-envios`. A forced 88 -> 120 rewrap is a code-wide change that
deserves its own commit per repo, not a side effect of the tooling rollout;
revisit once all 5 repos share the pinned hook versions.

### 3.3 Rollout steps (Phase 0)

> **Status 2026-09-23:** steps 1-3 done for **odoo-argentina-envios** (config
> added, all hooks green, QUAL-02 fixed). Still pending: `payment-sipago`
> (step 1, no config) and steps 2-6 for the other four repos.

1. Write/refresh `.pre-commit-config.yaml` in all 5 repos from §3.2
   (payment-sipago and odoo-argentina-envios get their **first** config).
2. Align the per-repo lint config: adopt the shared pylint disable set and the
   repo's `--max-line-length`; **keep** the repo's existing `ruff.toml` /
   `.ruff.toml` (do not delete it).
3. Per repo: `pre-commit install` (once) + `pre-commit run --all-files`;
   fix autofixables, triage the rest (fix, or documented `--disable`).
4. Commit per each repo's log style (`git log --oneline -5` first); then bump
   the supermodule gitlinks **only when asked**.
5. Supermodule Makefile: add `lint-union`, `lint-ocr`, `lint-sipago`,
   `lint-envios` targets mirroring `lint-odoo-ar` (Makefile:130).
6. Housekeeping in the same breath:
   - Update AGENTS.md: add `submodules/odoo-argentina-envios`
     (git@github.com:Mueve-TEC/odoo-argentina-envios.git, branch 19.0) to the
     tracked-submodules table + the pre-commit section (uniform baseline).
   - Manifest quick wins: add/verify `license` in union_benefit_request /
     union_contribution / union_school_position; confirm `l10n_ar_factura_qr`'s
     LGPL-3 is intentional (human decision); unify manifest quote style (or
     accept the drift once `quote-style=preserve` is the rule).
   - No git hooks at supermodule level (AGENTS.md) — lint manually before
     every commit: `pre-commit run ruff --files <path> && pre-commit run
     ruff-format --files <path>`.

## 4. Review execution order

- **Phase 0 — Tooling & housekeeping** (§3.3). Everything after lands
  pre-commit-clean. *Status: odoo-argentina-envios done; 4 repos pending.*
- **Phase 1 — Security sweep, all 11 modules** (fast, scripted + manual):
  run the `.bak` scanners per module, judge hits against official
  `odoo-security`. Known hotspots to eyeball first: `payment_sipago` webhook
  (csrf/token/`consteq`), `sudo()` + `safe_eval` in fiscal_ws, `ocr.arca.scan`
  sudo-based logging, union `controllers/` auth, `delivery_correo_argentino`
  missing `security/`, missing CSVs (#2, #3, #10). Fix CRITICAL/HIGH
  immediately, each with a regression test.
- **Phase 2 — Deep review by batch** (odoo-review two-passes per module):
  - **Batch A (fiscal core, highest risk):** `l10n_ar_fiscal_ws` →
    `l10n_ar_fiscal_ws_fe` → `l10n_ar_pos_afipws_fe`.
  - **Batch B:** `l10n_ar_factura_qr`, `l10n_ar_inflation_adjustment`.
  - **Batch C (money):** `payment_sipago`.
  - **Batch D (union):** `union_affiliation` → `union_contribution` →
    `union_benefit_request` → `union_school_position`.
  - **Batch E:** `delivery_correo_argentino`. **Done 2026-09-23** (§8.11;
    pulled forward ahead of Batch A at the user's request).
- **Phase 3 — Test strategy implementation** (§5), module by module as each
  module's review closes (findings → regression tests → missing suites).
- **Phase 4 — Wrap-up:** per-module DoD audit (§6); durable findings into
  submodule docs; gitlink bumps (when asked); archive this file.

## 5. Test strategy

### 5.1 Common rules (every module)

- **Framework/location:** `tests/test_<feature>.py`, imported from
  `tests/__init__.py`;   class `Test<Feature>` inheriting `TransactionCase`
  (`SavepointCase` is deprecated in recent versions — `TransactionCase` is
  the one to use); `HttpCase` only where controllers/portal
  behavior must be verified (union_\*, payment_sipago).
- **Tags:** every class `@tagged('post_install', '-at_install')` **plus the
  module name** (`@tagged('l10n_ar_fiscal_ws')`, …) so the harness can narrow:
  `make test MODULE=<m> TEST_TAGS=/<m>`.
- **Fixtures:** `setUpClass` (not `setUp`) with `cls.env`; explicit dates
  (never `today()`-dependent assertions); reuse
  `submodules/payment-sipago/*_response_example.json` as HTTP fixtures.
- **Mocking:** external services are **always** mocked
  (`unittest.mock.patch` on the transport/client layer): ARCA/AFIP WS (zeep /
  pyafipws-era clients), Sipago HTTP, Correo Argentino API. Tests never touch
  real networks or homologation credentials (`.env_example` values only).
  Keep using `arcaws.env.type` switches live (AGENTS.md #11) but pointed at
  mocked transports.
- **Security tests:** replicate odoo-union's `test_security.py` pattern
  (positive + `AccessError` via `with_user`) in every module that has its own
  ACLs (union quartet already has it — extend; add to fiscal_ws, factura_qr,
  inflation_adjustment, sipago if it defines models).
- **Baseline first:** run the existing suite before touching anything
  (`make test MODULE=<m>`) and fix reds before adding coverage.
- **Where to run:** a dedicated, disposable test DB in the harness
  (`test_correo` was created for `delivery_correo_argentino`; AGENTS.md lists
  `test_pos`, `pos_fix`, `admin`). Never test against a DB that matters.
  `--http-port 8099` on raw runs.
- **HTTP mocking pattern (established, reusable):** `tests/common.fake_response()`
  builds a `requests.Response`-like `Mock`; patch the adapter's session
  (`adapter._session.request = Mock(side_effect=[...])`) for a request
  sequence, and `patch.object(type(carrier), "log_xml")` to capture debug
  logging. See `delivery_correo_argentino/tests/`.
- **Migration/data notes:** `make test-install` exercises fresh-install paths;
  `arcaws.xml` template changes require `-u` on every DB (AGENTS.md #12);
  translations via `--i18n-overwrite` (AGENTS.md #6).

### 5.2 Per-module targets

| Module | Today | Target suite (type) | Key cases / mocks |
|--------|-------|---------------------|-------------------|
| `l10n_ar_fiscal_ws` | 5 files | extend (TransactionCase) | `arcaws.method` `definition_dict` `safe_eval` templates; `env.type` switch incl. `UserError` on invalid (AGENTS.md #11); certificate/CSR via `cryptography` (pyOpenSSL 26.4.0 pin, #13); ARCA error-code mapping as table-driven tests (dictionary in `POS_CONTEXT.md`); padrón (existing) keep green; the 1 JS file: assess a hoot test only if non-trivial |
| `l10n_ar_fiscal_ws_fe` | 4 files | extend (TransactionCase) | invoice FE flow with mocked WSFE; A5 homologation response shapes (fixtures from `MIGRATION_19.md`); rejection paths (existing `test_rejection.py` keep green); CAE allocation; currency rate edge cases |
| `l10n_ar_pos_afipws_fe` | 1 file | extend (TransactionCase; tour only if UI logic appears) | POS order → FE with mocked fiscal backend; error surfacing to POS; `pos.config` fiscal fields validation |
| `l10n_ar_factura_qr` | **none** | new suite (TransactionCase) | `_parse_arca_qr_url` float normalization (`cuit: 30717930076.0` → int); doc-code → `move_type` mapping (3/8/13 → in_invoice/in_refund); `_prepare_invoice_line_commands` account fallback chain; decoder `new=True` vs `new=False` (empty-field preservation, gotcha #2 of the module AGENTS.md); `ocr.arca.scan` states + manager-only access; synthetic ARCA QR-url fixtures (no real PDFs needed); keep `TESTING_19.md` as the E2E manual complement |
| `l10n_ar_inflation_adjustment` | **none** | new suite (TransactionCase) | wizard run over fixture index (IPC/ICL) periods; adjustment move balancing; **idempotency/second-run**; multi-period + boundary dates; security test on the wizard |
| `union_affiliation` | 3 files | extend | period boundary edge cases; wizard flows; migration smoke via `make test-install`; controllers → HttpCase (auth) |
| `union_contribution` | 2 files | extend | contribution computation incl. **rounding**; period aggregation; security matrix extension |
| `union_benefit_request` | 2 files | extend | approval state machine; wizard validation errors; HttpCase for controller auth |
| `union_school_position` | 4 files | extend | registration-date rules; affiliate extension (existing) keep green |
| `payment_sipago` | 5 files | extend + harden | provider config constraints; transaction state machine (pending/done/cancelled/refund); **webhook controller HttpCase with mocked outbound** — csrf strategy, token compare (`consteq`), no sudo-on-request-params; `test_sipago_integration.py` must prove it never hits the network (patch at transport level) |
| `delivery_correo_argentino` | 1 file | **done — 26 tests** (§8.11) | mocked `_session.request` for MiCorreo/PaqAr (token, rate, labels, tracking, agencies), parcel/timezone/error cases, and security (field `groups` + log redaction). Still open: `es_AR.po` |

Rule: every CRITICAL/HIGH finding fixed in Phase 1/2 gets a test in the same
PR/commit that proves the fix (fail-before/pass-after).

## 6. Definition of Done (per module)

- [ ] `pre-commit run --all-files` green in its repo (canonical stack, §3.2).
- [ ] `odoo-oca-developer` validator passes:
      `python ~/.agents/skills/odoo-oca-developer/scripts/validate_module.py <module_path>`
- [ ] Security sweep done; **0 open CRITICAL/HIGH**; MEDIUM/LOW triaged in §8.
- [ ] Review recorded in §8 with **Guidelines read:** line per module.
- [ ] Target test suite implemented; `make test MODULE=<m>` green on the test
      DB; `make test-install MODULE=<m>` green for fresh-install paths.
- [ ] `bash copy_addons.sh` + module upgrade + manual smoke on the test DB if
      XML/data/security/manifest changed.
- [ ] Translations: English msgids, `es_AR.po` present and `oca-checks-po`
      green; applied with `--i18n-overwrite` where needed.
- [ ] Manifest: `license` present, version `19.0.x.y.z`, OCA-clean keys.

Per-module status against this list: **`delivery_correo_argentino`** meets it
except translations (still no `es_AR.po`) and the deferred MER-07 tracking URL.

## 7. Command cheat sheet (this harness)

```bash
# sync sources (after ANY submodule edit)
bash copy_addons.sh            # or: make sync

# lint (canonical stack, per repo root)
cd submodules/<repo> && pre-commit run --all-files
make lint-odoo-ar              # supermodule wrapper (only odoo-argentina today)
make lint                      # supermodule infra files

# tests
make test MODULE=<m>                        # -u + --test-enable (filtered)
make test MODULE=<m> TEST_TAGS=/<m>         # narrowed by module tag
make test-install MODULE=<m>                # fresh install + tests
make test-raw MODULE=<m>                    # unfiltered output

# upgrade (XML/data/security/manifest changes)
make upgrade DB=<db> MODULE=<m>

# security triage scanners (backup skill — not the house rules)
python ~/.agents/skills/odoo-security.bak-20260923/scripts/security_auditor.py <module_path> --min-severity HIGH

# OCA structure validator
python ~/.agents/skills/odoo-oca-developer/scripts/validate_module.py <module_path>

# raw odoo CLI (full addons path — Makefile ADDONS_PATH omits /mnt/extra-addons)
docker compose exec web odoo \
  --addons-path=/mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons \
  --db_host=db --db_user=odoo --db_password=odoo \
  -d <db> -u <m> --stop-after-init --http-port 8099
```

## 8. Findings tracker

Severity scale §2.3. One table per module; append rows as found. Every module's
review closes with a `Guidelines read:` list (odoo-review §Report).

**Progress:** §8.11 `delivery_correo_argentino` complete (1 HIGH, 4 MEDIUM,
10 LOW/INFO; all fixed except MER-07 deferred). §8.1-§8.10 pending.

### 8.1 l10n_ar_fiscal_ws — Batch A

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.2 l10n_ar_fiscal_ws_fe — Batch A

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.3 l10n_ar_pos_afipws_fe — Batch A

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.4 l10n_ar_factura_qr — Batch B

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.5 l10n_ar_inflation_adjustment — Batch B

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.6 payment_sipago — Batch C

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.7 union_affiliation — Batch D

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.8 union_contribution — Batch D

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.9 union_benefit_request — Batch D

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.10 union_school_position — Batch D

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| — | | | | | | |

_Guidelines read:_

### 8.11 delivery_correo_argentino — Batch E

Reviewed commit: `odoo-argentina-envios` @ `d3cb11a` (branch `19.0`).

| ID | Sev | file:line | Finding | Fix | Section/judgement | Status |
|----|-----|-----------|---------|-----|-------------------|--------|
| SEC-01 | HIGH | `models/delivery_carrier.py:41-49` | Secret fields (`correo_argentino_micorreo_password`, `correo_argentino_paqar_apikey`) are plain `fields.Char` with no `groups`. `delivery.carrier` is `read`-granted to `sales_team.group_sale_salesman` and `base.group_partner_manager` (core ACL) -> any salesperson reads the API secrets via `read`/`search_read`/export. `password="True"` only masks the widget. | Add `groups=` (e.g. `base.group_system` or a carrier-manager group) to the secret fields; keep the UI mask. | odoo-security: Field-level access; odoo-guidelines `fields.md` | fixed |
| SEC-02 | MEDIUM | `models/correo_argentino_request.py:159-166` + `models/correo_argentino_micorreo.py:69-83` | Debug logging persists the request `data` to `ir.logging` (sudo, own cursor) via `_log_exchange`; `get_customer_id` sends the plaintext MiCorreo password in `data` -> secret/PII leak into logs (response bodies too). | Redact secret keys before logging, or skip `data` for credential calls. | odoo-security (tokens/secrets) + merits | fixed |
| SEC-03 | INFO | (no `security/`) | No ACL file needed: every model is inherited (`delivery.carrier`, `stock.picking`) with existing ACLs. The scanner warning is a false positive (its `access_checker` errored on the missing `security/`). | none | odoo-guidelines `security.md` | n/a |
| VIEW-01 | MEDIUM | `views/delivery_carrier_views.xml:8,90,96,102,108` | Fragile view inheritance: `//notebook/page[1]` (position) and `contains(@invisible, 'not debug_logging')` / `@icon` anchors on core attribute contents. Break silently on core reorder or wording change. | Anchor the page on `page[@name='pricing']`; for the duplicated `toggle_*` buttons anchor on a stable attribute and drop the `contains(@invisible, ...)` matches. | odoo-guidelines `xml.md`: Anchor view inheritance on names, never on position | fixed |
| MER-01 | MEDIUM | `models/correo_argentino_paqar.py:229` | `saleDate` = `fields.Datetime.now()` (UTC, naive) formatted with a literal `-03:00` offset -> timestamp is 3 h ahead of real Argentina time. | Format the company/carrier timezone with its real offset, or send UTC with `Z`. | merits (timezone) | fixed |
| MER-02 | LOW | `models/correo_argentino_paqar.py:200-202` | `total_grams // n * n != total`: remainder grams dropped when splitting weight across parcels. | Distribute the remainder over the parcels. | merits (rounding) | fixed |
| MER-03 | LOW | `models/correo_argentino_micorreo.py:41-59,102-112` | `_get_auth_headers` calls `_get_token()` on every request: a `/token` round-trip per call, no caching/refresh. | Cache the token on the adapter/session, refresh on 401. | `performance.md` | fixed |
| MER-04 | LOW | `models/correo_argentino_paqar.py:122-135` | `for item in response or []`: a single-label dict response iterates keys, then `item.get` raises `AttributeError`. | Normalize `[response] if isinstance(response, dict)`. | merits (robustness) | fixed |
| MER-05 | LOW | `models/correo_argentino_paqar.py:135` | Unguarded `base64.b64decode(raw)`: malformed label raises `binascii.Error`, not `CorreoArgentinoError`. | Wrap and re-raise as `CorreoArgentinoError`. | merits | fixed |
| MER-06 | LOW | `models/correo_argentino_request.py:193-202` | `_split_street` reads `street_name`/`street_number` (from `base_address_extended`, not a dependency): dead branch in a default install; full street sent as `streetName`. | Depend on `base_address_extended` or parse the street; keep the ROADMAP note. | `manifest.md` + merits | fixed |
| MER-07 | LOW | `models/correo_argentino_request.py:39` + adapters | `tracking_url` unset in both adapters -> `correo_argentino_get_tracking_link` always returns `False`; core `carrier_tracking_url` stays empty. | **Deferred:** needs a confirmed public tracking URL (none in either manual); fabricating one would mislead. Implement once confirmed. | merits | deferred |
| MER-08 | LOW | `models/delivery_carrier.py:320-328` | `_correo_argentino_get_close_locations` returns the raw agency payload (code TODO): not normalized to the website pickup-point structure, so the selector receives unexpected data. | Normalize the payload to the pickup-location shape. | merits | fixed |
| TST-01 | MEDIUM | `tests/test_delivery_correo_argentino.py` | No HTTP-layer tests (ROADMAP admits). Covers only factory/capabilities/fallback/wiring. | Mock `_session.request`: token, rate parse, payload builders, error mapping, labels, tracking, cancel, plus an assertion for SEC-01. | odoo-guidelines `tests.md`; plan §5.2 | fixed |
| MAN-01 | LOW | `__manifest__.py:9` | Author "Fundacion Mueve, Odoo Community Association (OCA)" while the module lives in a non-OCA repo. | Drop "OCA" or place the module under OCA governance. | `manifest.md` | fixed |
| QUAL-01 | LOW | `models/delivery_carrier.py:103,113` | Mirror fields reuse the core labels ("Environment" / "Debug logging"), so Odoo logs "Two fields ... have the same label" on install. | Renamed to "API environment" / "API debug logging". | merits (install warning) | fixed |
| QUAL-02 | LOW | `data/delivery_correo_argentino_data.xml:3` | `oca-checks-odoo-module` flags `xml-deprecated-data-node`: `<odoo><data noupdate="1">`. | Moved `noupdate="1"` onto `<odoo>` and dropped `<data>`. | oca-checks-odoo-module; odoo-guidelines `xml.md` | fixed |

**Fixes applied and verified (22:26, DB `test_correo`):**

- SEC-01: `base.group_system` on the password/agreement/apikey fields, plus a
  narrow read-only `sudo()` in `CorreoArgentinoRequest._get_secret` (the
  outbound call runs as the operating user; `sudo()` bypasses field `groups`,
  confirmed against `check_field_access_rights`). The security scanner's new
  LOW (`sudo() in _get_secret`) is the expected, justified hit.
- SEC-02: `_redact` masks `SECRET_KEYS` in both request and response debug
  logs; `_json_or_text` avoids logging a raw non-JSON body.
- VIEW-01: page anchored on `page[@name='pricing']`; the duplicated toggle
  buttons anchored on their own `invisible` condition (the match fails loudly
  on a core change).
- MER-01: `_correo_argentino_local_now()` converts UTC to
  `America/Argentina/Buenos_Aires` and emits a real `-03:00` offset.
- MER-02..06, MER-08: parcel-remainder distribution, instance token cache,
  list/dict label handling with `binascii` guard, `base_address_extended`
  dependency, and agency normalization to the pickup-location shape
  (`id/name/street/city/state/zip_code/country_code/latitude/longitude/opening_hours`).
- MAN-01, QUAL-01: author and field labels.
- Verification: `ruff check` + `ruff format --check` clean; fresh install and
  `-u` with `--test-enable` on `test_correo` -> **0 failed, 0 errors**; the
  duplicate-label warning is gone; `validate_module.py` passes.
- TST-01 (follow-up): added `tests/common.py` and the MiCorreo, PaqAr and
  security suites, all mocking `_session.request` / `log_xml`; the original
  smoke test now shares `CorreoArgentinoCommon`. Later the same day: the
  MiCorreo token 401 refresh (`_reset_auth`), the `i18n/es_AR.po` (73 terms)
  and the module docs. `-u --test-enable` on `test_correo` -> **0 failed,
  0 errors of 27 tests**; the module was committed in 7 review-scoped commits
  (`97c7aaf..76353fc`).
- Phase 0 (this repo): added `.pre-commit-config.yaml` (canonical MUEVE stack:
  pre-commit-hooks v6.0.0, OCA odoo-pre-commit-hooks v0.0.35, ruff v0.13.0,
  pylint-odoo v9.1.3, rstcheck v6.2.1, prettier + plugin-xml), plus
  `package.json`, `.prettierrc.json` and `.gitignore` entries. The OCA hooks
  found QUAL-02 (fixed). `pre-commit run` over all files -> **all hooks pass**.
  Line length stays at this repo's established 88; the 88 -> 120 unification is
  a cross-repo Phase 0 decision, not taken here.

**Verified correct (no action):** provider dispatch names match core/OCA
(`%s_rate_shipment` in `delivery`, `%s_send_shipping` / `%s_cancel_shipment` /
`%s_get_tracking_link` in `stock_delivery`, `%s_tracking_state_update` in
`delivery_state`, `_%s_get_close_locations` in `delivery`); the `delivery_state`
map uses `canceled_shipment` (one `l`), fixing the 16.0 bug; no `sudo`, raw SQL,
routes, `eval`/`pickle`, `open()`, mutable defaults or domain injection; HTTP
timeouts set; translation placeholders are named and literal (good); manifest
deps are direct, version/license correct, `external_dependencies` declared;
`validate_module.py` passes (only the auto-generated `README.rst` warning).

_Guidelines read:_ `manifest.md`, `python.md`, `orm.md`, `fields.md`, `xml.md`,
`security.md`, `performance.md`, `tests.md`, `comments.md`, `stable.md`, and
the official `~/.agents/skills/odoo-security/SKILL.md` full sweep table.

---

*Inventory and repo config data in §1/§3 verified against the working tree on
2026-09-23 (`19.0-dev`). Re-verify counts before reporting if submodules have
moved.*
