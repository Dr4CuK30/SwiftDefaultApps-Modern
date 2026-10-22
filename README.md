# SwiftDefaultApps (moderno)

Ver y cambiar las **aplicaciones por defecto** de macOS para cualquier esquema de URL (`http`, `mailto`, `ssh`…) o tipo de archivo (`.md`, `public.plain-text`…), con una app gráfica o desde la terminal.

Es una reimplementación desde cero, para macOS moderno, de [SwiftDefaultApps](https://github.com/Lord-Kamina/SwiftDefaultApps) de Gregorio Litenstein. El original (v2.0.1, 2019) ya no funciona en las Mac actuales:

- sus binarios son solo Intel (`x86_64`) y fallan con `bad CPU type in executable` en Apple Silicon sin Rosetta;
- era un panel `.prefPane`, y Configuración del Sistema (macOS 13+) ya no admite bien paneles de terceros.

Esta versión es nativa para **Apple Silicon e Intel** (binario universal), usa las APIs actuales de `NSWorkspace`/`UniformTypeIdentifiers` y se distribuye como **app independiente** en vez de panel.

## Requisitos

- macOS 13 Ventura o posterior.
- Para compilar: Xcode 15+ (Swift 5.9+).

## Instalación

### Desde el release

1. Descarga `SwiftDefaultApps-<versión>.zip` de [Releases](../../releases).
2. Descomprime y arrastra `SwiftDefaultApps.app` a `/Applications`.
3. La app está firmada ad hoc (no notarizada): la primera vez ábrela con **clic derecho → Abrir**, o ejecuta:

   ```bash
   xattr -dr com.apple.quarantine /Applications/SwiftDefaultApps.app
   ```

El CLI viene dentro de la app y también como descarga aparte (`swda-<versión>.zip`). Para tenerlo en el `PATH`:

```bash
sudo ln -sf /Applications/SwiftDefaultApps.app/Contents/Resources/swda /usr/local/bin/swda
```

### Desde el código

```bash
git clone <url-de-este-repo>
cd <repo>
./build-app.sh
```

Genera `build/SwiftDefaultApps.app` y `./swda`.

## La app

Tres secciones en la barra lateral:

| Sección | Qué hace |
| --- | --- |
| **Esquemas de URL** | Lista todos los esquemas conocidos por LaunchServices con su app actual. Elige otra en "Abrir con" o con "Otra aplicación…". |
| **Tipos de archivo** | Lo mismo para UTIs, con su descripción y extensión. Permite elegir el rol (Visor, Editor, Shell o Todos). |
| **Aplicaciones** | Para cada app instalada, muestra qué esquemas y tipos declara, cuáles abre ya y un botón "Usar esta app" para el resto. |

Todas las listas tienen buscador. El botón **Recargar** vuelve a leer LaunchServices.

> Al cambiar el navegador (`http`/`https`), macOS muestra un diálogo de confirmación propio. Es una restricción del sistema.

## El CLI: `swda`

Compatible con los comandos del `swda` original:

```text
swda getSchemes                        Lista esquemas de URL y su app por defecto
swda getUTIs                           Lista UTIs y su app por defecto
swda getApps                           Lista las apps registradas en LaunchServices
swda getHandler <tipo> [--role R] [--all]
swda setHandler <tipo> --app <app> [--role R]
```

`<tipo>` puede ser `--URL <esquema>`, `--UTI <uti>`, `--ext <extensión>` o un atajo: `--browser`, `--mail`, `--ftp`, `--rss`, `--news`.
`<app>` puede ser un nombre, un bundle id o la ruta a un `.app`.

Ejemplos:

```bash
swda getHandler --browser
swda getHandler --ext md --all
swda setHandler --ext md --app "Visual Studio Code"
swda setHandler --mail --app com.apple.mail
swda setHandler --UTI public.plain-text --role Editor --app TextEdit
```

### Diferencias con el original

- Nuevo `--ext` para indicar una extensión en lugar de un UTI.
- `--app` acepta nombre, bundle id o ruta.
- `--app None` ya no está soportado: macOS moderno elimina las asociaciones a apps "vacías", así que la app *ThisAppDoesNothing* del original no tiene equivalente.

## Estructura

```text
Sources/
  DefaultAppsCore/   Lógica compartida sobre LaunchServices
  swda/              CLI
  SwiftDefaultApps/  App SwiftUI
build-app.sh         Compila ambos como binarios universales y arma el .app
```

## Créditos y licencia

Idea y diseño de comandos basados en [SwiftDefaultApps](https://github.com/Lord-Kamina/SwiftDefaultApps) de Gregorio Litenstein, a su vez inspirado en RCDefaultApp de Carl Lindberg. El código de este repositorio es nuevo.

Licencia [MIT](LICENSE).
