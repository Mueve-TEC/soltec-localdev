#!/bin/bash

RUTA_ORIGEN="./submodules/"
RUTA_DESTINO="./custom-addons/"
EXCLUIR="./exclude.txt"

# Iterar sobre cada subdirectorio en ./submodules
for dir in "$RUTA_ORIGEN"*/; do
  echo "Copiando desde $dir a $RUTA_DESTINO"
  rsync -av --exclude-from="$EXCLUIR" "$dir" "$RUTA_DESTINO"
done
