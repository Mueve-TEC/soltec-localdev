#!/usr/bin/env bash
#
# ticket.sh — per-ticket Odoo worktrees (parallel development).
#
# Usage:
#   scripts/ticket.sh new SLUG
#   scripts/ticket.sh up|down|logs|shell|dbshell|upgrade|test|list SLUG
#   scripts/ticket.sh done SLUG [KEEP=1] [FORCE=1]
#   scripts/ticket.sh golden-refresh [SRC_DB=admin]
#   scripts/ticket.sh guard-down-clean
#
# In a ticket worktree SLUG can be omitted: it is read from .ticket/env.
#
# What a ticket gets: its own git worktree + branch(es), Odoo web container,
# host port, database and filestore volume. The Postgres server and the Docker
# image are shared with the main checkout.
#
# Environment overrides:
#   TICKETS_DIR    (default: <main checkout>/../soltec-tickets)
#   GOLDEN_DB      (default: ticket_template)
#   IMAGE_TAG      (default: soltec-localdev-odoo19:1.0)
#   MAIN_PROJECT   (default: basename of the main checkout)
#   MAIN_ROOT      (default: the main checkout, via git common dir)
#   BASE_REF       (default: HEAD of the main checkout)  — used by `new`
#   SRC_DB         (default: admin)                      — used by `golden-refresh`

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/ticket-lib.sh
source "$SCRIPT_DIR/ticket-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  scripts/ticket.sh new SLUG
  scripts/ticket.sh up|down|logs|shell|dbshell|list [SLUG]
  scripts/ticket.sh upgrade SLUG MODULE=<module>
  scripts/ticket.sh test SLUG MODULE=<module> [TEST_TAGS=<tags>]
  scripts/ticket.sh done SLUG [KEEP=1] [FORCE=1]
  scripts/ticket.sh golden-refresh [SRC_DB=admin]
  scripts/ticket.sh guard-down-clean

SLUG is optional inside a ticket worktree (read from .ticket/env).
EOF
}

wait_http() {
  local port=$1
  local i
  for i in $(seq 1 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:$port/web/login" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  warn "web did not answer at http://localhost:$port yet (check: make ticket-logs)"
}

init_submodules() {
  local dir=$1
  local slug=$2
  local branch
  branch=$(slug_branch "$slug")

  git -C "$dir" submodule update --init --recursive

  while read -r _sha path _rest; do
    [[ -n "${path:-}" ]] || continue
    local sub="$dir/$path"
    [[ -e "$sub/.git" ]] || continue

    if git -C "$sub" fetch --quiet origin 19.0 2>/dev/null &&
      git -C "$sub" rev-parse --verify --quiet refs/remotes/origin/19.0 >/dev/null; then
      if ! git -C "$sub" merge-base --is-ancestor HEAD refs/remotes/origin/19.0; then
        warn "$path: the recorded revision is not an ancestor of origin/19.0 (commits may diverge)"
      fi
      git -C "$sub" checkout -q -B "$branch" refs/remotes/origin/19.0
    else
      warn "could not fetch origin/19.0 for $path; branching from the recorded revision"
      git -C "$sub" checkout -q -B "$branch" 2>/dev/null || true
    fi
  done < <(git -C "$dir" submodule status 2>/dev/null || true)

  if ! git -C "$dir" diff --quiet -- submodules; then
    git -C "$dir" add submodules
    git -C "$dir" commit -qm "[CHORE] $slug: start submodules at origin/19.0"
  fi
}

cmd_new() {
  local slug=${1:-${SLUG:-}}
  local dir branch project db port base_sha created=0

  [[ -n "$slug" ]] || die "usage: make ticket-new SLUG=<slug>"
  slug_valid "$slug" ||
    die "invalid slug '$slug' (use lowercase letters, digits and dashes: ^[a-z0-9][a-z0-9-]{1,40}$)"

  dir=$(ticket_dir_for "$slug")
  branch=$(slug_branch "$slug")
  project=$(slug_project "$slug")
  db=$(slug_db "$slug")

  [[ -f "$MAIN_ROOT/docker-compose.yml" ]] ||
    die "main checkout not found at $MAIN_ROOT"
  [[ -e "$dir" ]] && die "ticket directory already exists: $dir"
  git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$branch" &&
    die "branch '$branch' already exists in $MAIN_ROOT"

  require_image "$DEFAULT_IMAGE_TAG"
  ensure_db_up
  require_golden

  if db_exists "$db"; then
    [[ "${RECREATE:-0}" == "1" ]] ||
      die "database '$db' already exists (rerun with RECREATE=1 to drop and recreate it)"
    db_drop "$db"
  fi

  base_sha=$(git -C "$MAIN_ROOT" rev-parse "${BASE_REF:-HEAD}")

  mkdir -p "$TICKETS_DIR"

  trap 'if [[ $created -eq 1 ]]; then
          printf "\nPartial ticket created. Clean it up with:\n  make ticket-done SLUG=%s FORCE=1\n\n" "$slug" >&2
        fi' ERR

  info "creating worktree $dir (from ${BASE_REF:-HEAD})"
  git -C "$MAIN_ROOT" worktree add -b "$branch" "$dir" "$base_sha"
  created=1

  info "initialising submodules and branching them at origin/19.0"
  init_submodules "$dir" "$slug"

  info "syncing submodules/ -> custom-addons/"
  (cd "$dir" && bash copy_addons.sh)

  port=$(find_free_port "$slug" "$slug")

  info "cloning $GOLDEN_DB -> $db"
  db_create_from_template "$db" "$GOLDEN_DB"

  info "cloning filestore ($GOLDEN_DB -> $db) into $project volume"
  clone_filestore "$db" "$GOLDEN_DB" "$project" "$DEFAULT_IMAGE_TAG"

  write_ticket_files "$dir" "$slug" "$project" "$db" "$port" "$DEFAULT_IMAGE_TAG" "$base_sha"
  load_ticket "$slug"

  local mods
  mods=$(installed_custom_modules "$db" "$dir/custom-addons")
  if [[ -n "$mods" ]]; then
    info "upgrading installed custom modules: $mods"
    ticket_compose run --rm --no-deps web \
      odoo --addons-path="$ADDONS_PATH" \
      --db_host=db --db_user=odoo --db_password=odoo \
      -d "$db" -u "$mods" --stop-after-init --http-port=8099 --log-level=warn
  else
    info "no custom modules installed in $db; skipping upgrade"
  fi

  info "starting ticket web container"
  ticket_compose up -d web
  wait_http "$port"

  trap - ERR
  print_ticket_summary "$slug" "$dir"
}

cmd_up() {
  load_ticket "${1:-}"
  ensure_db_up
  ticket_compose up -d web
  printf 'Ticket %s: http://localhost:%s\n' "$TICKET_SLUG" "$WEB_PORT"
}

cmd_down() {
  load_ticket "${1:-}"
  ticket_compose down
  printf 'Ticket %s stopped (DB and filestore volume kept).\n' "$TICKET_SLUG"
}

cmd_logs() {
  load_ticket "${1:-}"
  ticket_compose logs -f web
}

cmd_shell() {
  load_ticket "${1:-}"
  ticket_compose exec web bash
}

cmd_dbshell() {
  load_ticket "${1:-}"
  ensure_db_up
  main_compose exec db psql -U odoo -d "$TICKET_DB"
}

cmd_upgrade() {
  load_ticket "${1:-}"
  [[ -n "${MODULE:-}" ]] || die "MODULE=<module> is required"
  ticket_compose exec -T web \
    odoo --addons-path="$ADDONS_PATH" \
    --db_host=db --db_user=odoo --db_password=odoo \
    -d "$TICKET_DB" -u "$MODULE" --stop-after-init --http-port=8099
}

cmd_test() {
  load_ticket "${1:-}"
  [[ -n "${MODULE:-}" ]] || die "MODULE=<module> is required"

  local args=(
    exec -T web odoo
    --addons-path="$ADDONS_PATH"
    --db_host=db --db_user=odoo --db_password=odoo
    -d "$TICKET_DB" -u "$MODULE" --test-enable
  )
  [[ -n "${TEST_TAGS:-}" ]] && args+=(--test-tags="$TEST_TAGS")
  args+=(--stop-after-init --http-port=8099 --log-level=info)

  ticket_compose "${args[@]}"
}

cmd_list() {
  local found=0 dir state
  printf '%-24s %-22s %-6s %-24s %s\n' "SLUG" "DATABASE" "PORT" "COMPOSE PROJECT" "WEB"

  for dir in "$TICKETS_DIR"/*; do
    [[ -f "$dir/.ticket/env" ]] || continue
    found=1
    (
      # shellcheck disable=SC1091
      source "$dir/.ticket/env"
      state=$(docker ps \
        --filter "label=com.docker.compose.project=$TICKET_PROJECT" \
        --filter "label=com.docker.compose.service=web" \
        --format '{{.State}}' 2>/dev/null | head -n1)
      printf '%-24s %-22s %-6s %-24s %s\n' \
        "$TICKET_SLUG" "$TICKET_DB" "$WEB_PORT" "$TICKET_PROJECT" "${state:--}"
    )
  done

  [[ $found -eq 1 ]] || printf 'no tickets in %s\n' "$TICKETS_DIR"
}

collect_problems() {
  local dir=$1
  local problems=()
  local status count path sub

  status=$(git -C "$dir" status --porcelain -- . ':(exclude)submodules' 2>/dev/null || true)
  [[ -n "$status" ]] && problems+=("superproject: uncommitted changes")

  if [[ -n "${TICKET_BASE_SHA:-}" ]]; then
    count=$(git -C "$dir" rev-list --count "$TICKET_BASE_SHA"..HEAD --not --remotes \
      -- . ':(exclude)submodules' 2>/dev/null || echo 0)
  else
    count=$(git -C "$dir" rev-list --count HEAD --not --remotes \
      -- . ':(exclude)submodules' 2>/dev/null || echo 0)
  fi
  [[ "$count" -gt 0 ]] &&
    problems+=("superproject: $count unpushed commit(s) touching infra files")

  while read -r _sha path _rest; do
    [[ -n "${path:-}" ]] || continue
    sub="$dir/$path"
    [[ -e "$sub/.git" ]] || continue

    if [[ -n "$(git -C "$sub" status --porcelain 2>/dev/null || true)" ]]; then
      problems+=("$path: uncommitted changes")
    fi
    count=$(git -C "$sub" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)
    [[ "$count" -gt 0 ]] &&
      problems+=("$path: $count unpushed commit(s)")
  done < <(git -C "$dir" submodule status 2>/dev/null || true)

  [[ ${#problems[@]} -eq 0 ]] && return 0
  printf '%s\n' "${problems[@]}"
}

cmd_done() {
  local slug=${1:-${SLUG:-}}
  local dir problems

  [[ -n "$slug" ]] || die "usage: make ticket-done SLUG=<slug>"
  load_ticket "$slug"
  dir=$TICKET_DIR

  if [[ "${KEEP:-0}" == "1" ]]; then
    ticket_compose down
    printf 'Ticket %s stopped; worktree, DB (%s) and volumes kept.\n' "$TICKET_SLUG" "$TICKET_DB"
    return 0
  fi

  problems=$(collect_problems "$dir")
  if [[ -n "$problems" && "${FORCE:-0}" != "1" ]]; then
    {
      printf 'Refusing to remove ticket %s:\n' "$TICKET_SLUG"
      while IFS= read -r problem; do printf '  - %s\n' "$problem"; done <<<"$problems"
      printf '\nPush the submodule commits (and bump the gitlinks) first, or rerun with FORCE=1.\n'
    } >&2
    exit 1
  fi

  info "stopping ticket containers and removing volumes"
  ticket_compose down -v || true

  info "dropping database $TICKET_DB"
  db_drop "$TICKET_DB"

  info "removing worktree $dir"
  if [[ -e "$dir" ]]; then
    if [[ "${FORCE:-0}" == "1" ]]; then
      git -C "$MAIN_ROOT" worktree remove --force "$dir"
    else
      git -C "$MAIN_ROOT" worktree remove "$dir"
    fi
  fi
  git -C "$MAIN_ROOT" worktree prune

  if git -C "$MAIN_ROOT" branch -d "$TICKET_BRANCH" >/dev/null 2>&1; then
    printf 'Removed merged branch %s.\n' "$TICKET_BRANCH"
  else
    printf 'Branch %s kept (not merged into HEAD, or already gone).\n' "$TICKET_BRANCH"
  fi

  printf 'Ticket %s removed.\n' "$TICKET_SLUG"
}

cmd_guard_down_clean() {
  local problems=() dir running

  if [[ -f "$PWD/.ticket/env" ]]; then
    warn "this is a ticket worktree: 'down-clean' only removes its volumes; the DB stays in the shared Postgres."
    warn "prefer: make ticket-done SLUG=$(basename "$PWD")"
    exit 0
  fi

  [[ "${FORCE:-0}" == "1" ]] && exit 0

  for dir in "$TICKETS_DIR"/*; do
    [[ -f "$dir/.ticket/env" ]] && problems+=("ticket worktree: $dir")
  done

  running=$(docker ps \
    --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null |
    grep -E '^tkt-' | sort -u || true)
  [[ -n "$running" ]] && problems+=("running ticket project(s): $(echo "$running" | paste -sd' ' -)")

  if [[ ${#problems[@]} -gt 0 ]]; then
    {
      printf 'Refusing to run down -v in the main checkout:\n'
      printf '  - %s\n' "${problems[@]}"
      printf '\nThis would wipe the shared Postgres and every ticket DB.\n'
      printf 'Remove the tickets first (make ticket-done SLUG=...), or rerun with FORCE=1.\n'
    } >&2
    exit 1
  fi
}

cmd_golden_refresh() {
  local src=${SRC_DB:-admin}
  local tmp

  [[ "$src" != "$GOLDEN_DB" ]] || die "SRC_DB cannot be the golden DB itself"
  ensure_db_up
  db_exists "$src" || die "source database '$src' does not exist"

  tmp=$(mktemp)
  trap 'rm -f "${tmp:-}"' EXIT

  info "dumping $src"
  main_compose exec -T db pg_dump -U odoo --format=custom "$src" >"$tmp"

  info "recreating $GOLDEN_DB"
  main_compose exec -T db dropdb -U odoo --if-exists --force "$GOLDEN_DB"
  main_compose exec -T db createdb -U odoo -O odoo "$GOLDEN_DB"

  info "restoring into $GOLDEN_DB"
  main_compose exec -T db pg_restore -U odoo -d "$GOLDEN_DB" \
    --no-owner --no-privileges <"$tmp"

  info "syncing filestore ($src -> $GOLDEN_DB)"
  docker run --rm \
    --entrypoint sh \
    -e SRC="$src" \
    -e DST="$GOLDEN_DB" \
    -v "${MAIN_PROJECT}_odoo-web-data:/data" \
    "$DEFAULT_IMAGE_TAG" -c '
      set -e
      mkdir -p /data/filestore
      rm -rf "/data/filestore/$DST"
      if [ -d "/data/filestore/$SRC" ]; then
        cp -a "/data/filestore/$SRC" "/data/filestore/$DST"
      else
        mkdir -p "/data/filestore/$DST"
      fi
    '

  info "golden database '$GOLDEN_DB' refreshed from '$src'"
}

main() {
  local cmd=${1:-help}
  shift || true

  case "$cmd" in
  new) cmd_new "$@" ;;
  up) cmd_up "$@" ;;
  down) cmd_down "$@" ;;
  logs) cmd_logs "$@" ;;
  shell) cmd_shell "$@" ;;
  dbshell) cmd_dbshell "$@" ;;
  upgrade) cmd_upgrade "$@" ;;
  test) cmd_test "$@" ;;
  list) cmd_list "$@" ;;
  done) cmd_done "$@" ;;
  golden-refresh) cmd_golden_refresh "$@" ;;
  guard-down-clean) cmd_guard_down_clean "$@" ;;
  help | -h | --help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
}

main "$@"
