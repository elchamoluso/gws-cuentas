# shellcheck shell=bash
# tests/comun.sh — sandbox y utilidades compartidas por los tests (sin red, sin tocar el
# $HOME real). Monta un árbol que imita el Drive de ChromeOS, un HOME temporal y una
# configuración con tres cuentas.
set -u
kit=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME=$T/home GCUENTAS_CONF=$T/cuentas.conf GCUENTAS_CACHE=$T/cache
unset GCUENTA GCUENTAS_VERBOSE
D=$T/mnt/shared/GoogleDrive
FORM=$D/SharedDrives/Formación
ASOC="$D/SharedDrives/Asociación Local"
mkdir -p "$D/MyDrive/a" "$FORM/01-sub/x/y" "$ASOC/02 comites/y z" "$D/SharedDrives/Empresa" \
    "$HOME/dev/asociacion/asociacion-ds/sub" "$HOME/dev/asociacion-dsx" "$HOME/dev/formacion/curso" "$T/mnt/chromeos" "$T/fuera"
ln -s ../shared "$T/mnt/chromeos/shared"
ln -s asociacion/asociacion-ds "$HOME/dev/asociacion-ds"
cat >"$GCUENTAS_CONF" <<CONF
# configuración de prueba
maquina|prueba
cuenta|empresa|admin@empresa.example|proy-empresa|workspace
cuenta|asociacion|Admin@Asociacion.example||workspace
cuenta|personal|yo@gmail.com||personal
defecto|empresa
ruta|$FORM|personal
ruta|  $ASOC  |asociacion
ruta|~/dev/formacion|personal
ruta|\$HOME/dev/asociacion/|asociacion
ruta|$FORM/01-sub/x|asociacion
conectores|personal
CONF

pasa=0
falla=0
esperar() { # esperar <descripción> <esperado> <obtenido>
    if [ "$3" = "$2" ]; then
        pasa=$((pasa + 1))
        printf '  ✓ %s\n' "$1"
    else
        falla=$((falla + 1))
        printf '  ✗ %s\n      esperado: «%s»\n      obtenido: «%s»\n' "$1" "$2" "$3"
    fi
}
contiene() { # contiene <descripción> <aguja> <pajar>
    case $3 in
        *"$2"*) pasa=$((pasa + 1)); printf '  ✓ %s\n' "$1" ;;
        *) falla=$((falla + 1)); printf '  ✗ %s\n      no contiene: «%s»\n      en: «%s»\n' "$1" "$2" "$3" ;;
    esac
}
resumen() {
    printf '\n%d bien, %d mal\n' "$pasa" "$falla"
    [ "$falla" -eq 0 ]
}
