#!/bin/bash

RUTA_ORIGEN="./submodules/"
RUTA_DESTINO="./custom-addons/"
EXCLUIR="./exclude.txt"

# Buscar recursivamente directorios que sean módulos de Odoo (contienen __manifest__.py)
find "$RUTA_ORIGEN" -type f -name "__manifest__.py" -print0 | while IFS= read -r -d '' manifest; do
  dir=$(dirname "$manifest")
  echo "Copiando módulo desde $dir a $RUTA_DESTINO"
  rsync -av --exclude-from="$EXCLUIR" "$dir" "$RUTA_DESTINO"
done
