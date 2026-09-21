#!/usr/bin/env bash
# tests/shim.sh — el shim: entorno por cuenta, bloqueos, cepo de .env, stdout limpio y hook.
# shellcheck source=comun.sh
. "$(dirname "$(readlink -f "$0")")/comun.sh"

# Binarios falsos: imprimen (en una sola línea) el entorno que reciben.
F=$T/falsos
mkdir -p "$F" "$T/bin"
cat >"$F/gws" <<'FAKE'
#!/usr/bin/env bash
printf 'dir=%s|keyring=%s|token=%s:%s|cuenta=%s|creds=%s|adc=%s|proy=%s|n=%d|a1=%s|a5=%s\n' \
  "${GOOGLE_WORKSPACE_CLI_CONFIG_DIR-}" "${GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND-}" \
  "${GOOGLE_WORKSPACE_CLI_TOKEN+definido}" "${GOOGLE_WORKSPACE_CLI_TOKEN-}" "${GCUENTA-}" \
  "${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE-}" "${GOOGLE_APPLICATION_CREDENTIALS-}" \
  "${GOOGLE_WORKSPACE_PROJECT_ID-}" "$#" "${1-}" "${5-}"
FAKE
for h in gcloud gsutil bq; do
    printf '#!/usr/bin/env bash\nprintf "%s cfg=%%s|activa=%%s|cuenta=%%s|n=%%d\\n" "${CLOUDSDK_CONFIG-}" "${CLOUDSDK_ACTIVE_CONFIG_NAME-}" "${GCUENTA-}" "$#"\n' "$h" >"$F/$h"
done
printf '#!/usr/bin/env bash\nprintf "clasp auth=%%s|cuenta=%%s\\n" "${clasp_config_auth-}" "${GCUENTA-}"\n' >"$F/clasp"
chmod 755 "$F"/*
for h in gws gcloud gsutil bq clasp; do ln -s "$kit/bin/cuenta-shim" "$T/bin/$h"; done
export GCUENTAS_GWS_BIN=$F/gws GCUENTAS_GCLOUD_BIN_DIR=$F GCUENTAS_CLASP_BIN=$F/clasp
for id in empresa asociacion personal; do mkdir -p "$HOME/.config/gws-$id"; done
B=$T/bin

echo "gws:"
salida=$(cd "$FORM/01-sub" && GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/x GOOGLE_APPLICATION_CREDENTIALS=/y \
    GOOGLE_WORKSPACE_CLI_TOKEN=robado "$B/gws" drive files list --params '{"q":"name = \"a b\""}' 2>/dev/null)
esperar "stdout es exactamente la salida de gws (1 línea)" 1 "$(printf '%s\n' "$salida" | wc -l)"
contiene "espacio de personal" "dir=$HOME/.config/gws-personal|" "$salida"
contiene "keyring en fichero" "keyring=file|" "$salida"
contiene "token definido y vacío (pisa el de fuera)" "token=definido:|" "$salida"
contiene "sin CREDENTIALS_FILE ni ADC heredados" "creds=|adc=|" "$salida"
contiene "GCUENTA exportada a los hijos" "cuenta=personal|" "$salida"
contiene "argumentos con espacios intactos" 'n=5|a1=drive|a5={"q":"name = \"a b\""}' "$salida"
contiene "proyecto de la cuenta por defecto" "proy=proy-empresa" "$(cd "$T/fuera" && GOOGLE_WORKSPACE_PROJECT_ID=otro "$B/gws" x 2>/dev/null)"
contiene "sin proyecto: no hereda uno global" "proy=|" "$(cd "$ASOC" && GOOGLE_WORKSPACE_PROJECT_ID=otro "$B/gws" x 2>/dev/null)"
contiene "GCUENTA=asociacion desde Formación" "dir=$HOME/.config/gws-asociacion|" "$(cd "$FORM" && GCUENTA=asociacion "$B/gws" x 2>/dev/null)"
esperar "GCUENTA desconocida no ejecuta nada (código 2)" "2:" \
    "$(cd "$FORM" && GCUENTA=nada "$B/gws" x 2>/dev/null; echo "$?:")"

echo "Bloqueos de gws:"
for args in "auth login" "auth login --scopes x" "--format json auth login" "auth logout" "auth setup" "auth export --unmasked"; do
    # shellcheck disable=SC2086
    r=$(cd "$FORM" && "$B/gws" $args 2>"$T/err"; echo "código=$?")
    esperar "gws $args bloqueado sin tocar stdout" "código=3" "$r"
done
contiene "…y remite a gcuenta login" "gcuenta login personal gws" "$(cd "$FORM" && "$B/gws" auth login 2>&1)"
contiene "gws auth export (enmascarado) sí pasa" "a1=auth" "$(cd "$FORM" && "$B/gws" auth export 2>/dev/null)"
contiene "gws auth status sí pasa" "a1=auth" "$(cd "$FORM" && "$B/gws" auth status 2>/dev/null)"

echo "Cepo de .env:"
printf 'FOO=1\n# GOOGLE_X=1 comentado\n' >"$FORM/.env"
contiene ".env inocuo: pasa" "a1=x" "$(cd "$FORM/01-sub" && "$B/gws" x 2>/dev/null)"
printf 'FOO=1\nGOOGLE_WORKSPACE_CLI_TOKEN=token-robado\n' >"$FORM/.env"
esperar ".env con GOOGLE_* en un padre: bloqueado" "3:" "$(cd "$FORM/01-sub" && "$B/gws" x 2>/dev/null; echo "$?:")"
printf 'export https_proxy=http://evil:8080\n' >"$FORM/.env"
esperar ".env con https_proxy: bloqueado" "3:" "$(cd "$FORM/01-sub" && "$B/gws" x 2>/dev/null; echo "$?:")"
rm -f "$FORM/.env"

echo "gcloud / gsutil / bq:"
salida=$(cd "$ASOC/02 comites" && CLOUDSDK_ACTIVE_CONFIG_NAME=otra "$B/gcloud" config list 2>/dev/null)
esperar "gcloud en la asociación usa su espacio y no hereda configuración activa" \
    "gcloud cfg=$HOME/.config/gcloud-asociacion|activa=|cuenta=asociacion|n=2" "$salida"
esperar "el espacio de gcloud se crea con 700" 700 "$(stat -c %a "$HOME/.config/gcloud-asociacion")"
contiene "gsutil comparte el espacio" "cfg=$HOME/.config/gcloud-asociacion|" "$(cd "$ASOC" && "$B/gsutil" ls 2>/dev/null)"
contiene "bq comparte el espacio" "cfg=$HOME/.config/gcloud-empresa|" "$(cd "$T/fuera" && "$B/bq" ls 2>/dev/null)"
for args in "auth login" "--project x auth login" "auth revoke" "auth application-default login" "config set account a@b" "init"; do
    # shellcheck disable=SC2086
    esperar "gcloud $args bloqueado" "3:" "$(cd "$ASOC" && "$B/gcloud" $args 2>/dev/null; echo "$?:")"
done
contiene "gcloud auth list sí pasa" "cuenta=asociacion" "$(cd "$ASOC" && "$B/gcloud" auth list 2>/dev/null)"

echo "clasp:"
contiene "clasp en ~/dev/formacion usa su fichero de auth" \
    "auth=$HOME/.config/clasp-personal/.clasprc.json|" "$(cd "$HOME/dev/formacion" && "$B/clasp" push 2>/dev/null)"
esperar "clasp login bloqueado" "3:" "$(cd "$HOME/dev/formacion" && "$B/clasp" login 2>/dev/null; echo "$?:")"
esperar "clasp logout bloqueado" "3:" "$(cd "$HOME/dev/formacion" && "$B/clasp" logout 2>/dev/null; echo "$?:")"

echo "Hook de Claude Code:"
h=$(printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$FORM/01-sub" | "$kit/bin/gcuenta" hook)
contiene "nombra la cuenta de la carpeta" "«personal» = yo@gmail.com" "$h"
contiene "conectores: misma cuenta" "la misma cuenta que esta carpeta" "$h"
contiene "sin estado todavía: pide gcuenta estado" "Sin estado comprobado" "$h"
esperar "no empieza por «{» (Claude lo tomaría por JSON)" "[" "${h:0:1}"
h=$(printf '{"cwd":"%s"}' "$ASOC" | "$kit/bin/gcuenta" hook)
contiene "Asociación: conectores NO siguen la regla" "NO siguen esta regla: para datos de Admin@Asociacion.example" "$h"
mkdir -p "$GCUENTAS_CACHE"
printf '{"fecha": %s, "gws": {"ok": true, "scopes": 35}, "gcloud": {"ok": false, "detalle": "hay que reautenticar"}, "clasp": {"ok": true}}' \
    "$(date +%s)" >"$GCUENTAS_CACHE/estado-asociacion.json"
h=$(printf '{"cwd":"%s"}' "$ASOC" | "$kit/bin/gcuenta" hook)
contiene "estado en caché: gws OK con scopes" "gws OK (35 scopes)" "$h"
contiene "estado en caché: aviso de gcloud" "⚠️ gcloud: hay que reautenticar" "$h"
esperar "hook sin stdin usa la carpeta actual" "[" "$(cd "$T/fuera" && "$kit/bin/gcuenta" hook </dev/null | head -c 1)"
r=$(printf '{"cwd":"/"}' | GCUENTAS_CONF=$T/no.conf "$kit/bin/gcuenta" hook; echo "código=$?")
contiene "configuración rota: el hook avisa y sale 0" "código=0" "$r"
contiene "…con un aviso" "⚠️" "$r"

echo "Revisión adversarial (regresiones):"
for args in "--account a@b auth login" "--configuration x auth login" "config set core/account a@b"; do
    # shellcheck disable=SC2086
    esperar "gcloud $args bloqueado" "3:" "$(cd "$ASOC" && "$B/gcloud" $args 2>/dev/null; echo "$?:")"
done
esperar "clasp -u x login bloqueado" "3:" "$(cd "$HOME/dev/formacion" && "$B/clasp" -u x login 2>/dev/null; echo "$?:")"
esperar "clasp -A f logout bloqueado" "3:" "$(cd "$HOME/dev/formacion" && "$B/clasp" -A f logout 2>/dev/null; echo "$?:")"
contiene "texto libre con «auth login» no bloquea gws" "a1=gmail" \
    "$(cd "$FORM" && "$B/gws" gmail +send --subject "auth login" --body x 2>/dev/null)"
contiene "--format value(auth login) no bloquea gcloud" "cuenta=asociacion" \
    "$(cd "$ASOC" && "$B/gcloud" projects list --format "auth login" 2>/dev/null)"
printf 'FOO=1\n' >"$FORM/01-sub/.env"
printf 'GOOGLE_WORKSPACE_CLI_TOKEN=x\n' >"$FORM/.env"
contiene "solo cuenta el primer .env (el que gws carga)" "a1=x" "$(cd "$FORM/01-sub/x" && "$B/gws" x 2>/dev/null)"
rm -f "$FORM/01-sub/.env" "$FORM/.env"
salida=$(cd "$T/fuera" && CLOUDSDK_CORE_ACCOUNT=otra@x CLOUDSDK_CORE_PROJECT=p CLOUDSDK_AUTH_ACCESS_TOKEN_FILE=/t \
    bash -c 'exec "$0" config list' "$B/gcloud" 2>/dev/null)
contiene "gcloud no hereda CLOUDSDK_CORE_ACCOUNT/PROJECT" "cfg=$HOME/.config/gcloud-empresa|" "$salida"
cat >"$F/gcloud" <<'FAKE'
#!/usr/bin/env bash
printf 'acct=%s|proj=%s|tok=%s\n' "${CLOUDSDK_CORE_ACCOUNT-}" "${CLOUDSDK_CORE_PROJECT-}" "${CLOUDSDK_AUTH_ACCESS_TOKEN_FILE-}"
FAKE
esperar "…ni las variables de credenciales" "acct=|proj=|tok=" \
    "$(cd "$T/fuera" && CLOUDSDK_CORE_ACCOUNT=otra@x CLOUDSDK_CORE_PROJECT=p CLOUDSDK_AUTH_ACCESS_TOKEN_FILE=/t "$B/gcloud" x 2>/dev/null)"
h=$(printf '{"cwd":"%s"}' "$FORM" | GCUENTA=asociacion "$kit/bin/gcuenta" hook)
contiene "hook: GCUENTA exportada manda, como en el shim" "«asociacion»" "$h"
h=$(printf '{"cwd":"%s"}' "$FORM" | GCUENTA=nada "$kit/bin/gcuenta" hook; echo "código=$?")
contiene "hook: GCUENTA inválida avisa y sale 0" "GCUENTA=«nada» está exportada" "$h"
printf '{"fecha": %s, "email": "otro@x", "gws": {"ok": true, "scopes": 9}, "gcloud": {"ok": true}, "clasp": {"ok": true}}' \
    "$(date +%s)" >"$GCUENTAS_CACHE/estado-asociacion.json"
contiene "hook: descarta la caché de otro email" "Sin estado comprobado" "$(printf '{"cwd":"%s"}' "$ASOC" | "$kit/bin/gcuenta" hook)"

printf 'import sys\nopen(sys.argv[0] + ".pwned", "w")\nraise SystemExit("json falso importado")\n' >"$FORM/json.py"
h=$(cd "$FORM" && printf '{"cwd":"%s"}' "$FORM" | "$kit/bin/gcuenta" hook 2>&1)
contiene "hook: un json.py en la carpeta no se importa (python -I)" "«personal»" "$h"
esperar "…y no se ejecutó nada" "no" "$(ls "$FORM"/*.pwned >/dev/null 2>&1 && echo sí || echo no)"
rm -f "$FORM/json.py"

esperar "gcloud auth print-refresh-token bloqueado" "3:" "$(cd "$ASOC" && "$B/gcloud" auth print-refresh-token 2>/dev/null; echo "$?:")"
cat >"$F/gws" <<'FAKE'
#!/usr/bin/env bash
printf '{"user":"yo@gmail.com","token_valid":true,"scope_count":3,"pwd":"%s","env_vacio":"%s"}\n' "$PWD" "$([ -f .env ] && [ ! -s .env ] && echo si || echo no)"
FAKE
printf 'x' >"$HOME/.config/gws-personal/credentials.enc"
"$kit/bin/gcuenta" estado personal >/dev/null 2>&1
contiene "estado lee a gws (gws OK, 3 scopes)" '"gws": {"ok": true, "detalle": "3 scopes"' "$(cat "$GCUENTAS_CACHE/estado-personal.json")"
esperar "…desde el directorio de ejecución" "si" "$([ -f "$GCUENTAS_CACHE/ejecucion/.env" ] && [ ! -s "$GCUENTAS_CACHE/ejecucion/.env" ] && echo si || echo no)"

resumen
