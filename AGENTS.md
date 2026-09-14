# Odoo LocalDev Environment Guide — soltec-localdev-odoo19 (19.0)

> Reference for AI agents (and humans) working in this repository.
> Living document — update it when the environment changes.
> All paths/commands below were verified against the working tree at
> `/home/ezeluduena/proyectos/odoo-unc/facturacion/soltec-localdev19-factura`
> on branch `19.0`.

> **When passing this file to an agent**, instruct it to:
>
> 1. Read this document in full before doing anything else.
> 2. This is a **local development environment**: module sources live in
>    `submodules/` as **tracked git submodules**. **Edit modules only in
>    `submodules/`**, then run `bash copy_addons.sh` (or `make sync`) to
>    populate the addons path, then launch/restart the container. `custom-addons/`
>    is generated — never edit it in place. Commit module changes inside the
>    submodule first, then bump the gitlink in this supermodule.
> 3. Use `-d <db>` explicitly on every Odoo CLI invocation (no db-filter).
> 4. Only commit when explicitly asked; commit in this repo's style
>    (`[CHORE]` / `[DOC]` / `[REFACT]` / `[FIX]`).
> 5. Run lint/tests when discoverable (see "Linting" and "Testing").
> 6. This file is the opencode project context (auto-loaded as `AGENTS.md`).
> 7. **Before starting any task**, scan the [Skills](#skills) section and load
>    the matching skill(s) with the `skill` tool.

## Overview

A **Docker-based local development harness** for **Odoo 19 Community**, used
to develop and test the SolTec / SOL3 Argentine localization modules
(`l10n_ar_*`, `eh_*`, payment, reports, etc.).

What it is / is not:

- It does **not** contain the Odoo server source — it rides on the SOL3 base
  image `muevetec/soltec-odoo:19.0.6-dev` (`FROM` in `Dockerfile`; Odoo Server
  19.0-20260817).
- The base image **bakes in ~123 modules** at `/mnt/extra-addons` (the
  read-only production baseline). The editable layer is **`custom-addons/`**
  (host `./custom-addons`, bind-mounted at `/mnt/custom-addons`), which is
  **generated from `submodules/`** before launching the container.
- The **edit flow** is: edit module sources in `submodules/`, run
  `copy_addons.sh` (or `make sync`) to copy them into `custom-addons/`, then
  launch/restart the container. `submodules/` holds **tracked git submodules**
  (each repo is pinned as a gitlink; initialise them with `make submodules-init`
  after a fresh clone). `custom-addons/` is a gitignored, generated addons path.
- It is **not** an OpenUpgrade project and has **no CI**. Tests/pre-commit
  only run on demand, locally.

Git identity:

- Remote: `git@github.com:Mueve-TEC/soltec-localdev.git`
- Current branch: `19.0` (per-Odoo-version branches are the norm).
- Commit style in this repo: bracketed prefixes
  (`[CHORE]`, `[DOC]`, `[REFACT]`, `[FIX]`, …).

## Skills

Skills provide specialized instructions/workflows for specific tasks. They are
**not** auto-loaded — the agent must invoke them explicitly with the `skill`
tool, and they are additive (load more than one if a task crosses domains).

### Which skill to load when

| If the task is…                                              | Load                   |
| ------------------------------------------------------------ | ---------------------- |
| Write / review Python models, XML views, wizards, manifests  | `odoo-development`     |
| Migrate module code between Odoo versions (16/17/18 → 19)    | `odoo-upgrade`         |
| Write or run `tests/` (TransactionCase, HttpCase, tours)     | `odoo-automated-tests` |
| Review a module, a Python file, or an XML view               | `odoo-code-review`     |
| Audit access rules, sudo, SQL injection, controllers         | `odoo-security`        |
| OCA conventions, scaffold a new OCA-style module             | `odoo-oca-developer`   |
| Generate test skeletons, mock data, coverage analysis        | `odoo-test`            |
| Discover / install an agent skill you don't have             | `find-skills`          |

Other skills available in the environment (general purpose): `customize-opencode`
(editing opencode's own config), `caveman` (compressed output), `grill-me` /
`grill-with-docs` (design interviews). Use `find-skills` to install more.

```python
# Pseudocode the agent should follow at task start
if task involves <one of the rows above>:
    invoke skill("<name>")  # via the skill tool
```

## Repository Layout

```
soltec-localdev-odoo19/
├── Dockerfile              # FROM muevetec/soltec-odoo:19.0.6-dev (SOL3, Odoo 19)
├── docker-compose.yml      # web (Odoo) + db (postgres:14) + pgadmin
├── Makefile                # wrappers: build/up/down/install/upgrade/test/lint…
├── scripts/test-runner.sh  # filters Odoo --test-enable output (PASS/FAIL/ERROR)
├── pyproject.toml          # [tool.ruff] — supermodule-level ruff config
├── .pre-commit-config.yaml # supermodule: ruff + prettier + check-xml
├── README.md               # Spanish, user-facing setup guide
├── AGENTS.md               # this file (auto-loaded project context)
├── .gitignore              # custom-addons, .qodo, .ruff_cache (submodules are tracked)
├── .gitmodules             # tracked git submodules (references/ + submodules/)
├── docker/                 # host Docker installers (debian/ubuntu)
├── custom-addons/          # GITIGNORED — generated addons path (bind-mounted, ~50 modules)
├── submodules/             # tracked git submodules — module sources (editable + versioned)
├── copy_addons.sh, exclude.txt   # sync submodules/* → custom-addons/ (before launching)
```

Key concepts:

- **`custom-addons/` is the only addons path Odoo loads from your repo.** It is
  gitignored (host-only), bind-mounted at `/mnt/custom-addons`, and takes
  precedence over the image-baked modules (see "Addons paths & shadowing").
  It is **generated**: don't edit it directly — edit `submodules/` and re-run
  `copy_addons.sh`.
- The files you can and should version-control are the infra:
  `Dockerfile`, `docker-compose.yml`, `Makefile`, `scripts/`, README/AGENTS,
  `.pre-commit-config.yaml`, `pyproject.toml`, `.gitignore`, `.gitmodules`.
  Module code lives in the `submodules/` submodules (tracked as gitlinks;
  commit there first, then update the pointer here).

## Addons paths & shadowing

The web service runs with:

```
--addons-path=/mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
```

Order matters — **the first path containing a module name wins**:

1. `/mnt/custom-addons` — host `./custom-addons` (bind mount), **generated
   from `submodules/` by `copy_addons.sh`**. Currently `mock_module` + ~49
   SolTec/AR modules.
2. `/mnt/extra-addons` — baked into the SOL3 image (read-only, ~123 modules).
   Baseline that a module in `custom-addons/` shadows on name collision.
3. core addons (`/usr/lib/python3/dist-packages/odoo/addons`).

> Because of this, if a module already exists in the image and you need to
> change it, first copy the source into `submodules/` (or copy the image copy
> into `custom-addons/` for a quick local-only override):
> `docker compose cp web:/mnt/extra-addons/<module> custom-addons/`
> then re-run `copy_addons.sh` — your copy now shadows the baked-in one.

## Environment Startup & Management

Everything runs through Docker Compose. The `Makefile` wraps the common flows;
raw `docker compose` equivalents are shown alongside.

| Action                                          | Make target       | Raw command                           |
| ----------------------------------------------- | ----------------- | ------------------------------------- |
| Build the Odoo image (after Dockerfile change)  | `make build`      | `docker compose build --no-cache`     |
| Start all services (detached)                   | `make up`         | `docker compose up -d`                |
| Stop services (keeps volumes)                   | `make down`       | `docker compose down`                 |
| Stop + delete volumes (wipe DB/files)           | `make down-clean` | `docker compose down -v`              |
| View Odoo logs (follow)                         | `make logs`       | `docker compose logs -f web`          |
| Service status                                  | `make ps`         | `docker compose ps`                   |
| Bash inside the Odoo container                  | `make shell`      | `docker compose exec web bash`        |
| Restart the web service                         | `make restart`    | `docker compose restart web`          |

`make help` lists all targets. Overridable variables: `DB` (default `odoo`),
`MODULE` (default `base`), `TEST_TAGS`.

Services and ports:

- **web** — Odoo 19 (SOL3 image, local tag `soltec-localdev-odoo19:1.0`).
  - Host port **8069** → http://localhost:8069
  - Addons path (see above); bind mount `./custom-addons:/mnt/custom-addons`;
    named volume `odoo-web-data:/var/lib/odoo`.
  - DB env: `HOST=db`, `USER=odoo`, `PASSWORD=odoo`.
- **db** — `postgres:14`, user/db/pass `odoo`/`odoo` (init DB `postgres`),
  host `db:5432` on the `odoo-network`; volume `postgres-data`.
- **pgadmin** — `dpage/pgadmin4`, host port **5050** → http://localhost:5050,
  login `admin@hola.com` / `admin`; connect to host `db`, port `5432`,
  user `odoo`, password `odoo`.

Notes:

- No `.env`, no db-filter, no `--test-enable` in the compose `command`.
  Create DBs via the web "Manage Databases" page (master password screen) and
  pass `-d <db>` on every CLI invocation.
- `docker compose exec web odoo` bypasses the entrypoint env vars, so **always**
  pass `--db_host=db --db_user=odoo --db_password=odoo` on CLI runs.
- If the container is not running, use `docker compose run --rm web` instead of
  `docker compose exec web`.

## Editing modules (the daily workflow)

> **Getting sources into `submodules/`**: add each module repo as a **git
> submodule**: `git submodule add <url> submodules/<repo>`, then
> `git add .gitmodules submodules/<repo>` and commit. After a fresh clone,
> initialise them with `make submodules-init`
> (`git submodule update --init --recursive`); update each to its branch tip with
> `make submodules-update` (`git submodule update --remote --merge`). Editing
> files inside a submodule is allowed: commit there first, then bump the gitlink
> in this supermodule.
>
> OCA dependency modules are provisioned the same way. E.g.
> `submodules/odoo-argentina-envios/delivery-carrier` pins OCA's
> `delivery-carrier` (branch 19.0) so its modules (`delivery_state`,
> `delivery_price_method`, `delivery_package_number`, …) are picked up by
> `copy_addons.sh` and installed from `custom-addons/`.

1. Edit the module source **only in `submodules/<repo>/.../<module>/`**.
2. Sync it into the addons path **before launching the container**:
   ```bash
   bash copy_addons.sh        # or: make sync
   ```
   `copy_addons.sh` finds every `__manifest__.py` under `./submodules/`
   (excluding `.git/`), rsyncs each module dir to `custom-addons/<basename>`
   with `--delete`, then prunes orphan dirs in `custom-addons/` that lack a
   manifest (handles upstream renames). `exclude.txt` strips README/docs/lint
   config from the copy.
3. Launch (or restart) the container so Odoo picks up the synced modules:
   ```bash
   make up         # first launch: docker compose up -d
   make restart    # if already running
   ```
   (`./custom-addons` is a bind mount, so no image rebuild is needed.)
4. Apply the change to the database:
   - **Python only** → `make restart` is enough (code is read at import time).
   - **Views / data / security / manifest / translations** → restart **and**
     upgrade the module:
     ```bash
     make upgrade DB=<db> MODULE=<module_name>
     ```
     or raw:
     ```bash
     docker compose exec web odoo \
       --addons-path=/mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons \
       --db_host=db --db_user=odoo --db_password=odoo \
       -d <db> -u <module_name> --stop-after-init --http-port 8099
     ```
5. Check the module actually shadows the image copy: if the module exists in
   `/mnt/extra-addons` too, your `custom-addons` copy must be the one loaded —
   the `addons paths:` order in the startup log and the `-u` output confirm it.

### Install / upgrade

```bash
# Install one or several modules
make install DB=<db> MODULE=l10n_ar,l10n_ar_tax,<...>
# Upgrade one module (re-runs views/security + migrations/<ver>/ scripts)
make upgrade DB=<db> MODULE=<module_name>
```

> Gotcha: the `Makefile` `ADDONS_PATH` is `=/mnt/custom-addons,/usr/lib/python3/dist-packages/odoo/addons`
> and does **not** include `/mnt/extra-addons`. If the module you install/upgrade
> lives only in the image, use the raw form above (with `/mnt/extra-addons`).
> Consider fixing `ADDONS_PATH` in the Makefile to match the compose command.

### Running tests

The `Makefile` wraps Odoo's built-in runner with output filtering via
`scripts/test-runner.sh`:

```bash
make test MODULE=<module_name>            # -u + --test-enable, filtered output
make test MODULE=<module_name> TEST_TAGS=/soltec:<module>   # narrowed
make test-install MODULE=<module_name>    # fresh install (-i) + tests
make test-raw MODULE=<module_name>        # unfiltered Odoo output
```

Raw equivalent:

```bash
docker compose exec web odoo \
  --addons-path=/mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons \
  --db_host=db --db_user=odoo --db_password=odoo \
  -d <db> --test-enable --test-tags=<module_name> \
  -u <module_name> --stop-after-init --log-level=info
```

- `--test-tags` filters by module path (`module.Class.method`) and/or custom
  tags; the leading-`/` form matches tags. Tag tests with `@tagged(...)` and a
  custom tag (e.g. the module name) for clean filtering.
- Per-module data migrations (`<module>/migrations/<version>/pre-migrate.py`,
  `post-migrate.py`) run automatically on `-u <module>`.

### Database / shell

```bash
make dbshell DB=<db>     # psql in the postgres container
make odoo-shell DB=<db>  # Python prompt with env/registry inside the container
```

## Translations (Odoo 19)

- Translations are stored as **JSONB on the record** (e.g.
  `ir_model_fields_selection.name`, model field descriptions/helps, view
  terms) — there is no `ir.translation` table anymore.
- `.po` files are loaded from the module's `i18n/` on install/upgrade, keyed by
  the **active language code** (es_AR → `es_AR.po`). Only loaded for languages
  active in the DB.
- **Overwrite semantics (the classic foot-gun):** a plain `-u <module>` does
  **not** overwrite existing translations. Add `--i18n-overwrite`:
  ```bash
  docker compose exec web odoo --addons-path=/mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons \
    --db_host=db --db_user=odoo --db_password=odoo \
    -d <db> -u <module> --i18n-overwrite --stop-after-init --http-port 8099
  ```
- **Empty `msgstr` terms are skipped entirely** by the importer: they neither
  overwrite nor *remove* an existing (bad) translation. If a DB already has a
  bogus value for a term you blanked out, delete the language key from the JSONB
  directly:
  ```sql
  UPDATE ir_model_fields_selection SET name = name - 'es_AR'
  WHERE name ? 'es_AR';
  ```
  (non-empty `msgstr` + `--i18n-overwrite` also works — it rewrites the key).
- Browser/JS caches translations: hard-refresh after changing them.

## Linting & Type Checking

Supermodule-level config (`.pre-commit-config.yaml` + `pyproject.toml`):

```bash
make lint      # pre-commit run --all-files (ruff + prettier + check-xml)
make format    # autofix (ruff + prettier), won't fail
```

- `pre-commit run --all-files` only scans files tracked by the top-level repo
  (infra files). Module code under `custom-addons/` is gitignored, so lint it
  with ruff directly: `ruff check custom-addons/<module>` (or `--fix`).
- `submodules/odoo-argentina` carries its own adhoc pre-commit stack; if the
  dir exists, run `make lint-odoo-ar` (or
  `cd submodules/odoo-argentina && pre-commit run --all-files`).
- **No type checker** is configured (`mypy`/`pyright` absent).

## Documentation

- **`README.md`** (root, Spanish) — user-facing setup guide.
- **`AGENTS.md`** — this file (opencode project context, auto-loaded).
- `.qodo/` — empty Qodo scaffold (safe to delete).

## Conventions & Gotchas

1. **Edit `custom-addons/` only through `submodules/` + `copy_addons.sh`.**
   `custom-addons/` is generated and gitignored; the source of truth for
   module code lives in the `submodules/` git submodules (tracked as gitlinks).
   Never hand-edit `custom-addons/` — re-run the sync and restart instead.
   Commit inside the submodule first, then bump the gitlink here.
2. **Addons-path shadowing**: `/mnt/custom-addons` > `/mnt/extra-addons` >
   core. First path containing the module name wins.
3. **`mock_module`** placeholder in `custom-addons/` keeps the addons path
   valid — Odoo refuses an addons path that contains no valid module ("not a
   valid addons directory"). Remove it only when real modules are present.
4. **Always pass `-d <db>`** and the DB connection args on CLI runs; use
   `--http-port 8099` (a free port) so `-i`/`-u`/`--test-enable` runs don't
   collide with the running web container's 8069.
5. **Makefile `ADDONS_PATH` is missing `/mnt/extra-addons`** (only
   `custom-addons` + core). For modules that live only in the image, use the
   raw command with the full path. Recommend fixing the Makefile.
6. **Translations**: plain `-u` doesn't overwrite; use `--i18n-overwrite`;
   empty `msgstr` terms are skipped (never clean existing DB values).
7. **Image versions**: `muevetec/soltec-odoo:19.0.6-dev` is Odoo 19 (correct).
   The older tag `1.0.6-dev` is **Odoo 16** — do not switch the Dockerfile to
   it.
8. **`mock_repo` placeholder**: `submodules/mock_repo/mock_module/` is a
   tracked placeholder (added in `42ded27`) that kept the addons path valid
   while `submodules/` had no real sources. Real submodules now exist
   (`submodules/odoo-argentina-envios`), so it can be removed when convenient.
10. **Branch model**: develop on `19.0`. Don't mix module commits between
    Odoo-version branches. Only commit/push when explicitly asked.
11. **Odoo-16 quick check**: a fresh image build silently downgrading to
    "Odoo version 16.0…" in the logs means the Dockerfile `FROM` was changed to
    a wrong tag — verify after `make build`.
12. **`arcaws.env.type`** changes apply live (no restart): switching
    homologation↔production takes effect immediately; an invalid value raises a
    `UserError` (no silent fallback).