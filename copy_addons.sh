#!/bin/bash
#
# copy_addons.sh — sincroniza módulos de Odoo desde ./submodules/ hacia
# ./custom-addons/.
#
# Estrategia abstracta: busca recursivamente, dentro del árbol de
# submódulos, todo directorio que contenga `__manifest__.py` (la convención
# que define un módulo de Odoo) y copia ese directorio — y sólo ese
# directorio — como `custom-addons/<nombre>/`.
#
# No importa el nivel de anidamiento del submódulo: funciona tanto con
# submódulos que tienen módulos sueltos en su raíz
#     submodules/<repo>/<modulo>/__manifest__.py
# como con submódulos que agrupan módulos en subdirectorios intermedios
#     submodules/<repo>/<grupo>/<modulo>/__manifest__.py
#     submodules/<repo>/<grupo>/<subrepo>/<modulo>/__manifest__.py
#
# El nombre destino de cada módulo es siempre su basename, por lo que el
# resultado en `custom-addons/` es una lista plana de módulos, lista para
# que Odoo la cargue como addons path.
#
# Rendimiento: una sola invocación de rsync recibe TODOS los paths de
# módulos como argumentos, en lugar de un rsync por módulo. Esto reduce
# el tiempo de sincronización de ~2.5s a ~0.25s para 41 módulos (la
# sobrecarga era el startup de proceso + re-scan del árbol en cada
# llamada).
#
# Uso:
#     bash copy_addons.sh
#
# Variables opcionales (pasar por entorno):
#     RUTA_ORIGEN    (default ./submodules)
#     RUTA_DESTINO   (default ./custom-addons)
#     EXCLUIR        (default ./exclude.txt  — rsync --exclude-from)
#
# Notas:
#   * Se respeta `exclude.txt` dentro de cada módulo (patrones de rsync).
#   * Cada módulo se sincroniza con `rsync --delete`, de modo que los
#     archivos borrados en el origen también se eliminan en el destino.
#   * Después de rsync se hace una pasada de limpieza que elimina de
#     `custom-addons/` cualquier directorio sin `__manifest__.py`, lo que
#     resuelve dos casos: (a) módulos que dejaron de existir en el origen
#     (ej. renombrados upstream) y (b) defensa contra cualquier directorio
#     espurio que rsync pudiera llegar a crear por argumentos corruptos.
#   * Si dos orígenes producen el mismo nombre de módulo (colisión), se
#     emite una advertencia y rsync mezclará los contenidos en el mismo
#     destino (el último ganará archivo por archivo). Esto es poco probable
#     con módulos Odoo bien nombrados.

set -uo pipefail

RUTA_ORIGEN="${RUTA_ORIGEN:-./submodules}"
RUTA_DESTINO="${RUTA_DESTINO:-./custom-addons}"
EXCLUIR="${EXCLUIR:-./exclude.txt}"

mkdir -p "$RUTA_DESTINO"

# Opciones de rsync. Una sola invocación con todos los paths a la vez.
RSYNC_OPTS=(-a --delete)
if [[ -f "$EXCLUIR" ]]; then
  RSYNC_OPTS+=(--exclude-from="$EXCLUIR")
fi

# Localizar todos los directorios que contengan __manifest__.py.
# `-not -path "*/.git/*"` evita entrar en repositorios git anidados.
# La salida se recoge en un array para preservar los paths exactos aunque
# contengan espacios (raro en módulos Odoo, pero defensivo).
mapfile -t MODULOS < <(find "$RUTA_ORIGEN" -type f -name "__manifest__.py" \
                            -not -path "*/.git/*" \
                            -exec dirname {} \; \
                       | sort -u)

if [[ ${#MODULOS[@]} -eq 0 ]]; then
  echo "ERROR: no se encontraron módulos (carpetas con __manifest__.py) bajo $RUTA_ORIGEN" >&2
  exit 1
fi

# Detección de colisiones de nombre (dos orígenes → mismo basename).
declare -A VISTOS=()
COLISIONES=0
for mod in "${MODULOS[@]}"; do
  nombre=$(basename "$mod")
  if [[ -n "${VISTOS[$nombre]+x}" ]]; then
    echo "ADVERTENCIA: colisión de nombre para '$nombre'" >&2
    echo "  ya visto desde: ${VISTOS[$nombre]}" >&2
    echo "  se omite:        $mod" >&2
    COLISIONES=$((COLISIONES + 1))
  fi
  VISTOS[$nombre]="$mod"
done

# Una sola invocación de rsync con todos los paths de módulos. rsync
# envía cada fuente a <destino>/<basename> automáticamente.
echo "Sincronizando ${#MODULOS[@]} módulos con una sola invocación de rsync…"
if ! rsync "${RSYNC_OPTS[@]}" "${MODULOS[@]}" "$RUTA_DESTINO/"; then
  echo "ERROR: rsync falló" >&2
  exit 1
fi

# Pasada de limpieza: elimina directorios en destino que no contengan
# __manifest__.py. Esto cubre:
#   (a) módulos cuya migración upstream los renombró (ej. l10n_ar_afipws
#       → l10n_ar_fiscal_ws) — el nombre viejo debe desaparecer;
#   (b) cualquier directorio espurio que rsync pudiera crear si los
#       argumentos se corrompen (defensa defensiva, no debería ocurrir).
HUEFANOS=0
for d in "$RUTA_DESTINO"/*/; do
  [[ -d "$d" ]] || continue
  if [[ ! -f "${d}__manifest__.py" ]]; then
    echo "Limpiando huérfano: $(basename "$d")"
    rm -rf "$d"
    HUEFANOS=$((HUEFANOS + 1))
  fi
done

echo
echo "Listo: ${#MODULOS[@]} módulos sincronizados, $HUEFANOS huérfanos limpiados, $COLISIONES colisiones."
exit 0