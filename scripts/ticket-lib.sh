#!/usr/bin/env bash
#
# ticket-lib.sh — helpers shared by scripts/ticket.sh (per-ticket worktrees).
#
# This file is sourced, not executed. It assumes bash 4+ and that the caller
# already enabled `set -euo pipefail`.
#
# Design summary:
#   * The main checkout owns the shared Postgres, the golden DB and the image.
#   * Each ticket lives in a sibling git worktree and runs its own Odoo web
#     container, attached to the main stack's Docker network.
#   * The main checkout is located through `git rev-parse --git-common-dir`, so
#     the helpers work identically from the main checkout and from any linked
#     worktree (no hardcoded paths).

IMAGE_TAG_DEFAULT="soltec-localdev-odoo19:1.0"
ADDONS_PATH="/mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons"
RESERVED_PORTS="5050 5051 5432 8069 8070 8099"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

info() {
  printf '==> %s\n' "$*" >&2
}

# ---------------------------------------------------------------------------
# Paths and project identity
# ---------------------------------------------------------------------------

ticket_common_dir() {
  local common
  common=$(git rev-parse --git-common-dir) ||
    die "not inside a git repository"
  if [[ "$common" != /* ]]; then
    common=$(cd "$common" && pwd)
  fi
  dirname "$common"
}

sanitize_name() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9_-]+//g; s/^[^a-z0-9]+//'
}

MAIN_ROOT=${MAIN_ROOT:-$(ticket_common_dir)}
[[ -f "$MAIN_ROOT/docker-compose.yml" ]] ||
  die "main checkout not found at $MAIN_ROOT (missing docker-compose.yml)"

MAIN_PROJECT=${MAIN_PROJECT:-$(sanitize_name "$(basename "$MAIN_ROOT")")}
[[ -n "$MAIN_PROJECT" ]] ||
  die "cannot derive a compose project name from '$MAIN_ROOT' (set MAIN_PROJECT)"

MAIN_NETWORK="${MAIN_PROJECT}_odoo-network"
MAIN_VOLUME="${MAIN_PROJECT}_odoo-web-data"

TICKETS_DIR=${TICKETS_DIR:-$MAIN_ROOT/../soltec-tickets}
TICKETS_DIR=$(realpath -m "$TICKETS_DIR")

GOLDEN_DB=${GOLDEN_DB:-ticket_template}
DEFAULT_IMAGE_TAG=${IMAGE_TAG:-$IMAGE_TAG_DEFAULT}

TICKET_DIR=""
TICKET_SLUG=""
TICKET_BRANCH=""
TICKET_PROJECT=""
TICKET_DB=""
TICKET_WEB_PORT=""
TICKET_MAIN_ROOT=""
TICKET_MAIN_PROJECT=""
TICKET_MAIN_NETWORK=""
TICKET_MAIN_VOLUME=""
TICKET_GOLDEN_DB=""
TICKET_IMAGE_TAG=""

# ---------------------------------------------------------------------------
# Ticket helpers
# ---------------------------------------------------------------------------

slug_valid() {
  local slug=$1
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]{1,40}$ ]]
}

slug_db() {
  printf 't_%s' "${1//-/_}"
}

slug_project() {
  printf 'tkt-%s' "$1"
}

slug_branch() {
  printf '19.0-%s' "$1"
}

ticket_dir_for() {
  local slug=$1
  printf '%s/%s' "$TICKETS_DIR" "$slug"
}

load_ticket() {
  local slug=${1:-}
  local dir

  if [[ -n "$slug" ]]; then
    dir=$(ticket_dir_for "$slug")
  elif [[ -f "$PWD/.ticket/env" ]]; then
    dir=$PWD
  else
    die "not inside a ticket worktree and no SLUG given"
  fi

  [[ -f "$dir/.ticket/env" ]] ||
    die "no ticket environment at $dir (create one with: make ticket-new SLUG=<slug>)"

  # shellcheck disable=SC1091
  source "$dir/.ticket/env"

  TICKET_DIR=$dir
  # The main checkout is authoritative even when the env file is stale.
  MAIN_ROOT=${TICKET_MAIN_ROOT:-$MAIN_ROOT}
  MAIN_PROJECT=${TICKET_MAIN_PROJECT:-$MAIN_PROJECT}
  MAIN_NETWORK=${TICKET_MAIN_NETWORK:-${MAIN_PROJECT}_odoo-network}
  MAIN_VOLUME=${TICKET_MAIN_VOLUME:-${MAIN_PROJECT}_odoo-web-data}

  [[ -n "${TICKET_SLUG:-}" && -n "${TICKET_DB:-}" && -n "${WEB_PORT:-}" ]] ||
    die "incomplete ticket environment at $dir/.ticket/env"
}

# ---------------------------------------------------------------------------
# Docker helpers
# ---------------------------------------------------------------------------

main_compose() {
  docker compose \
    --project-directory "$MAIN_ROOT" \
    -p "$MAIN_PROJECT" \
    "$@"
}

ticket_compose() {
  (
    cd "$TICKET_DIR"
    docker compose \
      -p "$TICKET_PROJECT" \
      -f docker-compose.ticket.yml \
      --env-file .env \
      "$@"
  )
}

ensure_db_up() {
  if ! main_compose exec -T db true >/dev/null 2>&1; then
    info "starting the main stack's db service..."
    main_compose up -d db
  fi

  local i
  for i in $(seq 1 60); do
    if main_compose exec -T db pg_isready -U odoo -q >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  die "postgres did not become ready (check: cd '$MAIN_ROOT' && docker compose logs db)"
}

db_psql() {
  local db=$1
  local sql=$2
  main_compose exec -T db psql -U odoo -d "$db" -tAc "$sql"
}

db_exists() {
  local name=${1//\'/\'\'}
  [[ "$(db_psql postgres "SELECT 1 FROM pg_database WHERE datname = '$name'")" == "1" ]]
}

db_create_from_template() {
  local db=$1
  local template=$2
  local dbq=${db//\"/\"\"}
  local templateq=${template//\"/\"\"}

  # CREATE DATABASE ... TEMPLATE is the fast path, but Postgres refuses to
  # clone a database that has open connections, and the running Odoo connects
  # to every database it discovers, the golden one included. So whenever the
  # main stack is up this fails: fall back to a dump/restore pipeline, which
  # tolerates connections and is what golden-refresh itself uses.
  if db_psql postgres "CREATE DATABASE \"$dbq\" WITH TEMPLATE \"$templateq\" OWNER \"odoo\"" >/dev/null 2>&1; then
    return 0
  fi

  warn "could not clone '$template' with TEMPLATE (open connections); cloning with pg_dump/pg_restore"
  db_drop "$db"
  main_compose exec -T db createdb -U odoo -O odoo "$dbq"
  main_compose exec -T db pg_dump -U odoo --no-owner --no-privileges "$template" |
    main_compose exec -T db psql -U odoo -d "$dbq" -q -v ON_ERROR_STOP=1 >/dev/null
}

db_drop() {
  local db=$1
  main_compose exec -T db dropdb -U odoo --if-exists --force "$db"
}

# Databases available in the shared Postgres, comma separated. Used to make
# error messages actionable instead of suggesting a database that may not
# exist.
list_databases() {
  main_compose exec -T db psql -U odoo -d postgres -tAc \
    "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY datname" |
    paste -sd, -
}

require_golden() {
  if db_exists "$GOLDEN_DB"; then
    return 0
  fi
  die "golden database '$GOLDEN_DB' does not exist.
Create it with: make golden-refresh SRC_DB=<database>
Available databases: $(list_databases)"
}

# Fail with an actionable message when the ticket web container is not
# running; `docker compose exec` would otherwise fail with a raw engine error.
require_web() {
  local state
  state=$(docker ps \
    --filter "label=com.docker.compose.project=$TICKET_PROJECT" \
    --filter "label=com.docker.compose.service=web" \
    --format '{{.State}}' | head -n1)
  [[ "$state" == "running" ]] ||
    die "ticket web is not running (start it with: make ticket-up SLUG=$TICKET_SLUG)"
}

require_image() {
  local image=${1:-$DEFAULT_IMAGE_TAG}
  docker image inspect "$image" >/dev/null 2>&1 ||
    die "image '$image' not found (run: make build in '$MAIN_ROOT')"
}

# Copy the golden filestore into the ticket's own volume.
clone_filestore() {
  local db=$1
  local template=$2
  local project=$3
  local image=$4

  docker run --rm \
    --entrypoint sh \
    -e DB="$db" \
    -e SRC="$template" \
    -v "${MAIN_PROJECT}_odoo-web-data:/src:ro" \
    -v "${project}_odoo-web-data:/var/lib/odoo" \
    "$image" -c '
      set -e
      mkdir -p /var/lib/odoo/filestore
      rm -rf "/var/lib/odoo/filestore/$DB"
      if [ -d "/src/filestore/$SRC" ]; then
        cp -a "/src/filestore/$SRC" "/var/lib/odoo/filestore/$DB"
      else
        mkdir -p "/var/lib/odoo/filestore/$DB"
      fi
    '
}

# Print the installed modules that come from ./custom-addons, comma-separated.
installed_custom_modules() {
  local db=$1
  local addons_dir=$2
  local installed custom

  installed=$(db_psql "$db" "SELECT name FROM ir_module_module WHERE state = 'installed'")
  custom=$(
    find "$addons_dir" -mindepth 2 -maxdepth 2 -name __manifest__.py -printf '%h\n' 2>/dev/null |
      xargs -r -n1 basename |
      sort -u
  )

  comm -12 \
    <(printf '%s\n' "$installed" | sort -u) \
    <(printf '%s\n' "$custom") |
    paste -sd, -
}

# ---------------------------------------------------------------------------
# Ports
# ---------------------------------------------------------------------------

port_is_reserved() {
  local port=$1
  local p
  for p in $RESERVED_PORTS; do
    [[ "$port" == "$p" ]] && return 0
  done
  return 1
}

port_is_listening() {
  local port=$1
  (exec 3<>"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1
}

ticket_port_taken() {
  local port=$1
  local exclude=$2
  local dir

  for dir in "$TICKETS_DIR"/*; do
    [[ -f "$dir/.ticket/env" ]] || continue
    [[ "$(basename "$dir")" == "$exclude" ]] && continue
    if grep -q "^WEB_PORT=$port\$" "$dir/.ticket/env" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

find_free_port() {
  local slug=$1
  local exclude=${2:-}
  local sum start port i

  sum=$(printf '%s' "$slug" | cksum | cut -d' ' -f1)
  start=$((8100 + sum % 400))
  port=$start

  for i in $(seq 1 400); do
    if ! port_is_reserved "$port" &&
      ! port_is_listening "$port" &&
      ! ticket_port_taken "$port" "$exclude"; then
      printf '%s' "$port"
      return 0
    fi
    port=$((8100 + (port - 8100 + 1) % 400))
  done

  die "no free port found in 8100-8499 for ticket '$slug'"
}

# ---------------------------------------------------------------------------
# Ticket metadata
# ---------------------------------------------------------------------------

write_ticket_files() {
  local dir=$1
  local slug=$2
  local project=$3
  local db=$4
  local port=$5
  local image=$6
  local base_sha=$7
  local branch

  branch=$(slug_branch "$slug")

  mkdir -p "$dir/.ticket"

  {
    printf 'TICKET_SLUG=%q\n' "$slug"
    printf 'TICKET_BRANCH=%q\n' "$branch"
    printf 'TICKET_PROJECT=%q\n' "$project"
    printf 'TICKET_DB=%q\n' "$db"
    printf 'WEB_PORT=%q\n' "$port"
    printf 'TICKET_MAIN_ROOT=%q\n' "$MAIN_ROOT"
    printf 'TICKET_MAIN_PROJECT=%q\n' "$MAIN_PROJECT"
    printf 'TICKET_MAIN_NETWORK=%q\n' "$MAIN_NETWORK"
    printf 'TICKET_MAIN_VOLUME=%q\n' "$MAIN_VOLUME"
    printf 'TICKET_GOLDEN_DB=%q\n' "$GOLDEN_DB"
    printf 'TICKET_IMAGE_TAG=%q\n' "$image"
    printf 'TICKET_BASE_SHA=%q\n' "$base_sha"
    printf 'TICKET_CREATED=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$dir/.ticket/env"

  cat >"$dir/.env" <<EOF
# Generated by scripts/ticket.sh new — do NOT commit.
# Plain \`docker compose\` in this directory targets this ticket automatically.
COMPOSE_PROJECT_NAME=$project
COMPOSE_FILE=docker-compose.ticket.yml
TICKET_PROJECT=$project
WEB_PORT=$port
MAIN_NETWORK=$MAIN_NETWORK
IMAGE_TAG=$image
EOF

  cat >"$dir/.ticket/env.mk" <<EOF
# Generated by scripts/ticket.sh new — included by the Makefile.
TICKET_DB=$db
EOF

  cat >"$dir/.ticket/TICKET.md" <<EOF
# Ticket worktree: $slug

This worktree runs an **isolated Odoo web container**, but it **shares the
main checkout's Postgres** and Docker network.

| Item | Value |
| ---- | ----- |
| Slug | \`$slug\` |
| Branch | \`$branch\` |
| Compose project | \`$project\` |
| Database | \`$db\` |
| Web URL | http://localhost:$port |
| Golden DB | \`$GOLDEN_DB\` |
| Main checkout | \`$MAIN_ROOT\` |

## Rules for agents working here

1. You are in a **ticket worktree**, not in the main checkout. Never edit
   \`$MAIN_ROOT\` from this session.
2. Odoo module sources live in \`submodules/\`. Edit there, then run
   \`bash copy_addons.sh\` (or \`make sync\`).
3. Use this worktree's \`make\` targets: they are pinned to \`$db\` by
   \`.ticket/env.mk\`. Run \`make upgrade MODULE=<module>\` for views/data and
   \`make test MODULE=<module>\`.
4. The database is shared infrastructure: run \`make upgrade\` / \`make test\`
   here (they use \`-d $db\`), never against the main DBs.
5. The main stack must be up for the DB: \`make ticket-up\` starts it if needed.
6. Read the "Parallel ticket worktrees" section of the root \`AGENTS.md\`.

## Teardown

From the main checkout: \`make ticket-done SLUG=$slug\` (refuses if there are
uncommitted or unpushed commits; \`FORCE=1\` overrides).
EOF
}

print_ticket_summary() {
  local slug=$1
  local dir=$2
  local url="http://localhost:$WEB_PORT"

  cat <<EOF

Ticket '$slug' is ready.

  worktree : $dir
  database : $TICKET_DB (shared Postgres, main stack)
  url      : $url

Open its session with:

  cd $dir && opencode

Useful commands (run inside the worktree):

  make ticket-up | make ticket-down | make ticket-logs
  make upgrade MODULE=<module> | make test MODULE=<module>
  make ticket-dbshell

EOF
}
