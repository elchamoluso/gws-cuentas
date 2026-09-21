# shellcheck shell=bash
# lib/cuentas.sh — configuración y resolución de cuentas de gws-cuentas.
#
# Lo sourcean bin/cuenta-shim y bin/gcuenta. No escribe nada en stdout: los avisos van a
# stderr y los resultados se dejan en variables globales (GC_*), para no depender de
# subshells que se comerían el estado.
#
# Formato de la configuración (una directiva por línea, campos separados por «|»):
#   maquina|<nombre>                                   → nombre de la credencial OAuth en todas las cuentas: gws-<maquina>
#   cuenta|<id>|<email>|<proyecto_gcp>|<workspace|personal>
#   defecto|<id>                                       → cuenta si ninguna ruta coincide
#   ruta|<prefijo>|<id>                                → carpeta (y todo lo que cuelga) → cuenta
#   conectores|<id>                                    → cuenta ligada a los conectores de claude.ai
#   navegador|<perfil>|<puerto>                        → Chromium compartido por todas las cuentas
#                                                        (por defecto ~/.agent-browser/perfiles/google y 9300)

GCUENTAS_CONF="${GCUENTAS_CONF:-$HOME/.config/gws-cuentas/cuentas.conf}"
GCUENTAS_CACHE="${GCUENTAS_CACHE:-$HOME/.cache/gws-cuentas}"

CUENTAS_IDS=()
declare -A CUENTA_EMAIL=() CUENTA_PROYECTO=() CUENTA_TIPO=()
RUTAS_PREFIJO=()
RUTAS_ID=()
CUENTA_DEFECTO=""
GCUENTAS_MAQUINA=""
GCUENTAS_CONECTORES=""
GC_NAV_PERFIL=""
GC_NAV_PUERTO=""

_gc_err() { printf 'gcuenta: %s\n' "$*" >&2; }

_gc_recortar() { # quita espacios al principio y al final, respeta los de dentro
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    printf '%s' "$s"
}

_gc_expandir() { # ~ y $HOME al principio de una ruta
    local p=$1
    case $p in
        "~") p=$HOME ;;
        "~/"*) p=$HOME/${p#"~/"} ;;
        '$HOME' | '${HOME}') p=$HOME ;;
        '$HOME/'*) p=$HOME/${p#'$HOME/'} ;;
        '${HOME}/'*) p=$HOME/${p#'${HOME}/'} ;;
    esac
    printf '%s' "$p"
}

cuenta_existe() {
    local id
    for id in "${CUENTAS_IDS[@]}"; do [ "$id" = "$1" ] && return 0; done
    return 1
}

cuentas_cargar() {
    if [ ! -r "$GCUENTAS_CONF" ]; then
        _gc_err "no encuentro la configuración $GCUENTAS_CONF (parte de config/cuentas.example.conf)"
        return 2
    fi
    local linea tipo a b c d n=0 id
    while IFS= read -r linea || [ -n "$linea" ]; do
        n=$((n + 1))
        linea=${linea%$'\r'}
        linea=$(_gc_recortar "$linea")
        case $linea in '' | '#'*) continue ;; esac
        IFS='|' read -r tipo a b c d <<<"$linea"
        tipo=$(_gc_recortar "$tipo"); a=$(_gc_recortar "$a"); b=$(_gc_recortar "$b")
        c=$(_gc_recortar "$c"); d=$(_gc_recortar "$d")
        case $tipo in
            maquina) GCUENTAS_MAQUINA=$a ;;
            cuenta)
                if ! [[ $a =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
                    _gc_err "$GCUENTAS_CONF:$n: id de cuenta no válido «$a» (minúsculas, cifras y guiones)"
                    return 2
                fi
                if cuenta_existe "$a"; then
                    _gc_err "$GCUENTAS_CONF:$n: cuenta «$a» repetida"
                    return 2
                fi
                if ! [[ $b =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]]; then
                    _gc_err "$GCUENTAS_CONF:$n: la cuenta «$a» necesita un email válido (tiene «$b»)"
                    return 2
                fi
                case ${d:-workspace} in workspace | personal) ;; *)
                    _gc_err "$GCUENTAS_CONF:$n: tipo «$d» no válido (workspace o personal)"
                    return 2 ;;
                esac
                CUENTAS_IDS+=("$a")
                CUENTA_EMAIL[$a]=$b
                CUENTA_PROYECTO[$a]=$c
                CUENTA_TIPO[$a]=${d:-workspace}
                ;;
            defecto) CUENTA_DEFECTO=$a ;;
            ruta)
                if [ -z "$a" ] || [ -z "$b" ]; then
                    _gc_err "$GCUENTAS_CONF:$n: la ruta necesita prefijo e id"
                    return 2
                fi
                a=$(_gc_expandir "$a")
                if [ "${a:0:1}" != / ]; then
                    _gc_err "$GCUENTAS_CONF:$n: el prefijo «$a» tiene que ser absoluto (o empezar por ~ o \$HOME)"
                    return 2
                fi
                local previo
                for previo in "${RUTAS_PREFIJO[@]}"; do
                    if [ "${previo%/}" = "${a%/}" ]; then
                        _gc_err "$GCUENTAS_CONF:$n: el prefijo «$a» está repetido"
                        return 2
                    fi
                done
                RUTAS_PREFIJO+=("$a")
                RUTAS_ID+=("$b")
                ;;
            conectores) GCUENTAS_CONECTORES=$a ;;
            navegador)
                GC_NAV_PERFIL=$(_gc_expandir "$a")
                GC_NAV_PUERTO=$b
                ;;
            *)
                _gc_err "$GCUENTAS_CONF:$n: directiva desconocida «$tipo»"
                return 2
                ;;
        esac
    done <"$GCUENTAS_CONF"

    if [ ${#CUENTAS_IDS[@]} -eq 0 ]; then
        _gc_err "$GCUENTAS_CONF: no hay ninguna línea «cuenta|…»"
        return 2
    fi
    if [ -z "$CUENTA_DEFECTO" ] || ! cuenta_existe "$CUENTA_DEFECTO"; then
        _gc_err "$GCUENTAS_CONF: «defecto|<id>» falta o apunta a una cuenta que no existe"
        return 2
    fi
    for id in "${RUTAS_ID[@]}"; do
        if ! cuenta_existe "$id"; then
            _gc_err "$GCUENTAS_CONF: una ruta apunta a la cuenta «$id», que no existe"
            return 2
        fi
    done
    GC_NAV_PERFIL=${GC_NAV_PERFIL:-${GCUENTAS_AB_BASE:-$HOME/.agent-browser}/perfiles/google}
    GC_NAV_PUERTO=${GC_NAV_PUERTO:-9300}
    if ! [[ $GC_NAV_PUERTO =~ ^[0-9]+$ ]]; then
        _gc_err "$GCUENTAS_CONF: el puerto del navegador «$GC_NAV_PUERTO» no es un número"
        return 2
    fi
    if [ -n "$GCUENTAS_CONECTORES" ] && ! cuenta_existe "$GCUENTAS_CONECTORES"; then
        _gc_err "$GCUENTAS_CONF: «conectores|$GCUENTAS_CONECTORES» no es una cuenta configurada"
        return 2
    fi
    return 0
}

# cuentas_resolver [ruta]
# Deja en GC_ID la cuenta y en GC_MOTIVO por qué se eligió.
#   - Sin ruta: manda GCUENTA si está definida; si no, la carpeta actual (pwd -P).
#   - Con ruta: solo cuenta la ruta (GCUENTA no interviene).
# Gana el prefijo más largo, y solo en el límite de carpeta: la regla …/asociacion no captura
# …/asociacion-ds. Los prefijos se canonicalizan con realpath, así que los symlinks
# (/mnt/chromeos/shared → /mnt/shared, ~/dev/atajo → otra/carpeta) no engañan.
cuentas_resolver() {
    local ruta=${1-}
    GC_ID="" GC_MOTIVO=""
    if [ -z "$ruta" ] && [ -n "${GCUENTA:-}" ]; then
        if ! cuenta_existe "$GCUENTA"; then
            _gc_err "GCUENTA=«$GCUENTA» no es una cuenta configurada (${CUENTAS_IDS[*]})"
            return 2
        fi
        GC_ID=$GCUENTA
        GC_MOTIVO="GCUENTA"
        return 0
    fi
    if [ -z "$ruta" ]; then
        # Sin carpeta actual (borrada) no se adivina: mejor fallar que usar otra cuenta.
        if ! ruta=$(pwd -P 2>/dev/null) || [ ! -d "$ruta" ]; then
            _gc_err "la carpeta actual ya no existe; no sé qué cuenta usar (entra en una carpeta o usa GCUENTA=<id>)"
            return 2
        fi
    else
        ruta=$(realpath -m -- "$ruta" 2>/dev/null) || ruta=""
    fi

    local -a canon=()
    if [ ${#RUTAS_PREFIJO[@]} -gt 0 ] && [ -n "$ruta" ]; then
        mapfile -d '' -t canon < <(realpath -m -z -- "${RUTAS_PREFIJO[@]}" 2>/dev/null)
    fi
    local i p mejor=-1 largo=-1
    for i in "${!canon[@]}"; do
        p=${canon[$i]%/}
        if [ "$ruta" = "$p" ] || [ -z "$p" ] || [[ $ruta == "$p"/* ]]; then
            if [ ${#p} -gt $largo ]; then
                mejor=$i
                largo=${#p}
            fi
        fi
    done
    if [ $mejor -ge 0 ]; then
        GC_ID=${RUTAS_ID[$mejor]}
        GC_MOTIVO="ruta ${RUTAS_PREFIJO[$mejor]}"
    else
        GC_ID=$CUENTA_DEFECTO
        GC_MOTIVO="defecto"
    fi
    return 0
}

# cuentas_dirs <id> → GC_GWS_DIR, GC_GCLOUD_DIR, GC_CLASP_DIR, GC_CLASP_AUTH
cuentas_dirs() {
    local id=$1 base=${GCUENTAS_CONFIG_BASE:-$HOME/.config}
    GC_GWS_DIR=$base/gws-$id
    GC_GCLOUD_DIR=$base/gcloud-$id
    GC_CLASP_DIR=$base/clasp-$id
    GC_CLASP_AUTH=$GC_CLASP_DIR/.clasprc.json
}

# Binarios reales (sobrescribibles para los tests).
GC_GWS_BIN=${GCUENTAS_GWS_BIN:-$HOME/.local/opt/gws/actual/gws}
GC_GCLOUD_BIN_DIR=${GCUENTAS_GCLOUD_BIN_DIR:-/usr/bin}
GC_CLASP_BIN=${GCUENTAS_CLASP_BIN:-$HOME/.local/opt/clasp/bin/clasp}

# Entorno de cada herramienta para la cuenta de cuentas_dirs (en el shell actual).
# El shim y gcuenta usan estas mismas funciones: una sola definición de qué es «estar en
# la cuenta X».
cuentas_entorno_gws() {
    local id=$1
    export GOOGLE_WORKSPACE_CLI_CONFIG_DIR=$GC_GWS_DIR
    export GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file
    # Vacío pero definido: gws lo ignora y ningún .env puede rellenarlo.
    export GOOGLE_WORKSPACE_CLI_TOKEN=
    unset GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE GOOGLE_APPLICATION_CREDENTIALS \
        GOOGLE_WORKSPACE_CLI_CLIENT_ID GOOGLE_WORKSPACE_CLI_CLIENT_SECRET
    if [ -n "${CUENTA_PROYECTO[$id]}" ]; then
        export GOOGLE_WORKSPACE_PROJECT_ID=${CUENTA_PROYECTO[$id]}
    else
        unset GOOGLE_WORKSPACE_PROJECT_ID
    fi
}

cuentas_entorno_gcloud() {
    export CLOUDSDK_CONFIG=$GC_GCLOUD_DIR
    # Variables que pisarían la cuenta, el proyecto o las credenciales del espacio.
    unset CLOUDSDK_ACTIVE_CONFIG_NAME CLOUDSDK_CORE_ACCOUNT CLOUDSDK_CORE_PROJECT \
        CLOUDSDK_AUTH_ACCESS_TOKEN_FILE CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE \
        CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT CLOUDSDK_BILLING_QUOTA_PROJECT
}

# Directorio desde el que gcuenta ejecuta gws por su cuenta (estado, login). Lleva un .env
# vacío: gws solo carga el primer .env que encuentra subiendo, así que ninguno de más arriba
# (por ejemplo ~/.env) puede meterle variables.
cuentas_dir_ejecucion() {
    local d=$GCUENTAS_CACHE/ejecucion
    mkdir -p "$d" && chmod 700 "$GCUENTAS_CACHE" "$d"
    [ -f "$d/.env" ] || : >"$d/.env"
    printf '%s' "$d"
}

cuentas_entorno_clasp() {
    export clasp_config_auth=$GC_CLASP_AUTH
}
