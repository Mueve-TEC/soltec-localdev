#!/usr/bin/env bash
# pilot-check.sh — Readiness checks before the Etapa 4 pilot.
#
# Verifies the running stack, installed modules, isolation record rules,
# private attachments, a live (rolled-back) multi-organization probe and a
# backup/restore drill. Optionally runs the secret scan (gate for Etapa 0).
#
# Usage:
#   bash scripts/pilot-check.sh
#   DB=ai_eval bash scripts/pilot-check.sh
#   SECRET_SCAN=1 bash scripts/pilot-check.sh
#
# Environment:
#   DB                    Odoo database (default: odoo)
#   RESTORE_DB            Scratch database for the drill (default: <DB>_restore_check)
#   DOCKER_COMPOSE        Compose command (default: docker compose)
#   SECRET_SCAN           "1" to run the secret scan, otherwise skipped
#   SECRET_SCAN_PATHS     Space-separated paths for the secret scan
#
# The restore drill dumps the database, restores it into RESTORE_DB, copies the
# filestore, loads the Odoo registry and compares counts. The scratch database
# and filestore copy are always removed on exit.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="${DB:-odoo}"
RESTORE_DB="${RESTORE_DB:-${DB}_restore_check}"
DOCKER_COMPOSE="${DOCKER_COMPOSE:-docker compose}"
ADDONS_PATH="/mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons"
SECRET_SCAN="${SECRET_SCAN:-0}"
SECRET_SCAN_PATHS="${SECRET_SCAN_PATHS:-. ../invoice-item-extractor ../facturas-backend-UNC-PSI ../ocr-scripts}"

failures=0
skipped=0
dump_file=""

if ! [[ "$DB" =~ ^[A-Za-z0-9_]+$ ]] || ! [[ "$RESTORE_DB" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "DB and RESTORE_DB must contain only letters, digits and underscores." >&2
    exit 2
fi

ok() { printf '  %-30s OK    %s\n' "$1" "$2"; }
fail() {
    printf '  %-30s FAIL  %s\n' "$1" "$2"
    failures=$((failures + 1))
}
skip() {
    printf '  %-30s SKIP  %s\n' "$1" "$2"
    skipped=$((skipped + 1))
}

psql_db() {
    $DOCKER_COMPOSE exec -T db psql -U odoo -d "$DB" -Atc "$1" 2>/dev/null
}

run_odoo_shell() {
    local database="$1"
    local script="$2"
    printf '%s\n' "$script" | $DOCKER_COMPOSE exec -T web odoo shell \
        -d "$database" \
        --addons-path="$ADDONS_PATH" \
        --db_host=db --db_user=odoo --db_password=odoo \
        --no-http 2>&1
}

cleanup() {
    $DOCKER_COMPOSE exec -T db dropdb -U odoo --if-exists --force \
        "$RESTORE_DB" >/dev/null 2>&1 || true
    $DOCKER_COMPOSE exec -T web sh -c \
        "rm -rf /var/lib/odoo/filestore/$RESTORE_DB" >/dev/null 2>&1 || true
    [ -n "$dump_file" ] && rm -f "$dump_file"
}
trap cleanup EXIT INT TERM

echo "Pilot readiness check — database: $DB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ---------------------------------------------------------------------------
# 1. Services and database
# ---------------------------------------------------------------------------
running_services="$($DOCKER_COMPOSE ps --status running --services 2>/dev/null || true)"
missing_services=""
for service in db web; do
    grep -qx "$service" <<<"$running_services" || missing_services="$missing_services $service"
done
if [ -z "$missing_services" ]; then
    ok "Services" "db, web running"
else
    fail "Services" "not running:$missing_services (run: make up)"
fi

if printf '%s\n' "$(psql_db "SELECT 1 FROM pg_database WHERE datname = '$DB'")" | grep -qx 1; then
    ok "Database" "$DB exists"
else
    fail "Database" "$DB not found (create it or set DB=...)"
fi

# ---------------------------------------------------------------------------
# 2. Required modules
# ---------------------------------------------------------------------------
required_modules="account_invoice_ai_evaluation account_invoice_ai_platform l10n_ar_factura_items l10n_ar_factura_qr"
installed_modules="$(psql_db "SELECT name FROM ir_module_module WHERE state = 'installed' AND name IN ('account_invoice_ai_evaluation', 'account_invoice_ai_platform', 'l10n_ar_factura_items', 'l10n_ar_factura_qr')")"
missing_modules=""
for module in $required_modules; do
    grep -qx "$module" <<<"$installed_modules" || missing_modules="$missing_modules $module"
done
if [ -z "$missing_modules" ]; then
    ok "Modules" "$required_modules"
else
    fail "Modules" "not installed:$missing_modules"
fi

# ---------------------------------------------------------------------------
# 3. Record rules, private attachments, live isolation probe
# ---------------------------------------------------------------------------
read -r -d '' CHECK_SCRIPT <<'PY'
import time

MODELS = [
    'account.invoice.ai.organization',
    'account.invoice.ai.document',
    'account.invoice.ai.run',
    'account.invoice.ai.line',
    'account.invoice.ai.prediction',
    'account.invoice.ai.validation',
    'account.invoice.ai.annotation',
    'account.invoice.ai.annotation.line',
    'account.invoice.ai.export',
    'account.invoice.ai.batch',
    'account.invoice.ai.correction',
]

rule_errors = []
for model in MODELS:
    rules = env['ir.rule'].search(
        [('model_id.model', '=', model), ('active', '=', True)]
    )
    domains = [(rule.domain_force or '').replace(' ', '') for rule in rules]
    if not any('ai_organization_ids' in domain for domain in domains):
        rule_errors.append('%s:no-org-rule' % model)
    if not any("(1,'=',1)" in domain for domain in domains):
        rule_errors.append('%s:no-manager-rule' % model)
print('PILOT|rules|%s|%d' % (','.join(rule_errors) or 'OK', len(MODELS)))

documents = env['account.invoice.ai.document'].search([])
attachment_errors = []
readable = 0
for document in documents:
    attachment = document.original_attachment_id
    if not attachment:
        continue
    if attachment.public or attachment.access_token:
        attachment_errors.append('%s:public-or-token' % attachment.id)
    elif (
        attachment.res_model != 'account.invoice.ai.document'
        or attachment.res_id != document.id
    ):
        attachment_errors.append('%s:not-document-owned' % attachment.id)
    else:
        try:
            data = attachment.datas
        except Exception:
            data = False
        if data:
            readable += 1
        else:
            attachment_errors.append('%s:unreadable' % attachment.id)
print(
    'PILOT|attachments|%s|documents=%d|readable=%d'
    % (','.join(attachment_errors) or 'OK', len(documents), readable)
)

probe_errors = []
try:
    stamp = str(int(time.time()))
    company_a = env.company
    org_a = env['account.invoice.ai.organization'].create(
        {
            'name': 'Pilot probe A %s' % stamp,
            'agreement_signed': True,
            'agreement_date': '2026-01-01',
            'consent_storage': 'granted',
            'consent_evaluation': 'granted',
            'company_ids': [(6, 0, [company_a.id])],
        }
    )
    company_a.ai_organization_id = org_a.id
    company_b = env['res.company'].create(
        {'name': 'Pilot probe B %s' % stamp, 'currency_id': company_a.currency_id.id}
    )
    org_b = env['account.invoice.ai.organization'].create(
        {
            'name': 'Pilot probe B %s' % stamp,
            'agreement_signed': True,
            'agreement_date': '2026-01-01',
            'consent_storage': 'granted',
            'consent_evaluation': 'granted',
            'company_ids': [(6, 0, [company_b.id])],
        }
    )
    company_b.ai_organization_id = org_b.id
    base_group = env.ref('base.group_user')
    user_group = env.ref(
        'account_invoice_ai_evaluation.group_ai_evaluation_user'
    )

    def make_user(login, company, organization):
        return env['res.users'].create(
            {
                'name': login,
                'login': login,
                'email': '%s@example.invalid' % login,
                'group_ids': [(6, 0, [base_group.id, user_group.id])],
                'company_id': company.id,
                'company_ids': [(6, 0, [company.id])],
                'ai_organization_ids': [(6, 0, [organization.id])],
            }
        )

    user_a = make_user('pilot_probe_a_%s' % stamp, company_a, org_a)
    user_b = make_user('pilot_probe_b_%s' % stamp, company_b, org_b)
    document_a = env['account.invoice.ai.document'].create(
        {
            'name': 'Pilot probe A %s' % stamp,
            'organization_id': org_a.id,
            'company_id': company_a.id,
        }
    )
    document_b = env['account.invoice.ai.document'].create(
        {
            'name': 'Pilot probe B %s' % stamp,
            'organization_id': org_b.id,
            'company_id': company_b.id,
        }
    )

    if not document_a.with_user(user_a).has_access('read'):
        probe_errors.append('own-document-not-readable')
    if document_b.with_user(user_a).has_access('read'):
        probe_errors.append('other-org-document-readable')
    if document_a.with_user(user_b).has_access('read'):
        probe_errors.append('other-org-document-readable-reverse')
    visible_orgs = (
        env['account.invoice.ai.organization'].with_user(user_a).search([])
    )
    if org_a not in visible_orgs:
        probe_errors.append('own-org-not-visible')
    if org_b in visible_orgs:
        probe_errors.append('other-org-visible')
except Exception as error:
    probe_errors.append('exception:%s' % type(error).__name__)
finally:
    env.cr.rollback()

print('PILOT|isolation|%s' % (','.join(probe_errors) or 'OK'))

orgs = env['account.invoice.ai.organization'].search_count([])
active_orgs = env['account.invoice.ai.organization'].search_count(
    [('active', '=', True)]
)
users = env['res.users'].search_count(
    [('ai_organization_ids', '!=', False), ('share', '=', False)]
)
batches = env['account.invoice.ai.batch'].search_count([])
annotations = env['account.invoice.ai.annotation'].search_count([])
print(
    'PILOT|coverage|orgs=%d|active_orgs=%d|users=%d|batches=%d'
    % (orgs, active_orgs, users, batches)
)
print(
    'PILOT|source|documents=%d|batches=%d|annotations=%d'
    % (len(documents), batches, annotations)
)
PY

shell_output="$(run_odoo_shell "$DB" "$CHECK_SCRIPT")"

rules_line="$(grep '^PILOT|rules|' <<<"$shell_output" | tail -1)"
if [[ "$rules_line" == PILOT\|rules\|OK\|* ]]; then
    ok "Record rules" "$(cut -d'|' -f4 <<<"$rules_line") AI models covered"
else
    fail "Record rules" "${rules_line:-no output from Odoo shell}"
fi

attachments_line="$(grep '^PILOT|attachments|' <<<"$shell_output" | tail -1)"
if [[ "$attachments_line" == PILOT\|attachments\|OK\|* ]]; then
    ok "Private attachments" "$(cut -d'|' -f4- <<<"$attachments_line")"
else
    fail "Private attachments" "${attachments_line:-no output from Odoo shell}"
fi

isolation_line="$(grep '^PILOT|isolation|' <<<"$shell_output" | tail -1)"
if [ "$isolation_line" = "PILOT|isolation|OK" ]; then
    ok "Isolation probe" "temporary orgs rolled back"
else
    fail "Isolation probe" "${isolation_line:-no output from Odoo shell}"
fi

coverage_line="$(grep '^PILOT|coverage|' <<<"$shell_output" | tail -1)"
if [ -n "$coverage_line" ]; then
    if [[ "$coverage_line" =~ orgs=([0-9]+)\|active_orgs=([0-9]+)\|users=([0-9]+)\|batches=([0-9]+) ]]; then
        active_orgs="${BASH_REMATCH[2]}"
        users="${BASH_REMATCH[3]}"
        if [ "$active_orgs" -ge 2 ]; then
            ok "Pilot data" "$active_orgs active organizations, $users platform users"
        else
            skip "Pilot data" "$active_orgs active organization(s) — formal pilot needs 2–3"
        fi
    fi
else
    fail "Pilot data" "no output from Odoo shell"
fi

# ---------------------------------------------------------------------------
# 4. Backup/restore drill
# ---------------------------------------------------------------------------
source_line="$(grep '^PILOT|source|' <<<"$shell_output" | tail -1)"
source_documents="$(sed -n 's/.*documents=\([0-9]*\).*/\1/p' <<<"$source_line")"
source_batches="$(sed -n 's/.*batches=\([0-9]*\).*/\1/p' <<<"$source_line")"
source_annotations="$(sed -n 's/.*annotations=\([0-9]*\).*/\1/p' <<<"$source_line")"

restore_ok=1
restore_detail=""
dump_file="$(mktemp /tmp/pilot-check-XXXXXX.dump)"

if ! $DOCKER_COMPOSE exec -T db pg_dump -U odoo -d "$DB" -Fc >"$dump_file" 2>/dev/null; then
    restore_ok=0
    restore_detail="pg_dump failed"
elif [ ! -s "$dump_file" ]; then
    restore_ok=0
    restore_detail="empty dump"
fi

if [ "$restore_ok" -eq 1 ]; then
    if ! $DOCKER_COMPOSE exec -T db dropdb -U odoo --if-exists --force \
        "$RESTORE_DB" >/dev/null 2>&1; then
        restore_ok=0
        restore_detail="could not drop $RESTORE_DB"
    elif ! $DOCKER_COMPOSE exec -T db createdb -U odoo \
        "$RESTORE_DB" >/dev/null 2>&1; then
        restore_ok=0
        restore_detail="could not create $RESTORE_DB"
    elif ! $DOCKER_COMPOSE exec -T db pg_restore -U odoo -d "$RESTORE_DB" \
        --no-owner <"$dump_file" >/dev/null 2>&1; then
        restore_ok=0
        restore_detail="pg_restore failed"
    fi
fi

if [ "$restore_ok" -eq 1 ]; then
    $DOCKER_COMPOSE exec -T web sh -c \
        "if [ -d /var/lib/odoo/filestore/$DB ]; then rm -rf /var/lib/odoo/filestore/$RESTORE_DB && cp -a /var/lib/odoo/filestore/$DB /var/lib/odoo/filestore/$RESTORE_DB; fi" \
        >/dev/null 2>&1 || true

    read -r -d '' RESTORE_SCRIPT <<'PY'
documents = env['account.invoice.ai.document'].search([])
bad_attachments = 0
for document in documents:
    attachment = document.original_attachment_id
    if attachment and not attachment.datas:
        bad_attachments += 1
print(
    'PILOT|restore|documents=%d|batches=%d|annotations=%d|bad_attachments=%d'
    % (
        len(documents),
        env['account.invoice.ai.batch'].search_count([]),
        env['account.invoice.ai.annotation'].search_count([]),
        bad_attachments,
    )
)
PY

    restore_output="$(run_odoo_shell "$RESTORE_DB" "$RESTORE_SCRIPT")"
    restore_line="$(grep '^PILOT|restore|' <<<"$restore_output" | tail -1)"
    if [[ "$restore_line" =~ documents=([0-9]+)\|batches=([0-9]+)\|annotations=([0-9]+)\|bad_attachments=([0-9]+) ]]; then
        restore_documents="${BASH_REMATCH[1]}"
        restore_batches="${BASH_REMATCH[2]}"
        restore_annotations="${BASH_REMATCH[3]}"
        restore_bad="${BASH_REMATCH[4]}"
        if [ "$restore_documents" != "$source_documents" ] ||
            [ "$restore_batches" != "$source_batches" ] ||
            [ "$restore_annotations" != "$source_annotations" ]; then
            restore_ok=0
            restore_detail="count mismatch: source ${source_documents}/${source_batches}/${source_annotations}, restored ${restore_documents}/${restore_batches}/${restore_annotations}"
        elif [ "$restore_bad" != "0" ]; then
            restore_ok=0
            restore_detail="$restore_bad attachment(s) unreadable after restore"
        else
            restore_detail="documents=$restore_documents, batches=$restore_batches, attachments readable"
        fi
    else
        restore_ok=0
        restore_detail="${restore_line:-could not load restored database}"
    fi
fi

if [ "$restore_ok" -eq 1 ]; then
    ok "Backup/restore drill" "$restore_detail"
else
    fail "Backup/restore drill" "$restore_detail"
fi

# ---------------------------------------------------------------------------
# 5. Secret scan (Etapa 0 gate)
# ---------------------------------------------------------------------------
if [ "$SECRET_SCAN" = "1" ]; then
    scan_paths=($SECRET_SCAN_PATHS)
    if bash "$ROOT/scripts/secret-scan.sh" "${scan_paths[@]}" >/tmp/pilot-secret-scan.log 2>&1; then
        ok "Secret scan" "${#scan_paths[@]} path(s), no leaks"
    else
        fail "Secret scan" "findings or scan error (see /tmp/pilot-secret-scan.log)"
    fi
else
    skip "Secret scan" "set SECRET_SCAN=1 (Etapa 0 gate)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$failures" -eq 0 ]; then
    echo "PASS: $skipped check(s) skipped, 0 failed."
    exit 0
fi
echo "FAIL: $failures check(s) failed, $skipped skipped."
exit 1
