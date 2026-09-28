#!/bin/bash
set -euo pipefail

BACKUP="${1:-}"
DB_NAME="${2:-CooperativaElEspinillo}"

if [ -z "$BACKUP" ] || [ ! -f "$BACKUP" ]; then
  echo "Uso: bash docker/restore_db.sh <backup.zip> [nombre_db]"
  echo "Ej : bash docker/restore_db.sh CooperativaElEspinillo_2026-09-28_13-29-22.zip CooperativaElEspinillo"
  exit 1
fi

echo "Backup : $BACKUP"
echo "Base   : $DB_NAME"
echo

if [ "${FORCE:-0}" != "1" ]; then
  read -r -p "Se va a DROPEAR la base '$DB_NAME' en el contenedor. Continuar? [s/N] " ans
  case "$ans" in
    s|S|si|SI|Si|y|Y) ;;
    *) echo "Cancelado."; exit 1 ;;
  esac
fi

if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
else
  DC="docker-compose"
fi

WEB=$($DC ps -q web)
DB=$($DC ps -q db)
if [ -z "$WEB" ] || [ -z "$DB" ]; then
  echo "Los contenedores no estan corriendo. Ejecuta primero: $DC up -d"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo ">> Extrayendo backup..."
unzip -q "$BACKUP" -d "$TMP"
if [ ! -f "$TMP/dump.sql" ]; then
  echo "El backup no contiene dump.sql"
  exit 1
fi

echo ">> Recreando la base '$DB_NAME'..."
docker exec "$DB" psql -U odoo -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS \"$DB_NAME\" WITH (FORCE);" \
  -c "CREATE DATABASE \"$DB_NAME\" OWNER odoo;"

echo ">> Importando dump.sql (psql del contenedor web)..."
sed '/^SET transaction_timeout = 0;/d' "$TMP/dump.sql" | \
  docker exec -i -e PGPASSWORD=odoo "$WEB" \
  psql -h db -U odoo -d "$DB_NAME" -q -v ON_ERROR_STOP=0

echo ">> Restaurando filestore..."
docker exec "$WEB" rm -rf "/var/lib/odoo/filestore/$DB_NAME"
docker exec "$WEB" mkdir -p "/var/lib/odoo/filestore/$DB_NAME"
if [ -d "$TMP/filestore" ]; then
  docker cp "$TMP/filestore/." "$WEB:/var/lib/odoo/filestore/$DB_NAME/"
fi

echo ">> Neutralizando la base (evita mails y llamadas AFIP productivas)..."
docker exec "$WEB" odoo neutralize -d "$DB_NAME" \
  --db_host=db --db_user=odoo --db_password=odoo \
  --addons-path=/mnt/custom-addons,/mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons \
  || echo "ADVERTENCIA: no se pudo neutralizar, revisar manualmente."

echo ">> Reiniciando el servicio web..."
$DC restart web >/dev/null

echo
echo "Listo. Base '$DB_NAME' restaurada desde '$BACKUP'."
