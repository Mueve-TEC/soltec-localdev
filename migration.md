# Migration Plan: Bring 16.0 changes into 19.0 — `odoo-union` repository

> **Scope:** Exhaustive analysis of the differences between branches `16.0`, `18.0` and `19.0` of the `odoo-union` repository, and an actionable plan to bring the features/fixes from `16.0` into `19.0` while keeping the Odoo 19 API.

---

## 1. Repository Summary

**Remote:** `git@github.com:Mueve-TEC/odoo-union.git`
**Current branch:** `16.0` (clean working tree, up to date with `origin/16.0`).

### Branches

| Branch | Type | HEAD SHA | State |
|---|---|---|---|
| `16.0` | local + remote | `3e96055` | Most evolved; all features/fixes live here |
| `18.0` | local + remote | `d1392b8` | **WIP/incomplete** — partial migration of 16.0 features to Odoo 17/18 API |
| `19.0` | local + remote | `3387b86` | Early migration; has tree->list, attrs->invisible, but missing many 16.0 features AND several deprecation fixes |
| `main` | local + remote | `7084a2f` | Merge sink (PRs from 16.0) |
| `16.0-develop` | remote only | — | Dev branch (not analyzed) |

### Branch topology (critical)

- `merge-base(16.0, 18.0)` = `merge-base(16.0, 19.0)` = **`97d0189`** ("sindicato es la vista por defecto al logear"). All three diverge here.
- `merge-base(18.0, 19.0)` = **`93d26f6`** ("creacion de afiliados desde la importacion de aportes"). So **18.0 and 19.0 share the same Odoo 17/18 migration base** (`5e9ce3d -> 93d26f6`: tree->list, attrs->invisible, users->user_ids, mobile removal, `_message_get_suggested_recipients`). 19.0 adds only `3387b86` (website link) on top; 18.0 adds 25 commits on top (the WIP migration of 16.0 features + more deprecation fixes).

### Modules (4)

All Odoo "Sindicato" (union) modules by Mueve.

| Module | Manifest version (16.0 / 19.0) | Depends on |
|---|---|---|
| `union_affiliation` | `16.0.1.2.0` / `19.0.0.0.0` | base, mail |
| `union_benefit_request` | `16.0.1.3.0` / `19.0.0.0.0` | base, survey, mail, union_affiliation |
| `union_contribution` | `16.0.1.2.0` / `19.0.0.0.0` | base, union_affiliation (has `post_init_hook`) |
| `union_school_position` | `16.0.1.2.0` / `19.0.0.0.0` | base, union_affiliation |

### Scale of divergence

`git diff --stat origin/19.0 origin/16.0` -> **101 files changed, +3541 / -2258**.

---

## 2. 18.0 Changes Analysis (25 commits on 18.0 not in 19.0)

Each row: the 18.0 commit, its nature, and whether the **change content** (not the SHA) is present in 16.0 and 19.0. Ordered oldest->newest.

| SHA | Message (abridged) | Nature | In 16.0? | In 19.0? | Action for 19.0 |
|---|---|---|---|---|---|
| `656ac09` | feat: cambio de version 18 | version bump | NO | NO (19.0 already `19.0.0.0.0`) | Skip (irrelevant) |
| `f3e2d0a` | fix: rollback "user_ids" -> "users" | API migration | YES (16.0 uses `users`) | **NO - 19.0 uses `user_ids`** | **SKIP / do NOT port** - conflicts with 19.0 direction (`511804e`). Keep 19.0's `user_ids`. |
| `1a0b96f` | `_message_get_suggested_recipients()` odoo 18 (affiliate) | API migration | NO (old sig) | YES (already done via `62aa134`) | Skip (already in 19.0) |
| `7d762cb` | traducciones afiliados v18 | i18n | NO | NO | Regenerate i18n at end |
| `d052ee9` | warnings deprecacion creacion (affiliate/period) | deprecation (create multi) | NO | NO | **Port** |
| `07a75cb` | traduccion registro de cambios afiliados | i18n + log | partial | NO | Port (i18n regen) |
| `1c8b534` | eliminacion archivos xml comentados | cleanup | NO (16.0 keeps them) | NO (19.0 still has dead `demo.xml`/`templates.xml`/`views.xml`) | **Port** (cleanup dead files) |
| `125c579` | refact act_window -> record (mail actions) | XML refactor | NO | NO | **Port** |
| `eeb5c45` | traduccion accion enviar email | i18n | NO | NO | i18n regen |
| `5bb3a3a` | deprecacion name_get (7 models) | deprecation | NO (16.0 keeps name_get) | **NO - 19.0 still has name_get** | **CRITICAL - Port** |
| `f3be61e` | name_get -> display_name (position/char/type) | deprecation | NO | NO | **CRITICAL - Port** |
| `e38ca4c` | vista tree deprecada (survey_user) | deprecation (tree->list) | NO | partial (verify) | Port/verify |
| `d729348` | traducciones solicitudes | i18n | NO | NO | i18n regen |
| `a3a57e8` | chatter vista form solicitudes | view fix | NO | NO | **Port** |
| `65559c2` | `_message_get_suggested_recipients()` odoo 18 (benefit_request) | API migration | NO | NO | **Port** |
| `cc2cbb1` | feat: restricciones al crear cargos | feature | YES (16.0 has it) | NO | **Port** |
| `f92e451` | fix: typo (benefit_request) | fix | NO | NO | Port |
| `ab8f0df` | api.model -> api.model_create_multi (benefit_request create) | API migration | YES (16.0 already uses `api.model_create_multi`) | **NO - 19.0 uses `@api.model`** | **CRITICAL - Port** |
| `bb81823` | WIP: tracking changes refact (benefit_request) | refactor | partial | NO | Port (review) |
| `a468402` | traducciones solicitudes | i18n | NO | NO | i18n regen |
| `b13c2ea` | fix: vista form de solicitudes | view fix | NO | NO | **Port** |
| `b68761e` | feat: work_id, delegation_id, seniority_years + uid validation | feature | YES | **NO** | **CRITICAL - Port** |
| `5bb98df` | eliminacion estado "new" solicitudes (vista) | fix | YES (16.0 `c6ac0a1`) | NO | **Port** |
| `d1392b8` | wip: migracion de cambios de en version 16 | **big feature port** | YES (ports 16.0 features) | **NO** | **CRITICAL - Port, but BROKEN (see section 5/6)** |

### Summary of the 18.0 analysis

- 18.0 is a **partial, incomplete (WIP) port** of 16.0 features onto the Odoo 17/18 API.
- It also contains **deprecation fixes that 19.0 is missing** (most importantly: `name_get` -> `_compute_display_name`, and `@api.model create` -> `@api.model_create_multi`).
- One 18.0 commit (`f3e2d0a`) **diverges from 19.0** (user_ids vs users) and must NOT be ported.
- The big WIP `d1392b8` references config fields (`create_user_from_position`, `create_user_from_request`) whose model files **do not exist in 18.0** - so that WIP is functionally broken on 18.0 and needs the 16.0 config files to be added when porting to 19.0.

---

## 3. 16.0 Features/Fixes Missing in 19.0 (the KEY LIST)

53 commits on 16.0 not in 19.0 (`origin/19.0..origin/16.0`). Grouped by module/feature. For each, we note whether 18.0 already ported it (useful as a reference) and the affected files.

### 3.1 `union_affiliation` - Affiliate model

| 16.0 commit | Change | Files | In 18.0? |
|---|---|---|---|
| `b68761e` (also on 18.0) | Add `work_id` (Char), `delegation_id` (Many2one union.workplace), `seniority_years` (Integer compute `_compute_seniority_years`); harden `uid` validation (only digits, cannot start with 0) | `union_affiliation/models/affiliate.py`, `views/affiliate_views.xml` | YES |
| `bfa99dd` | **Refactor: remove `workplace_ids` (Many2many) + `_check_main_workplace` constraint + `_auto_assign_workplace_parents`; add `delegation_id`** | `models/affiliate.py` (-66), `models/workplace.py` (-35), `views/affiliate_views.xml` (-34), `wizards/workplace_delete_wizard.py` | YES (via `d1392b8`) |
| `1e2dba3` | Refactor: "Legajo" -> "ID de afiliado/a"; new `legajo` field | `models/affiliate.py`, `views/affiliate_views.xml`, + i18n across modules | partial (WIP) |
| `72bb747` | **fix: SQL constraints in affiliations** - adds `_sql_constraints` block (`uid_unique`, `unique_affiliation_number`); large refactor of `affiliate.py` (+442/-) | `models/affiliate.py`, `models/affiliate_type.py`, `models/affiliation_period.py`, `models/workplace.py` | **NO - 16.0 only** |
| `3af9e8c` | Computed `seniority_years` (antiguedad) - same feature as in `b68761e` | `models/affiliate.py`, `views/affiliate_views.xml` | YES |
| `8712861` | **feat: agrupar por fecha de registro en afiliados** - new model `school_position.registration.date` | `union_school_position/models/position_registration_date.py`, `models/__init__.py`, `models/affiliate.py`, `security/ir.model.access.csv`, `views/affiliate_views.xml` | **NO - 16.0 only** |
| `09050db` | **feat: creacion de afiliados desde solicitudes + ID validation** - adds `create_user_from_request` config + import-create-affiliate logic in benefit_request | `union_benefit_request/models/affiliation_configuration.py` (new), `views/affiliation_configuration_view.xml` (new), `models/benefit_request.py`, `union_contribution/models/contribution.py`, `union_school_position/models/position.py` | partial (logic in WIP, **config file missing**) |
| misc fixes | `f723eeb` (ID label warning), `91c835e` (remove tipos de cargo field), `0a9f4d0` (group buttons), `8712861` group-by registration date, `f38b0eb`/`bc3ab7b`/`a339c64` (i18n/typos), `c717f59` i18n | various | partial |

### 3.2 `union_school_position` - Cargos

| 16.0 commit | Change | Files | In 18.0? |
|---|---|---|---|
| `b8c74cd` | **feat: "Destacado" (featured) field** in position + actions `action_set_featured`/`action_unset_featured` + list decoration + filters | `models/position.py`, `views/position_views.xml` | YES (via WIP) |
| `bca2274` | **feat: bool "Tiene cargo destacado" (`has_featured_position`)** computed on affiliate | `union_school_position/models/affiliate.py`, `views/affiliate_views.xml` | **NO - 16.0 only** |
| `10fc6de` | **feat: nuevas agrupaciones y filtros para cargos** - `workplace_level1/2/3` computed fields + group-by filters | `models/position.py`, `views/position_views.xml`, i18n | YES (via WIP) |
| `9bae91c` | **feat: campo `sector` en cargos** | `models/position.py`, `views/position_views.xml` | **NO - 16.0 only** |
| `702cf2d` | feat: agrupar por "Lugar de trabajo" en cargos | `views/position_views.xml`, i18n | partial |
| `9b8e5e7` | **feat: creacion de afiliados desde importacion de cargos** - `create_user_from_position` config + import-create-affiliate in position.py | `models/affiliation_configuration.py` (new), `views/affiliation_configuration_view.xml` (new), `models/position.py`, `models/__init__.py` | partial (logic in WIP, **config file missing**) |
| `1e1e9bb` | fix: campos obligatorios en creacion de cargos | `models/position.py`, `views/position_views.xml` | partial (WIP made some optional - verify) |
| `5d5d29e` | fix: typo en nombre de campo position | `models/position.py` | - |
| `8ea61cb`, `f1a51b4`, `de79b70` | i18n / group button order / type name display | various | partial |

### 3.3 `union_contribution` - Aportes / Inconsistencias

| 16.0 commit | Change | Files | In 18.0? |
|---|---|---|---|
| `1937455` | **refactor: rename `name` -> `description` in `contribution.affiliate_contribution_code`** (`_rec_name`->description, `_compute_display_name`) | `models/contribution_code.py`, `views/contribution_code_views.xml`, `views/contribution_views.xml`, i18n | YES (via WIP) |
| `ed3abbc` | **feat: codigos de aporte + multiples tipos de relacion laboral en busqueda de inconsistencias** - `affiliate_type_ids` (Many2many), `contribution_code_ids` (Many2many); replaces SQL-function calls with **inline SQL** | `models/query.py`, `views/query_views.xml` | YES (via WIP) |
| `e6f0641` | **feat: campos de estado de afiliacion y tipo de relacion laboral en la inconsistencia** - `affiliate_state`, `affiliate_type_id`, `quote` (related, stored) on `inconsistencies.result` | `models/query.py`, `models/result.py`, `views/result_views.xml` | YES (via WIP) |
| `b176266` | **feat: acciones desde inconsistencias** - `action_set_quote`/`action_unset_quote` + `ChangeStateWizard` model + server actions + access rule | `models/result.py`, `security/ir.model.access.csv`, `views/result_views.xml` | YES (via WIP) |
| `b25aa4f`, `c794a86` | feat: botones/grupos para agrupar resultados de inconsistencias | `views/result_views.xml`, `views/inconsistencies_menu.xml` | YES (via WIP) |
| `fcd01d1` | feat: agrupamiento por codigo, afiliado y fecha en aportes | `views/contribution_views.xml` | partial |
| `96d6d68`, `c927064`, `f48f6fd`, `1e2154e` | fixes in inconsistencias (actions, breadcrumb, i18n, rename) | various | partial |
| `f39bd30` | fix: permiso de cambio de estado de afiliacion en inconsistencias | security | partial |

### 3.4 `union_benefit_request` - Solicitudes

| 16.0 commit | Change | Files | In 18.0? |
|---|---|---|---|
| `09050db` (shared) | creacion de afiliados desde solicitudes (import_name/import_vat/import_personal_id + auto-create) | `models/benefit_request.py`, `models/affiliation_configuration.py` (new), `views/affiliation_configuration_view.xml` (new) | partial (logic in WIP, **config missing**) |
| `c6ac0a1`, `5bb98df` | eliminacion estado "new" de solicitudes en vistas | `views/benefit_request_views.xml` | YES (`5bb98df`) |
| `acf6d85` | feat: agregado estado a la vista tree de solicitudes | `views/benefit_request_views.xml` | NO |
| `2eb4911` | fix: notebook de solicitudes en vista form de afiliados | `views/affiliate_views.xml` | NO |
| `7a4f9dc` | fix: id de grupos de permisos | security | partial |
| `22aa598` | fix: "ID de afiliado/a" en vez de "Legajo" en cargos | i18n/position | partial |
| `6738cb1`, `5a48bfb`, `2a9d95a`, `d852e8e` | ruff fixes / remove unused imports / commented code | various | NO (cleanup) |
| `c7effb9`, `3e96055`, `2b2678f` | ruff format/check | various | NO (tooling) |

### 3.5 Repo-level / tooling (16.0 not in 19.0)

- `pyproject.toml` present in 16.0/18.0, **missing in 19.0** (ruff config).
- `a7ed849` "update de version" (16.0 version bumps).

---

## 4. File-Level Diff Summary: 16.0 vs 19.0

`git diff --stat origin/19.0 origin/16.0` - **101 files, +3541/-2258**. Most significant:

### Python model files (highest-impact)

- `union_affiliation/models/affiliate.py` - **371 lines** (work_id, delegation_id, seniority_years, `_sql_constraints`, removal of `workplace_ids` logic, uid validation, partner unlink)
- `union_school_position/models/position.py` - **216 lines** (featured, workplace_level1/2/3, affiliate_state, sector, import_name/vat, `api.model_create_multi` create, `_compute_display_name` replacing `name_get`)
- `union_contribution/models/query.py` - **153 lines** (`affiliate_type_ids`, `contribution_code_ids`, inline SQL replacing `calculateInconsistencies`/`calcInconsByType`)
- `union_contribution/models/result.py` - **147 lines** (`affiliate_state`, `quote`, `affiliate_type_id` related fields, `action_set_quote`/`unset_quote`, `ChangeStateWizard`)
- `union_affiliation/models/workplace.py` - **163 lines** (removal of custom unlink + parent_path `unaccent=False`)
- `union_contribution/__init__.py` - **107 lines** (`post_init_hook` signature `cr,registry`->`env`; 19.0 already has the `env` signature, so this is mostly identical - 19.0 already migrated this)
- `union_benefit_request/models/benefit_request.py` - **206 lines** (import_name/vat/personal_id, `api.model_create_multi` create, create-affiliate-from-import, tracking refactor, `_compute_display_name` replacing `name_get`)
- `union_benefit_request/models/survey_user.py` - 73 lines

### XML views (high-impact)

- `union_affiliation/views/affiliate_views.xml` (+155) - delegation_id, seniority_years, work_id, removal of "Lugares de trabajo" page + filters
- `union_contribution/views/result_views.xml` (+93) - new fields, search view, ChangeStateWizard form, server actions
- `union_benefit_request/views/benefit_request_views.xml` (+124) - state column, chatter, estado "new" removal
- `union_school_position/views/position_views.xml` (+61) - featured, group-bys, filters
- `union_school_position/views/menu.xml` (+42), `union_contribution/views/menu.xml` (+35), `union_benefit_request/views/menu.xml` (+54)

### New files in 16.0 absent from 19.0

- `union_school_position/models/affiliation_configuration.py` (create_user_from_position)
- `union_benefit_request/models/affiliation_configuration.py` (create_user_from_request)
- `union_school_position/views/affiliation_configuration_view.xml` (x2)
- `union_benefit_request/views/affiliation_configuration_view.xml`
- `union_school_position/models/position_registration_date.py`
- `pyproject.toml`

### Files present in 19.0 but as dead/commented boilerplate (should be removed)

- `*/demo/demo.xml` (all 4 modules - commented-out scaffold, still referenced by 19.0 manifests)
- `*/views/templates.xml`, `*/views/views.xml` (orphaned, not in manifest but on disk)

### i18n

All 4 `es_AR.po` files differ heavily (16.0 is the most complete). Recommend regenerating rather than merging.

---

## 5. Upgrade Plan (ordered, actionable, with risk)

**Strategic recommendation:** Use a **hybrid port**. Because 18.0 and 19.0 share the same migration base (`93d26f6`), the lowest-friction path is to (A) cherry-pick the non-conflicting 18.0 commits onto 19.0 (they already speak Odoo 17/18 API), then (B) fill the gaps from 16.0 directly (the 16.0-only features + the config files the 18.0 WIP forgot).

### Phase 0 - Preparation

- **0.1** Create a working branch from `origin/19.0`: `git checkout -b 19.0-upgrade origin/19.0`.
- **0.2** Set up an Odoo 19 dev environment to validate after each phase (many changes can't be statically verified).
- **0.3** Decide i18n strategy up front: plan to **regenerate** `es_AR.po` at the end (do not waste time merging PO files by hand).

### Phase 1 - Port 18.0 deprecation fixes (low risk, high value)

These fix Odoo 18/19 breaking issues that 19.0 still has. Cherry-pick in this order; resolve trivial conflicts.

1. **`5bb3a3a` + `f3be61e`** - Replace all `name_get` with `_compute_display_name`.
   - *Why critical:* 19.0 still has `def name_get` in `benefit_request.py:305`, `position.py:94`, `contribution.py:64`, `contribution_code.py`, `affiliate_state.py`, `school_benefit.py`. `name_get` is removed in Odoo 18+. **19.0 will break without this.**
   - Risk: **Low-Medium**. Mechanical replacement. Verify each model has a proper `display_name` compute.
2. **`ab8f0df` + `d052ee9`** - `@api.model def create(self, vals)` -> `@api.model_create_multi def create(self, vals_list)` for `benefit_request.py` and `affiliation_period.py`/`affiliate.py`.
   - *Why critical:* 19.0 `benefit_request.py:285` and `position.py:101` still use the single-val `@api.model create`. Odoo 18+ requires multi.
   - Risk: **Medium** (must adapt loop logic `for vals in vals_list`).
3. **`65559c2`** - `_message_get_suggested_recipients` override for `benefit_request.py` (Odoo 18 signature).
   - Risk: **Low** (affiliate.py already done in 19.0; only benefit_request needs it).
4. **`125c579`** - refactor `act_window` mail actions to `record` structure in `affiliate_views.xml` + `benefit_request_views.xml`.
   - Risk: **Low**.
5. **`a3a57e8`, `b13c2ea`, `e38ca4c`, `5bb98df`** - view fixes (chatter, form de solicitudes, tree->list survey_user, remove "new" state).
   - Risk: **Low**.
6. **`1c8b534`** - **Cleanup dead XML files**: delete `demo/demo.xml`, `views/templates.xml`, `views/views.xml` from all 4 modules AND remove their references from manifests (19.0 manifests still list `demo/demo.xml`).
   - Risk: **Low** (dead/commented content). Confirm no module references them after removal.
7. **`cc2cbb1`** - restricciones al crear cargos (position.py constraints).
   - Risk: **Low**.
8. **SKIP `f3e2d0a`** (user_ids->users rollback) - **explicitly do NOT port**; 19.0 correctly uses `user_ids` (from `511804e`). Keep 19.0's direction.
9. **SKIP `656ac09`** (version bump to 18) - irrelevant; 19.0 already at `19.0.0.0.0`.

### Phase 2 - Port 18.0 feature commits (medium risk)

10. **`b68761e`** - Add `work_id`, `delegation_id`, `seniority_years` + uid isdigit/leading-zero validation to `affiliate.py` + view fields.
    - Risk: **Low-Medium**. Clean addition. (Same content already in 16.0; 18.0 version is API-correct.)
11. **`d1392b8`** (the big WIP) - port the consolidated feature migration:
    - Remove `workplace_ids` / `_check_main_workplace` / `_auto_assign_workplace_parents` from `affiliate.py`; simplify `create`/`write`; `unlink` partner; remove "Lugares de trabajo" page + filter from `affiliate_views.xml`; update `workplace_delete_wizard.py` to use `delegation_id`.
    - `benefit_request.py`: import_name/vat/personal_id fields + create-affiliate-from-import logic.
    - `position.py`: featured, workplace_level1/2/3, affiliate_state, import_name/vat, `api.model_create_multi` create, `action_set_featured`.
    - `contribution.py`: uid validation in import.
    - `contribution_code.py`: `name`->`description`, `_rec_name`->`description`.
    - `query.py`: `affiliate_type_ids`/`contribution_code_ids` + inline SQL.
    - `result.py`: `affiliate_state`/`quote`/`affiliate_type_id` + `action_set_quote`/`unset_quote` + `ChangeStateWizard`.
    - Views + access CSV + wizard.
    - **Risk: HIGH.** This is a large WIP. Expect conflicts in i18n (skip, regenerate) and possibly security XML (keep 19.0's `user_ids`). **Must be ported together with Phase 3.1** because it references `conf.create_user_from_position`/`conf.create_user_from_request` which don't exist yet (see below).

### Phase 3 - Fill gaps from 16.0 (18.0 WIP was incomplete)

12. **3.1 (CRITICAL bug-fix for Phase 2):** Add the missing config model files + views from 16.0, otherwise the WIP's import-create-affiliate code crashes with `AttributeError`:
    - `union_benefit_request/models/affiliation_configuration.py` (adds `create_user_from_request` Boolean, `_inherit='affiliation.affiliation_configuration'`)
    - `union_school_position/models/affiliation_configuration.py` (adds `create_user_from_position`)
    - `union_benefit_request/views/affiliation_configuration_view.xml` + `union_school_position/views/affiliation_configuration_view.xml` (xpath inherit to add the fields)
    - Register in `models/__init__.py` and add view files to `__manifest__.py` `data` lists of both modules.
    - Risk: **Medium** (must verify the base `affiliation.affiliation_configuration` form view id `union_affiliation.union_affiliation_affiliation_configuration_form` exists in 19.0 - it does).
13. **`72bb747`** - Add `_sql_constraints` (`uid_unique`, `unique_affiliation_number`) to `affiliate.py` + refactor of affiliate_type/period/workplace.
    - Risk: **Medium-High** (442-line refactor; conflicts likely with Phase 2's affiliate.py changes). Port carefully, possibly re-apply by hand on top of the Phase 2 result.
14. **`9bae91c`** - Add `sector` field to `position.py` + view. (16.0-only, not in 18.0.)
    - Risk: **Low**.
15. **`bca2274`** - Add `has_featured_position` computed bool to `union_school_position/models/affiliate.py` + view. (16.0-only.)
    - Risk: **Low**.
16. **`8712861`** - Add `school_position.registration.date` model + group-by registration date in affiliates. (16.0-only.)
    - Files: new `position_registration_date.py`, `models/__init__.py`, `affiliate.py`, `security/ir.model.access.csv`, `views/affiliate_views.xml`.
    - Risk: **Low-Medium** (new model + access row).
17. **`1e2dba3`** + **`22aa598`** - "Legajo" -> "ID de afiliado/a" labeling; new `legajo` field. (i18n-heavy; fold into i18n regen.)
    - Risk: **Low**.
18. **`acf6d85`, `2eb4911`, `702cf2d`, `fcd01d1`, `b25aa4f`, `c794a86`, `10fc6de`** - remaining group-by/filter/view enhancements for cargos, aportes, solicitudes. Many are already in the WIP; port only what's missing after Phase 2.
    - Risk: **Low** (view-only, mostly).
19. **`pyproject.toml`** - copy from 16.0/18.0 (ruff config). Optional but recommended.
    - Risk: **None**.

### Phase 4 - i18n & version

20. **Regenerate** all 4 `es_AR.po` files from the updated Python/XML sources (`odoo -d <db> --i18n-export=...` or `--modules`). Do not merge by hand.
21. **Bump manifest versions** to `19.0.1.0.0` (or per-module `19.0.1.x.y`) for all 4 modules to reflect the feature port.
22. Run **ruff** (`ruff check` + `ruff format`) to match 16.0's `3e96055`/`c7effb9` tooling state.

### Phase 5 - Validation

23. Install all 4 modules on a fresh Odoo 19 DB; verify `post_init_hook` (SQL functions) still runs (19.0 already has `env`-based signature - OK).
24. Test import flows (cargos, solicitudes, aportes) - these exercise the new create-affiliate-from-import + config flags.
25. Test inconsistencias query + ChangeStateWizard + set/unset quote server actions.
26. Verify chatter / `_message_get_suggested_recipients` on both affiliate and benefit_request.

**Recommended order rationale:** Phase 1 first (fixes Odoo 19 breaking issues with minimal conflict), then Phase 2 (features, built on same base), then Phase 3 (fill 16.0-only gaps + the WIP's missing config), then i18n/version last.

---

## 6. Version-Specific Caveats for Porting 16.0 -> 19.0

1. **`name_get()` is removed in Odoo 18+.** 19.0 still has it in 5 models (`benefit_request.py:305`, `position.py:94`, `contribution.py:64`, `contribution_code.py`, `affiliate_state.py`, `school_benefit.py`). Every `name_get` must become `_compute_display_name`. 18.0 already did this (`5bb3a3a`, `f3be61e`) - reuse that.

2. **`@api.model def create(self, vals)` (single-val) is invalid in Odoo 18+.** Must be `@api.model_create_multi def create(self, vals_list)` and loop. 19.0 `benefit_request.py:285` and `position.py:101` still use the old form. 18.0's `ab8f0df` shows the correct pattern.

3. **`<tree>` -> `<list>`** view tag (Odoo 18+). 19.0 already did this (`06fcce7`, `994ba69`). 16.0 uses `<tree>` - so when porting 16.0 view snippets, **rewrite `<tree>` to `<list>`**. 18.0 versions are already converted - prefer porting view changes from 18.0 where possible.

4. **`attrs="{'invisible': [...]}"` -> `invisible="..."`** (Odoo 17+). 19.0 already done (`8c99f49`). 16.0 uses `attrs=` - convert when porting 16.0 XML.

5. **`res.groups` field: `users` vs `user_ids`.** 19.0 uses `user_ids` (`511804e`); 18.0 rolled back to `users` (`f3e2d0a`). **Keep 19.0's `user_ids`** - do NOT accept 18.0's rollback. Any 16.0/18.0 security XML ported must be rewritten to `user_ids`.

6. **`_post_init_hook` signature.** 16.0 uses `(cr, registry)`; 18.0/19.0 use `(env)`. 19.0 already migrated - do not regress. The SQL functions (`mapState`, `translateState`, `calculateInconsistencies`, `calcInconsByType`) are still defined in 19.0's `__init__.py`; the 16.0/18.0 `query.py` inline-SQL approach still **calls `translateState()`**, so keep that function. `calculateInconsistencies`/`calcInconsByType` become unused after porting inline SQL - optional to remove.

7. **Stored related fields require schema columns.** The WIP/16.0 adds `affiliate_state`, `affiliate_type_id`, `quote` as `related=..., store=True` on `inconsistencies.result`. The ORM will add these columns on module upgrade - no manual migration script needed, but ensure the module upgrades cleanly. Also `position.affiliate_state` (stored related) and `position.workplace_level1/2/3` (stored compute) - same.

8. **`_sql_constraints`** added by `72bb747` (`uid_unique`, `unique_affiliation_number`) - these create DB constraints on upgrade. If duplicate data exists, upgrade will fail; consider a pre-migration cleanup or catch the error. Coordinate with any data migration.

9. **The 18.0 WIP `d1392b8` is functionally broken on its own** - it references `conf.create_user_from_position`/`conf.create_user_from_request` but the 18.0 branch never added the `affiliation_configuration.py` model files (verified: `git ls-tree origin/18.0 -- union_school_position/models/affiliation_configuration.py` -> 0). **You MUST add these config files (from 16.0) in the same PR/phase**, or imports that hit the auto-create branch will raise `AttributeError`.

10. **`unaccent=False` on `parent_path`** (workplace.py, from WIP) - verify Odoo 19 supports this index parameter; if not, drop it.

11. **Delegated inheritance `unlink`**: the WIP changes `affiliate.unlink()` to also call `self.partner_id.unlink()`. In Odoo 19 with `_inherits`, parent cleanup is normally ORM-handled; manually unlinking the partner may double-delete or raise. **Verify this behaves correctly on Odoo 19** (the WIP even leaves a `# TODO` comment about it).

12. **i18n `.po` files** differ massively across all branches. Do not attempt to merge; regenerate from final sources.

13. **`position_type.py` display_name**: 19.0 removed 16.0's `name_get` but added **no replacement** (`_compute_display_name` absent). 18.0 has a proper implementation. Port 18.0's version so the type's display name is correct.

14. **Dead scaffold files**: 19.0 still ships commented `demo/demo.xml` (referenced in manifests), `templates.xml`, `views.xml`. Remove them and clean manifest `demo` lists - 18.0 already did this (`1c8b534`).

---

## 7. Quick-Reference: Key SHAs

| Reference | SHA | Notes |
|---|---|---|
| 16.0 HEAD | `3e96055` | ruff format |
| 18.0 HEAD | `d1392b8` | WIP big feature port |
| 19.0 HEAD | `3387b86` | website link only on top of migration base |
| Common ancestor (all three) | `97d0189` | "sindicato es la vista por defecto al logear" |
| Shared migration base (18.0 & 19.0) | `93d26f6` | "creacion de afiliados desde la importacion de aportes" |
| Biggest single port commit (18.0 WIP) | `d1392b8` | 598 insertions, 18 files - **broken without Phase 3.1** |
| 16.0 affiliate SQL constraints | `72bb747` | 442-line refactor, 16.0-only |
| 16.0-only features needing direct port | `9bae91c`, `bca2274`, `8712861`, `09050db`, `9b8e5e7` | sector, has_featured_position, registration_date, config files |

---

## 8. Do-Not-Port List

| Commit | Branch | Reason |
|---|---|---|
| `f3e2d0a` | 18.0 | Rolls back `user_ids` -> `users`; 19.0 correctly uses `user_ids`. Porting would regress Odoo 17+ API. |
| `656ac09` | 18.0 | Version bump to `18.0.x`; 19.0 is already at `19.0.0.0.0`. |
| `1a0b96f` | 18.0 | `_message_get_suggested_recipients` for affiliate - already present in 19.0 via `62aa134`. |
