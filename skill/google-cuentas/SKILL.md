---
name: google-cuentas
description: "Protocolo de cuentas Google por carpeta en esta máquina (kit gws-cuentas): qué cuenta usan gws, gcloud, gsutil, bq y clasp según el proyecto, cómo usar otra cuenta en un comando (GCUENTA), comprobar el estado (gcuenta estado), hacer logins (gcuenta login) y abrir las consolas de Google con el navegador de cada cuenta (gcuenta nav). Léelo antes de cualquier trabajo con Google Workspace o Google Cloud: Gmail, Drive, Calendar, Classroom, Docs, Sheets, Forms, Chat, Admin, Apps Script, Cloud Console, OAuth, credenciales. Keywords: gws, gcloud, clasp, cuenta google, workspace, drive, gmail, classroom, consola, credenciales, oauth, login, GCUENTA."
---

# Cuentas Google por carpeta (gws-cuentas)

En esta máquina hay varias cuentas Google logueadas **a la vez**, cada una en su propio
espacio. Qué cuenta se usa lo decide **la carpeta** en la que se ejecuta el comando: no hay
que iniciar sesión ni cambiar de cuenta.

- `gws`, `gcloud`, `gsutil`, `bq` y `clasp` son, en `~/.local/bin`, un shim que resuelve la
  cuenta en **cada llamada** con `pwd -P` y el prefijo más largo de las reglas. Si nada
  coincide, usa la cuenta por defecto.
- El hook de inicio de sesión ya te ha dicho qué cuenta toca en la carpeta de la sesión. Si
  cambias de carpeta, la cuenta cambia con ella.

## Reglas

1. **Comprueba antes de actuar.** `gcuenta` muestra la cuenta de la carpeta actual y el
   motivo. `gcuenta lista` muestra todas las cuentas y reglas. No supongas la cuenta: la
   configuración real está en `~/.config/gws-cuentas/cuentas.conf`.
2. **No hagas login.** `gws auth login`, `gcloud auth login`, `gcloud init` y `clasp login`
   están bloqueados a propósito. Si una credencial falla, sigue la sección «Si algo falla».
3. **Otra cuenta en un solo comando** solo cuando el usuario lo pida: `GCUENTA=<id> gws …`
   (lo mismo con gcloud o clasp). Di siempre qué cuenta has usado.
4. **Antes de escribir** (enviar correo, compartir, borrar, crear eventos, tocar Admin),
   confirma que la cuenta que muestra `gcuenta` es la que el usuario quiere. Usa `--dry-run`
   cuando gws lo ofrezca.
5. **Los conectores de claude.ai** (Gmail, Drive, Calendar) están ligados a **una sola**
   cuenta (línea `conectores|` de la configuración; el hook la nombra). No siguen las reglas
   de carpeta. Para datos de cualquier otra cuenta, usa gws.
6. **Nunca**:
   - toques `~/.config/gws` ni `~/.config/gcloud` (son cepos: ficheros vacíos con modo 000);
   - copies credenciales entre espacios (`~/.config/{gws,gcloud,clasp}-<id>`);
   - imprimas tokens o secretos (`gws auth export --unmasked` está bloqueado);
   - ejecutes los binarios reales por su ruta (`~/.local/opt/gws/actual/gws`,
     `/usr/bin/gcloud`) para saltarte el shim.
7. **Ficheros del Drive local:** gws exige que las rutas de `--upload` y `--output` estén
   bajo la carpeta actual. Trabaja desde la carpeta del proyecto con rutas relativas.

## Las skills de gws funcionan tal cual

Las skills `gws-*`, `recipe-*` y `persona-*` llaman a `gws` a secas, que es el shim. Úsalas
normalmente: operan con la cuenta de la carpeta.

## Si algo falla (401, 403, invalid_grant, «token expired»)

1. `gcuenta estado` comprueba en vivo gws, gcloud y clasp de la cuenta de la carpeta.
   `gcuenta estado --todas` comprueba todas.
2. Si pide reautenticar: `gcuenta login <id> <gws|gcloud|clasp>`. **Necesita al usuario**,
   porque abre el consentimiento de Google en el navegador de esa cuenta.
   - Lánzalo en segundo plano. Luego mira la página con `gcuenta nav <id> snapshot -i` y
     pulsa «Continuar/Permitir» solo si el usuario está de acuerdo.
   - El login comprueba el email antes de guardar nada: si se elige otra cuenta, falla sin
     romper la buena.
3. Un 403 con token válido suele ser un scope que no se concedió, o una API sin activar en el
   proyecto de la cuenta. `gws auth status` (a través del shim) muestra los scopes.

## Consolas de Google con agent-browser

Hay **un solo Chromium compartido** con la sesión de Google de todas las cuentas. Se queda
abierto, y agent-browser se conecta a él por CDP. `gcuenta nav <id> open <url>` añade la
cuenta a la URL (`authuser=<email>`):

```bash
gcuenta nav <id> open "https://console.cloud.google.com/apis/credentials?project=<proyecto>"
gcuenta nav <id> snapshot -i -c
gcuenta nav <id> click @e12
gcuenta url <id> <url>           # solo imprime la URL con la cuenta puesta
```

- **Nunca** lances `agent-browser` a secas, ni con `--profile` o `--config`, para Google: si
  agent-browser arranca Chromium con sus flags, Google revoca las sesiones.
- `gcuenta nav <id> close` solo desconecta agent-browser; el navegador sigue abierto.
  `gcuenta cerrar` lo cierra del todo, y **Google cierra las sesiones**: al reabrirlo, el
  usuario tiene que volver a entrar (`gcuenta entrar <id>`). No lo cierres sin necesidad.
- La pantalla de consentimiento OAuth («Permitir») no acepta clics automatizados: pídele al
  usuario que pulse él. El resto de la consola sí se puede manejar con `gcuenta nav`.
- Si la consola pide «Confirme a sua identidade» (organizaciones Workspace), la contraseña la
  pone el usuario.
- Si una página pide iniciar sesión: `gcuenta entrar <id>` abre una pestaña para que el usuario
  entre. No se hace por él.
- Las descargas (por ejemplo, el JSON de un cliente OAuth) caen en
  `~/.local/share/gws-cuentas/descargas/`.
- clasp se usa por Bash (el shim le da la cuenta de la carpeta). No registres el MCP de clasp a
  nivel usuario: fija la cuenta al arrancar.

## Credenciales nuevas

- Cada máquina tiene **un** cliente OAuth de tipo **Desktop** por cuenta, y en todas las cuentas se
  llama igual: `gws-<maquina>` (línea `maquina|` de la configuración). Identifica la máquina, no
  la cuenta. Su JSON va a `~/.config/gws-<id>/client_secret.json` (modo 600).
- Los clientes `gws-*` de **otras** máquinas no se tocan ni se borran.
- clasp usa ese mismo cliente.
- El README del kit (`~/dev/gws-cuentas/README.md`) tiene el protocolo completo.
