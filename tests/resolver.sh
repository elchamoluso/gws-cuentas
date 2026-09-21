#!/usr/bin/env bash
# tests/resolver.sh — resolución carpeta → cuenta.
# shellcheck source=comun.sh
. "$(dirname "$(readlink -f "$0")")/comun.sh"
g=$kit/bin/gcuenta

echo "Por ruta explícita:"
esperar "subcarpeta de Formación (ó)" personal "$("$g" id "$FORM/01-sub")"
esperar "raíz exacta de Formación" personal "$("$g" id "$FORM")"
esperar "prefijo más largo gana (Formación/01-sub/x → asociacion)" asociacion "$("$g" id "$FORM/01-sub/x/y")"
esperar "Asociación Local con espacios (regla con espacios alrededor)" asociacion "$("$g" id "$ASOC/02 comites/y z")"
esperar "MyDrive → defecto" empresa "$("$g" id "$D/MyDrive/a")"
esperar "Empresa → defecto" empresa "$("$g" id "$D/SharedDrives/Empresa")"
esperar "~/dev/asociacion/asociacion-ds (regla con \$HOME y barra final)" asociacion "$("$g" id "$HOME/dev/asociacion/asociacion-ds/sub")"
esperar "symlink ~/dev/asociacion-ds → asociacion" asociacion "$("$g" id "$HOME/dev/asociacion-ds")"
esperar "~/dev/asociacion-dsx no cae en la regla ~/dev/asociacion" empresa "$("$g" id "$HOME/dev/asociacion-dsx")"
esperar "~/dev/formacion (regla con ~)" personal "$("$g" id "$HOME/dev/formacion/curso")"
esperar "/mnt/chromeos/shared/… igual que /mnt/shared/…" personal \
    "$("$g" id "$T/mnt/chromeos/shared/GoogleDrive/SharedDrives/Formación/01-sub")"
esperar "Formaciónx no cae en la regla Formación" empresa "$("$g" id "$D/SharedDrives/Formaciónx")"
esperar "carpeta que no existe bajo Formación" personal "$("$g" id "$FORM/no/existe")"
esperar "fuera de todo → defecto" empresa "$("$g" id "$T/fuera")"
esperar "/tmp → defecto" empresa "$("$g" id /tmp)"

echo "Por carpeta actual:"
esperar "cd a Formación" personal "$(cd "$FORM/01-sub" && "$g" id)"
esperar "cd por el symlink ~/dev/asociacion-ds" asociacion "$(cd "$HOME/dev/asociacion-ds" && "$g" id)"
esperar "cd por /mnt/chromeos/shared" asociacion \
    "$(cd "$T/mnt/chromeos/shared/GoogleDrive/SharedDrives/Asociación Local" && "$g" id)"

echo "GCUENTA:"
esperar "GCUENTA manda sobre la carpeta" asociacion "$(cd "$FORM" && GCUENTA=asociacion "$g" id)"
esperar "con ruta explícita, GCUENTA no interviene" personal "$(GCUENTA=asociacion "$g" id "$FORM")"
salida=$(cd "$FORM" && GCUENTA=nada "$g" id 2>&1)
esperar "GCUENTA desconocida falla (código 2)" 2 "$(cd "$FORM" && GCUENTA=nada "$g" id >/dev/null 2>&1; echo $?)"
contiene "…y dice por qué" "no es una cuenta configurada" "$salida"

echo "Motivo y configuración:"
contiene "cual explica la regla" "ruta $FORM" "$("$g" cual "$FORM/01-sub")"
contiene "cual explica el defecto" "(defecto)" "$("$g" cual "$T/fuera")"
contiene "env de asociacion" "CLOUDSDK_CONFIG=$HOME/.config/gcloud-asociacion" "$("$g" env asociacion)"
cp "$GCUENTAS_CONF" "$T/buena.conf"
printf 'ruta|/x|noexiste\n' >>"$GCUENTAS_CONF"
esperar "regla hacia cuenta inexistente → código 2" 2 "$("$g" id /x >/dev/null 2>&1; echo $?)"
cp "$T/buena.conf" "$GCUENTAS_CONF"
printf 'cuenta|Mal Id|x@y||workspace\n' >>"$GCUENTAS_CONF"
esperar "id de cuenta no válido → código 2" 2 "$("$g" id /x >/dev/null 2>&1; echo $?)"
cp "$T/buena.conf" "$GCUENTAS_CONF"
esperar "sin configuración → código 2" 2 "$(GCUENTAS_CONF=$T/no.conf "$g" id >/dev/null 2>&1; echo $?)"

esperar "URL de Google sin https:// → normalizada con authuser" "https://console.cloud.google.com/x?authuser=Admin%40Asociacion.example" \
    "$("$g" url asociacion 'console.cloud.google.com/x')"
esperar "dominio que no es de Google sin esquema, intacto" "notgoogle.com/x" "$("$g" url asociacion 'notgoogle.com/x')"
esperar "google.com.evil.com no es de Google" "https://google.com.evil.com/x" "$("$g" url asociacion 'https://google.com.evil.com/x')"
esperar "usuario@host engañoso, intacto" "https://accounts.google.com@evil.example/x" "$("$g" url asociacion 'https://accounts.google.com@evil.example/x')"
esperar "barra invertida en el host, intacto" 'https://evil.example\\.google.com/x' "$("$g" url asociacion 'https://evil.example\\.google.com/x')"

echo "Validación de la configuración (revisión adversarial):"
printf 'cuenta|sinemail|||workspace\n' >>"$GCUENTAS_CONF"
esperar "cuenta sin email → código 2" 2 "$("$g" id /x >/dev/null 2>&1; echo $?)"
cp "$T/buena.conf" "$GCUENTAS_CONF"
printf 'ruta|relativa/carpeta|asociacion\n' >>"$GCUENTAS_CONF"
esperar "prefijo relativo → código 2" 2 "$("$g" id /x >/dev/null 2>&1; echo $?)"
cp "$T/buena.conf" "$GCUENTAS_CONF"
mkdir -p "$HOME/llaves"
printf 'ruta|${HOME}/llaves|asociacion\n' >>"$GCUENTAS_CONF"
esperar "prefijo con \${HOME}" asociacion "$("$g" id "$HOME/llaves")"
cp "$T/buena.conf" "$GCUENTAS_CONF"

echo "URLs con la cuenta puesta:"
esperar "consola de Cloud → authuser" "https://console.cloud.google.com/apis?project=p&authuser=Admin%40Asociacion.example" \
    "$("$g" url asociacion 'https://console.cloud.google.com/apis?project=p')"
esperar "accounts.google.com → login_hint (sin tocar el resto)" \
    "https://accounts.google.com/o/oauth2/auth?scope=a%20b&redirect_uri=http://localhost:1&login_hint=yo%40gmail.com" \
    "$("$g" url personal 'https://accounts.google.com/o/oauth2/auth?scope=a%20b&redirect_uri=http://localhost:1')"
esperar "respeta un authuser ya puesto y el fragmento" "https://admin.google.com/?authuser=2#usuarios" \
    "$("$g" url asociacion 'https://admin.google.com/?authuser=2#usuarios')"
esperar "dominios que no son de Google, intactos" "https://example.com/x" "$("$g" url asociacion https://example.com/x)"

printf 'ruta|%s/|personal\n' "$ASOC" >>"$GCUENTAS_CONF"
esperar "prefijo repetido → código 2" 2 "$("$g" id /x >/dev/null 2>&1; echo $?)"
cp "$T/buena.conf" "$GCUENTAS_CONF"
mkdir -p "$T/borrada"
r=$(cd "$T/borrada" && rmdir "$T/borrada" && "$g" id 2>&1; echo "código=$?")
contiene "carpeta actual borrada → no adivina (código 2)" "código=2" "$r"
contiene "…y lo explica" "la carpeta actual ya no existe" "$r"

resumen
