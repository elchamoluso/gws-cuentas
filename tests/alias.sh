#!/usr/bin/env bash
# tests/alias.sh — «alias|<id>|<email>»: otra dirección de la misma cuenta, que también vale al comprobar
# con qué cuenta se entró (gcuenta estado y login).
# shellcheck source=comun.sh
. "$(dirname "$(readlink -f "$0")")/comun.sh"
g=$kit/bin/gcuenta

cat >>"$GCUENTAS_CONF" <<'CONF'
alias|personal|Yo.Antes@Gmail.com
alias|personal|yo.mucho.antes@gmail.com
CONF

es() { # es <id> <email> → «sí» o «no», con la configuración de prueba
    (. "$kit/lib/cuentas.sh" && cuentas_cargar && if cuenta_es_email "$1" "$2"; then echo sí; else echo no; fi)
}

echo "La configuración con alias:"
esperar "carga y resuelve igual que sin alias" personal "$("$g" id "$FORM/01-sub")"
esperar "fuera de todo, la de por defecto" empresa "$("$g" id "$T/fuera")"

echo "cuenta_es_email:"
esperar "la dirección de la cuenta, en otras mayúsculas" sí "$(es personal YO@gmail.com)"
esperar "el primer alias, en otras mayúsculas" sí "$(es personal yo.antes@gmail.com)"
esperar "el segundo alias" sí "$(es personal Yo.Mucho.Antes@gmail.com)"
esperar "el alias de otra cuenta no vale" no "$(es empresa yo.antes@gmail.com)"
esperar "una dirección ajena" no "$(es personal otro@gmail.com)"
esperar "vacío" no "$(es personal '')"
esperar "una cuenta sin alias sigue con su dirección" sí "$(es asociacion admin@asociacion.example)"

echo "Errores de configuración:"
malo=$T/malo.conf
cp "$GCUENTAS_CONF" "$malo"
echo 'alias|nadie|x@y.example' >>"$malo"
contiene "un alias de una cuenta que no existe" "un alias apunta a la cuenta «nadie»" \
    "$(GCUENTAS_CONF=$malo "$g" id "$T/fuera" 2>&1)"
cp "$GCUENTAS_CONF" "$malo"
echo 'alias|personal|sin-arroba' >>"$malo"
contiene "un alias sin email válido" "el alias de «personal» necesita un email válido" \
    "$(GCUENTAS_CONF=$malo "$g" id "$T/fuera" 2>&1)"

resumen
