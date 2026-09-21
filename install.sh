#!/usr/bin/env bash
# install.sh — instala gws-cuentas en esta máquina. Se puede repetir sin miedo.
#
#   ./install.sh                instala o actualiza
#   ./install.sh --desinstalar  quita shims, hook y skill (no toca credenciales ni cepos)
#
# Qué hace:
#   1. Crea un espacio por cuenta y herramienta (~/.config/{gws,gcloud,clasp}-<id>, 700).
#   2. Pone los cepos: ~/.config/gws y ~/.config/gcloud pasan a ser ficheros vacíos con modo
#      000, para que nada use esas rutas por defecto sin pasar por el shim.
#   3. Enlaza en ~/.local/bin el shim como gws, gcloud, gsutil, bq y clasp, y gcuenta.
#   4. Prepara el navegador compartido (un perfil de Chromium con las sesiones de todas las
#      cuentas; agent-browser se conecta a él por CDP).
#   5. Enlaza la skill google-cuentas y añade el hook SessionStart a ~/.claude/settings.json.
set -euo pipefail

kit=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
BIN=$HOME/.local/bin
CONF_DIR=$HOME/.config/gws-cuentas
CONF=$CONF_DIR/cuentas.conf
SETTINGS=$HOME/.claude/settings.json
SKILLS=$HOME/.claude/skills
HERRAMIENTAS=(gws gcloud gsutil bq clasp)

paso() { printf '→ %s\n' "$*"; }
aviso() { printf '⚠ %s\n' "$*" >&2; }
fallo() {
    printf '✗ %s\n' "$*" >&2
    exit 1
}

enlazar() { # enlazar <destino> <enlace> — nunca pisa un fichero real
    local destino=$1 enlace=$2
    if [ -L "$enlace" ] || [ ! -e "$enlace" ]; then
        ln -sfn "$destino" "$enlace"
    else
        fallo "$enlace existe y no es un symlink; no lo piso (muévelo y repite)"
    fi
}

hook_settings() { # hook_settings <poner|quitar>
    mkdir -p "$(dirname "$SETTINGS")"
    # «~» y no la ruta absoluta: el hook se ejecuta en una shell, y así un HOME con espacios
    # no rompe el comando.
    python3 -I - "$SETTINGS" "$1" '~/.local/bin/gcuenta hook' <<'PY'
import json, os, shutil, sys
ruta, accion, comando = sys.argv[1:]
# Si settings.json es un symlink (dotfiles), se edita el fichero real y el enlace se conserva.
ruta = os.path.realpath(ruta)
datos = {}
if os.path.exists(ruta):
    with open(ruta) as f:
        datos = json.load(f)
    shutil.copy2(ruta, ruta + ".bak-gws-cuentas")
hooks = datos.setdefault("hooks", {})
grupos = []
for grupo in hooks.get("SessionStart", []):
    propios = [h for h in grupo.get("hooks", []) if "gcuenta hook" not in h.get("command", "")]
    if propios:
        g = dict(grupo)
        g["hooks"] = propios
        grupos.append(g)
if accion == "poner":
    # Sin matcher: cubre inicio, reanudación, /clear y compactación.
    grupos.append({"hooks": [{"type": "command", "command": comando, "timeout": 10}]})
if grupos:
    hooks["SessionStart"] = grupos
else:
    hooks.pop("SessionStart", None)
if not hooks:
    datos.pop("hooks", None)
tmp = ruta + ".tmp"
with open(tmp, "w") as f:
    json.dump(datos, f, indent=2, ensure_ascii=False)
    f.write("\n")
if os.path.exists(ruta):
    shutil.copymode(ruta, tmp)
os.replace(tmp, ruta)
PY
}

cepo() { # cepo <ruta> — la deja como fichero vacío con modo 000
    local p=$1 respaldo
    if [ -f "$p" ] && [ ! -s "$p" ]; then
        chmod 000 "$p"
        return
    fi
    if [ -d "$p" ]; then
        if find "$p" -type f \( -name 'credentials*' -o -name '*.enc' -o -name '.encryption_key' \
            -o -name 'access_tokens.db' -o -name 'application_default_credentials.json' \
            -o -name 'client_secret*.json' -o -name 'legacy_credentials' \) 2>/dev/null | grep -q .; then
            fallo "$p contiene credenciales; muévelas al espacio de su cuenta antes de instalar"
        fi
        respaldo=$HOME/.cache/gws-cuentas/respaldo-$(date +%Y%m%d-%H%M%S)
        mkdir -p "$respaldo"
        mv "$p" "$respaldo/"
        aviso "$p era una carpeta sin credenciales (logs, cachés); movida a $respaldo"
    elif [ -e "$p" ] || [ -L "$p" ]; then
        fallo "$p existe y no es ni carpeta ni fichero vacío; revísalo a mano"
    fi
    : >"$p"
    chmod 000 "$p"
}

desinstalar() {
    local h
    for h in "${HERRAMIENTAS[@]}" gcuenta gcuenta-abrir; do
        if [ -L "$BIN/$h" ] && [[ $(readlink -f "$BIN/$h") == "$kit"/* ]]; then
            rm -f "$BIN/$h"
            paso "quitado $BIN/$h"
        fi
    done
    if [ -L "$SKILLS/google-cuentas" ]; then rm -f "$SKILLS/google-cuentas"; paso "quitada la skill"; fi
    [ -f "$SETTINGS" ] && hook_settings quitar && paso "quitado el hook de $SETTINGS"
    echo "Hecho. Credenciales, espacios y cepos siguen en su sitio (bórralos a mano si quieres)."
}

[ "${1:-}" = --desinstalar ] && { desinstalar; exit 0; }

# 0. Requisitos
for c in python3 realpath setsid grep find; do
    command -v "$c" >/dev/null 2>&1 || fallo "falta «$c»"
done

# 1. Configuración de esta máquina
mkdir -p "$CONF_DIR" && chmod 700 "$CONF_DIR"
if [ ! -f "$CONF" ]; then
    install -m 600 "$kit/config/cuentas.example.conf" "$CONF"
    echo "He creado $CONF a partir del ejemplo."
    echo "Edítalo con tus cuentas, carpetas y proyectos, y vuelve a ejecutar ./install.sh"
    exit 0
fi
chmod 600 "$CONF"
export GCUENTAS_CONF=$CONF
# shellcheck source=lib/cuentas.sh
. "$kit/lib/cuentas.sh"
cuentas_cargar || fallo "la configuración $CONF tiene errores"
paso "configuración: ${#CUENTAS_IDS[@]} cuentas (${CUENTAS_IDS[*]}), defecto $CUENTA_DEFECTO"

# 2. Espacios por cuenta
for d in "$HOME/.cache/gws-cuentas" "$(dirname "$GC_NAV_PERFIL")" "$GC_NAV_PERFIL" \
    "$HOME/.local/share/gws-cuentas" "$HOME/.local/share/gws-cuentas/descargas"; do
    mkdir -p "$d"
    chmod 700 "$d"
done
for id in "${CUENTAS_IDS[@]}"; do
    cuentas_dirs "$id"
    for d in "$GC_GWS_DIR" "$GC_GCLOUD_DIR" "$GC_CLASP_DIR"; do
        mkdir -p "$d"
        chmod 700 "$d"
    done
    for f in "$GC_GWS_DIR"/client_secret.json "$GC_GWS_DIR"/credentials.enc "$GC_GWS_DIR"/.encryption_key "$GC_CLASP_AUTH"; do
        [ -f "$f" ] && chmod 600 "$f"
    done
    paso "espacios de $id listos"
done
paso "navegador compartido: perfil $GC_NAV_PERFIL, puerto $GC_NAV_PUERTO (solo localhost)"

# 3. Cepos
cepo "$HOME/.config/gws"
cepo "$HOME/.config/gcloud"
paso "cepos en ~/.config/gws y ~/.config/gcloud"

# 4. Shims y comandos
mkdir -p "$BIN"
for h in "${HERRAMIENTAS[@]}"; do enlazar "$kit/bin/cuenta-shim" "$BIN/$h"; done
enlazar "$kit/bin/gcuenta" "$BIN/gcuenta"
enlazar "$kit/bin/gcuenta-abrir" "$BIN/gcuenta-abrir"
paso "shims en $BIN: ${HERRAMIENTAS[*]}, gcuenta"
case ":$PATH:" in
    *":$BIN:"*) ;;
    *) aviso "$BIN no está en el PATH de esta shell: añádelo delante (export PATH=\"\$HOME/.local/bin:\$PATH\")" ;;
esac
for h in "${HERRAMIENTAS[@]}"; do
    r=$(command -v "$h" || true)
    [ "$r" = "$BIN/$h" ] || aviso "«$h» resuelve a «$r» en esta shell, no al shim: pon $BIN delante en el PATH"
done

# 5. Claude Code
mkdir -p "$SKILLS"
enlazar "$kit/skill/google-cuentas" "$SKILLS/google-cuentas"
hook_settings poner
paso "skill google-cuentas y hook SessionStart en $SETTINGS"

echo
"$kit/bin/gcuenta" doctor || true
cat <<EOF

Siguientes pasos (una vez por cuenta; ver README):
  gcuenta entrar <id>          iniciar sesión en Google con esa cuenta (navegador compartido; no lo cierres)
  gcuenta login <id> gcloud    el «gcloud init» de esa cuenta
  (cliente OAuth Desktop «gws-${GCUENTAS_MAQUINA:-<maquina>}», el mismo nombre en todas las cuentas → ~/.config/gws-<id>/client_secret.json)
  gcuenta login <id> gws
  gcuenta login <id> clasp
  gcuenta estado --todas
EOF
