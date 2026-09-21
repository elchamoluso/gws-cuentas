# gws-cuentas

Varias cuentas Google logueadas **a la vez** en la misma máquina, cada una en su propio
espacio. La cuenta que usan [`gws`](https://github.com/googleworkspace/cli),
[`gcloud`](https://cloud.google.com/cli) (con `gsutil` y `bq`) y
[`clasp`](https://github.com/google/clasp) **la decide la carpeta** en la que trabajas.

```
~/Drive/SharedDrives/Asociación/…   → admin@asociacion.example
~/Drive/SharedDrives/Estudios/…     → yo@gmail.com
~/dev/asociacion/…                  → admin@asociacion.example
cualquier otra carpeta              → admin@empresa.example   (cuenta por defecto)
```

Entras en una carpeta, ejecutas `gws gmail users getProfile --params '{"userId":"me"}'` y
responde la cuenta de esa carpeta. No hay `login` ni `switch`. Si abres
[Claude Code](https://claude.com/claude-code) en esa carpeta, un hook se lo dice al empezar
la sesión.

Es la evolución de [gws-dos-cuentas](https://github.com/elchamoluso/gws-dos-cuentas): pasa
de dos cuentas a N, añade gcloud y clasp, y hace que la elección sea automática y comprobable.

## Por qué hace falta

- **gws** no tiene multicuenta desde la v0.7.0. Lo único que cambia de cuenta es la variable
  `GOOGLE_WORKSPACE_CLI_CONFIG_DIR`. Además:
  - si el directorio está vacío, usa **sin avisar** el ADC de `~/.config/gcloud`;
  - carga cualquier `.env` que encuentre subiendo desde la carpeta;
  - escribe las credenciales **antes** de saber con qué cuenta has entrado.
- **gcloud** guarda todas las cuentas en un solo sitio, con una activa global: el login de un
  proyecto cambia la cuenta de todos los demás.
- **clasp** guarda los tokens en `~/.clasprc.json`, también global.

## Cómo funciona

1. **Un espacio por cuenta y herramienta** (permisos 700/600):
   - `~/.config/gws-<id>/`, con `client_secret.json`, `credentials.enc` y `.encryption_key`.
   - `~/.config/gcloud-<id>/`, vía `CLOUDSDK_CONFIG`.
   - `~/.config/clasp-<id>/.clasprc.json`, vía `clasp_config_auth`.
2. **Un shim** (`bin/cuenta-shim`) instalado en `~/.local/bin` como `gws`, `gcloud`, `gsutil`,
   `bq` y `clasp`. En cada llamada:
   - resuelve la cuenta: `GCUENTA` si está definida; si no, el prefijo más largo de las reglas
     sobre `pwd -P`; si no, la cuenta por defecto;
   - prepara el entorno de esa cuenta y ejecuta el binario real;
   - no escribe nada en stdout.

   También **bloquea**:
   - los logins directos (`gws auth login`, `gcloud auth login`, `gcloud init`, `clasp login`…);
   - `gws auth export --unmasked`;
   - `.env` con variables `GOOGLE_*` o de proxy.
3. **Cepos.** `~/.config/gws` y `~/.config/gcloud` son ficheros vacíos con modo 000. Si algo
   se salta el shim, falla a la vista en vez de usar otra cuenta en silencio.
4. **`gcuenta`**, la herramienta del protocolo:

   | Orden | Qué hace |
   |---|---|
   | `gcuenta` | cuenta de la carpeta actual y por qué |
   | `gcuenta lista` | cuentas y reglas |
   | `gcuenta estado [--todas]` | comprueba en vivo gws, gcloud y clasp |
   | `gcuenta login <id> <gws\|gcloud\|clasp>` | login con el navegador de esa cuenta, **verificando el email antes de guardar** |
   | `gcuenta entrar <id>` | pestaña para iniciar sesión con esa cuenta en el navegador compartido |
   | `gcuenta nav <id> …` | [agent-browser](https://github.com/vercel-labs/agent-browser) conectado al navegador compartido; `open` añade la cuenta a la URL |
   | `gcuenta url <id> <url>` | la URL con la cuenta puesta (`authuser` / `login_hint`) |
   | `gcuenta cerrar` | cierra el navegador compartido |
   | `gcuenta env [id]` | variables de la cuenta, para `eval` |
   | `gcuenta hook` | texto para el hook de Claude Code (offline) |
   | `gcuenta doctor` | revisa la instalación |

5. **Un navegador compartido.** Un solo Chromium (perfil `~/.agent-browser/perfiles/google`)
   tiene la sesión de Google de todas las cuentas y **se queda abierto**. agent-browser **se
   conecta** a él por CDP (`127.0.0.1:9300`) y nunca lo lanza: con los flags de automatización
   con los que agent-browser arranca Chromium, Google revoca las sesiones. Cada página se abre
   con la cuenta que toca (`authuser=<email>`, o `login_hint` en accounts.google.com). Los
   logins abren el consentimiento ahí, no en el navegador por defecto del sistema.
6. **Claude Code**:
   - un hook `SessionStart` le dice a Claude qué cuenta toca en la carpeta de la sesión;
   - la skill `google-cuentas` explica el protocolo.

## Instalación en una máquina nueva

Probado en ChromeOS (Crostini, Debian 13, arm64). Debería funcionar en cualquier Linux con
bash, python3 y Chromium.

### 1. Herramientas

```bash
# Básicos + Chromium + Node.js (Debian; en Ubuntu, ver la nota de abajo)
sudo apt-get install -y ca-certificates gnupg curl python3 chromium nodejs npm

# Google Cloud CLI (repo apt oficial). NO ejecutes «gcloud init»: se hace por cuenta.
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli

# gws: binario estático (musl) de la release, verificado, fuera del PATH (se llama a través
# del shim). El de glibc para x86_64 exige glibc ≥ 2.39 y no arranca en Debian 12 ni Ubuntu 22.04.
V=0.22.5; A=google-workspace-cli-$(uname -m)-unknown-linux-musl.tar.gz
mkdir -p ~/.local/opt/gws/$V && cd "$(mktemp -d)"
curl -fsSLO https://github.com/googleworkspace/cli/releases/download/v$V/$A
curl -fsSLO https://github.com/googleworkspace/cli/releases/download/v$V/$A.sha256
sha256sum -c <(awk -v f="$A" '{print $1"  "f}' $A.sha256) && tar -xzf "$A" ./gws \
  && install -m 755 gws ~/.local/opt/gws/$V/gws && ln -sfn $V ~/.local/opt/gws/actual

# clasp (fuera del PATH) y agent-browser
npm i -g --prefix ~/.local/opt/clasp @google/clasp
npm i -g --prefix ~/.local agent-browser     # NO hace falta «agent-browser install»: el kit usa tu Chromium

# Skills para Claude Code (opcional)
npx skills add https://github.com/googleworkspace/cli --skill '*' -g -a claude-code -y
npx skills add vercel-labs/agent-browser -g -a claude-code -y
```

- **Node.js ≥ 20** para clasp (y ≥ 22 para `npx skills`). Debian 13 trae el 20. En Debian 12 o
  Ubuntu, instala uno más nuevo con [NodeSource](https://github.com/nodesource/distributions)
  o nvm.
- **Chromium sin snap.** El kit busca `chromium`, `chromium-browser`, `google-chrome-stable` o
  `google-chrome`, y descarta los de snap, que no pueden usar un perfil en una carpeta oculta de
  `$HOME`. En Ubuntu, instala Google Chrome desde su `.deb` oficial. Para usar otro binario:
  `export GCUENTAS_CHROMIUM=/ruta/al/navegador`.
- **`~/.local/bin` tiene que ir delante en el PATH.** En Debian y Ubuntu, `~/.profile` lo añade al
  iniciar sesión, pero solo si la carpeta ya existía. En una máquina nueva, después de este paso
  ejecuta `. ~/.profile` (o abre una terminal de login nueva). Tras `install.sh`, `command -v gcloud`
  tiene que dar `~/.local/bin/gcloud`.

### 2. Kit

```bash
git clone https://github.com/elchamoluso/gws-cuentas.git ~/dev/gws-cuentas
cd ~/dev/gws-cuentas
./install.sh             # la primera vez crea ~/.config/gws-cuentas/cuentas.conf desde el ejemplo
$EDITOR ~/.config/gws-cuentas/cuentas.conf
./install.sh             # crea espacios, cepos, shims, skill y hook
bash tests/resolver.sh && bash tests/shim.sh
```

La configuración (`config/cuentas.example.conf` tiene un ejemplo comentado):

```
maquina|<nombre>                     # la credencial OAuth se llama gws-<nombre> en todas las cuentas
cuenta|<id>|<email>|<proyecto_gcp>|<workspace|personal>
defecto|<id>
ruta|<carpeta>|<id>
conectores|<id>                      # opcional
navegador|<perfil>|<puerto>          # opcional: por defecto ~/.agent-browser/perfiles/google y 9300
```

## Protocolo por cuenta

Para cada cuenta, en este orden.

### 1. Iniciar sesión en el navegador compartido

```bash
gcuenta entrar <id>
```

Abre (o reutiliza) el Chromium compartido, **sin automatización**, así Google no lo bloquea
como «navegador no seguro», y le añade una pestaña con el email ya puesto. Inicia sesión con
2FA. Repite con cada cuenta: quedan todas en el mismo navegador. **No lo cierres** mientras
trabajas en consolas o logins; ese navegador solo hace falta para eso. Si lo cierras (o
reinicias la máquina), Google cierra esas sesiones y habrá que volver a entrar con
`gcuenta entrar <id>` la próxima vez que necesites una consola. Las credenciales de gws,
gcloud y clasp **no** dependen del navegador.

### 2. gcloud

```bash
gcuenta login <id> gcloud
```

Es el `gcloud init` de esa cuenta, dentro de su espacio. `gcloud auth login <email>` rechaza
cualquier otra cuenta antes de guardar nada.

### 3. Proyecto y credencial OAuth en la consola

En el proyecto GCP de la cuenta (existente o nuevo):

Todos los `gcloud` de esta sección se ejecutan con la cuenta **de la carpeta en la que estés**.
Ponles delante `GCUENTA=<id>` (o hazlos desde una carpeta de esa cuenta), porque si no irían con la
cuenta por defecto.

1. **APIs**:
   - todas las cuentas: `GCUENTA=<id> gcloud services enable drive.googleapis.com sheets.googleapis.com gmail.googleapis.com calendar-json.googleapis.com docs.googleapis.com slides.googleapis.com tasks.googleapis.com people.googleapis.com forms.googleapis.com meet.googleapis.com classroom.googleapis.com script.googleapis.com pubsub.googleapis.com workspaceevents.googleapis.com --project <proyecto>`
   - solo Workspace: `chat.googleapis.com admin.googleapis.com alertcenter.googleapis.com groupssettings.googleapis.com cloudidentity.googleapis.com licensing.googleapis.com vault.googleapis.com`
2. **Google Auth Platform → Audiencia**:
   - cuenta de Workspace: **Interna**, si el proyecto pertenece a esa organización. Así no hay
     verificación, ni usuarios de prueba, ni caducidad de 7 días;
   - cuenta @gmail.com: **Externa, publicada en producción**. En modo pruebas, el refresh token
     caduca a los 7 días. Sale un aviso de «app no verificada» que se acepta una vez.
3. **Chat** (solo Workspace): la API de Chat exige configurar la ficha de la app de Chat,
   aunque se use con auth de usuario.
4. **Clientes → Crear cliente → Aplicación de escritorio**, con el nombre **`gws-<maquina>`**:
   el **mismo nombre en todas las cuentas**, porque identifica la máquina que usa la credencial
   (`gws-portatil-casa`, `gws-macmini-oficina`…), no la cuenta ni el proyecto. Así, al limpiar
   credenciales, se ve enseguida de qué máquina es cada una. Descarga el
   JSON en el diálogo de creación y guárdalo en `~/.config/gws-<id>/client_secret.json` con
   modo 600.
5. `gcloud config set project <proyecto>` (desde una carpeta de esa cuenta, o con `GCUENTA=<id>`),
   y apunta el proyecto en `cuentas.conf`.

Se puede hacer a mano, o con agent-browser: `gcuenta nav <id> open https://console.cloud.google.com/auth/clients?project=<proyecto>`.

### 4. gws y clasp

```bash
gcuenta login <id> gws      # scopes de scopes/workspace.txt o scopes/personal.txt
gcuenta login <id> clasp    # usa el mismo cliente gws-<maquina> de esa cuenta
gcuenta estado --todas
```

- Antes del login de clasp, activa «Google Apps Script API» en
  https://script.google.com/home/usersettings con esa cuenta.
- El login de gws se hace en un directorio de staging, y solo se copia al espacio real si el
  email coincide con el de la cuenta.

## Uso diario

```bash
cd ~/Drive/SharedDrives/Estudios/curso && gws classroom courses list   # cuenta personal
cd ~/dev/asociacion && gcloud projects list                            # cuenta de la asociación
GCUENTA=empresa gws drive files list --params '{"pageSize": 5}'        # otra cuenta, solo este comando
gcuenta                                                                # ¿qué cuenta toca aquí?
```

### Claude Code

`install.sh` añade a `~/.claude/settings.json`:

```json
"hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "~/.local/bin/gcuenta hook", "timeout": 10 } ] } ] }
```

- El hook es **offline**: lee la caché que deja `gcuenta estado`, así que no retrasa el
  arranque. Con eso, Claude sabe qué cuenta toca sin loguearse, y si algo necesita
  reautenticarse.
- Las skills de gws funcionan tal cual, porque llaman a `gws`, que es el shim.
- clasp se usa por Bash (`clasp push`, `clasp pull`…), y el shim le da la cuenta de la carpeta
  en cada llamada. El servidor MCP de clasp **no** se registra a nivel usuario: fija la cuenta
  al arrancar y acepta proyectos de cualquier carpeta de `$HOME`, así que podría subir código
  con la cuenta equivocada.

## Seguridad

- Las credenciales no salen de su espacio: el shim nunca las mueve ni las imprime.
- `.encryption_key` y `credentials.enc` de gws se copian **juntos** en cada login.
- La configuración real (emails, rutas, proyectos) vive fuera del repo, en
  `~/.config/gws-cuentas/cuentas.conf`.
- El perfil del navegador compartido tiene sesiones de Google abiertas: trátalo como una
  credencial (`~/.agent-browser/perfiles`, modo 700).
- Mientras está abierto, el puerto CDP (`127.0.0.1:9300`) permite controlar ese navegador a
  cualquier proceso **local**. En una máquina de un solo usuario es aceptable; ciérralo con
  `gcuenta cerrar` cuando no lo necesites.
- Python se ejecuta siempre con `-I` (modo aislado): un `json.py` en la carpeta del proyecto
  no se importa.

## Problemas conocidos

| Síntoma | Causa y arreglo |
|---|---|
| Un 403 con el token válido | Falta el scope o la API en el proyecto. `gws auth status` muestra los scopes. |
| Tras cambiar scopes sigue el token viejo | `token_cache.json` no distingue scopes. `gcuenta login` lo borra. |
| `unauthorized_client` / «access blocked» con una cuenta @gmail | El cliente es de un proyecto con audiencia Interna. La cuenta personal necesita un proyecto Externo. |
| El login se abre en el Chrome de ChromeOS | Crostini exporta `BROWSER=garcon-url-handler`. Usa `gcuenta login`, que abre la URL en el perfil de la cuenta. |
| `agent-browser install` falla en arm64 | Es esperado. Usa el `chromium` de Debian, que agent-browser encuentra solo. |
| Google dice «este navegador no es seguro» | Inicia sesión con `gcuenta entrar <id>` (Chromium sin automatización). |
| Las sesiones del navegador desaparecen al usarlo con agent-browser | No dejes que agent-browser lance Chromium (`--profile`, `--config` con perfil). Usa `gcuenta nav`, que se conecta por CDP al navegador compartido. |
| Las sesiones de Google se pierden al cerrar o reiniciar Chromium | Pasa en Crostini con el Chromium de Debian: Google revoca la sesión cuando el navegador vuelve a arrancar. Causa sin resolver (desactivar las sesiones ligadas al dispositivo, DBSC, no lo evitó). Mientras el navegador sigue abierto, las sesiones aguantan. Tras reiniciarlo: `gcuenta entrar <id>`. Las credenciales de las CLI no se ven afectadas. |
| El clic automático en «Permitir» del consentimiento OAuth no hace nada | Google no acepta clics automatizados en esa pantalla. Ese clic lo da la persona; el resto (abrir la URL con la cuenta, verificar el email, guardar) lo hace `gcuenta login`. |
| La consola pide «Confirme a sua identidade» | Es la política de reautenticación de la organización Workspace. Introduce la contraseña en el navegador compartido y repite la acción. |
| `--output` no escribe el fichero con respuestas JSON | gws imprime por stdout las respuestas JSON aunque se le pase `--output`. Redirige con `> fichero`. Con contenido binario (PDF, imágenes, exportaciones) sí escribe, también en el Drive montado por 9p. |
| `--upload` o `--output` fuera de la carpeta | gws exige rutas bajo la carpeta actual. Trabaja desde la carpeta del proyecto. |
| Una organización Workspace pide reautenticar cada X días | Es su política de sesión. `gcuenta estado` lo detecta y `gcuenta login` lo repara. |

## Desinstalar

```bash
./install.sh --desinstalar   # quita shims, hook y skill; deja credenciales y cepos
```

## Licencia

MIT
