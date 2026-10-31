# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **Un reemplazo ligero y perfecto para Spotlight de macOS, construido en Swift puro, diseñado para desarrolladores y usuarios avanzados que desean velocidad instantánea sin la sobrecarga de la indexación de archivos.**

Lightspot reproduce fielmente el moderno diseño de píldora flotante y la estética de cristal translúcido de Spotlight de macOS (`NSVisualEffectView`). Bajo el capó, ofrece una capacidad de respuesta por debajo del milisegundo (< 1.0 ms de búsqueda) con **cero indexación de archivos en segundo plano**. En reposo, su único trabajo periódico es una comprobación ligera del portapapeles cada 0.6 s, y usa menos de **25 MB de RAM**.

![Captura de pantalla de Lightspot](screenshot.png)

---

## ⚡ Inicio Rápido

### 📦 Descarga e Instalación en una sola línea
Simplemente copia y pega este comando en tu Terminal para descargar, extraer e instalar automáticamente el último **Lightspot** en tu carpeta `/Applications`. Descarga la compilación para tu Mac, unos 1,6 MB en Apple silicon o 1,75 MB en Intel, según el procesador del propio Mac (`sysctl hw.optional.arm64`), así que una Terminal que se ejecuta con Rosetta también recibe la compilación para Apple silicon:

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

*(Opcional: Pasa `--user` para instalar en `~/Applications`: `curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash -s -- --user`)*

---

### 🗑️ Desinstalación Completa
¿Deseas eliminarlo por completo? Este comando detiene la aplicación, elimina los elementos de inicio automático, borra las preferencias de usuario, elimina el paquete de la aplicación y vuelve a activar Apple Spotlight si Lightspot lo desactivó (reactivar la indexación pide tu contraseña de administrador, o muestra el comando `sudo mdutil -a -i on` para ejecutarlo más tarde):

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash
```

*(Opcional: `curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/uninstall.sh | bash -s -- --dry-run` muestra lo que se cambiaría sin modificar nada; usa `--keep-spotlight-disabled` en su lugar para dejar Spotlight desactivado.)*

Los cambios de Mac Tweaks se quedan, también los elementos en segundo plano que desactivó (los de todos los usuarios siguen desactivados en todas las cuentas): el desinstalador conserva su registro de deshacer y la copia del Dock, y explica cómo deshacer lo que queda: reinstala Lightspot y elige **Undo everything Lightspot changed** en Settings de Mac Tweaks, quita **Lightspot Mac Tweaks** en Ajustes del Sistema › General › Gestión de dispositivos, o usa **Restore Dock Icons**.

---

## 💡 ¿Por qué Lightspot?

Spotlight integrado de Apple fue diseñado para la búsqueda casual de archivos. Pero para los desarrolladores y usuarios avanzados, los procesos en segundo plano de Spotlight a menudo crean una fricción severa en el sistema. **Lightspot está construido para resolver esto.**

### El Problema: Spotlight de Apple

1. **Drenaje de CPU y Batería:** Los demonios en segundo plano (`mds`, `mdworker`) indexan archivos agresivamente. Un simple `npm install` o `git checkout` puede clavar tu CPU al 100%, encendiendo los ventiladores y matando la duración de la batería.
2. **Aplicaciones Faltantes:** El índice de Spotlight frecuentemente se corrompe, lo que hace que falle en su trabajo más básico: encontrar aplicaciones como Terminal o Slack. Solucionarlo requiere ejecutar comandos oscuros de `mdutil` para reconstruir el índice desde cero.
3. **Uso Excesivo de Disco:** Spotlight almacena en caché silenciosamente metadatos en una carpeta oculta `/.Spotlight-V100`. En máquinas de desarrolladores, este índice regularmente se infla a **50GB–200GB**, desperdiciando costoso almacenamiento SSD.
4. **Acaparamiento de Memoria:** Los procesos de Spotlight frecuentemente tienen fugas y consumen gigabytes de memoria unificada RAM, memoria que debería estar disponible para tu IDE, Docker o LLMs locales.
5. **Rastreo de Archivos no Deseado:** Excluir carpetas masivas como `node_modules`, `.git` o `.venv` a través de los Ajustes del Sistema es notoriamente torpe, lento y a menudo se reinicia durante las actualizaciones de macOS.

*(Ver reportes de la comunidad: [High CPU](https://www.reddit.com/r/MacOS/comments/1p10c3f/pages_caused_insane_cpu_spikes_on_macos_i_think_i/), [Missing Apps](https://www.reddit.com/r/MacOS/comments/1gjhiha/spotlight_not_looking_for_apps/), [Storage Waste](https://dev.to/vvo/how-to-avoid-spotlight-using-hundreds-of-gbs-and-rebuild-its-index-4kki), [Memory Leaks](https://discussions.apple.com/thread/256167358?sortBy=rank))*

---

## ⚡ La Solución: Arquitectura de Cero Indexación

Lightspot soluciona estos problemas adoptando un enfoque fundamentalmente diferente: **Cero indexación de archivos en segundo plano.**

En lugar de rastrear agresivamente todo tu disco duro, Lightspot se centra estrictamente en lo que los usuarios avanzados realmente buscan: Aplicaciones, Proyectos IDE, Pestañas del Navegador, Marcadores e Historial, Utilidades para Desarrolladores y Comandos Personalizados.

### Matriz de Comparación

| Métrica | Spotlight de Apple | Raycast / Alfred | Lightspot 🔍 |
|:---|:---|:---|:---|
| **Indexación de Archivos** | Rastreo incontrolado en segundo plano | Opcional / Configurable | **Nunca** (Por garantía arquitectónica) |
| **Uso de CPU en Reposo** | Picos de 100%+ durante operaciones | 1% – 5% en segundo plano | **Mínimo** (sin indexación; solo una comprobación del portapapeles cada 0.6 s) |
| **Almacenamiento en Disco** | 10 GB – 200 GB+ en caché oculta | 100 MB – 1 GB | **Sin índice ni caché** (tus ajustes en `UserDefaults`, un archivo de bloqueo y archivos pequeños solo cuando limpias o aplicas algo: registros de recibos, el registro de deshacer de Mac Tweaks y una copia del Dock) |
| **Huella de RAM** | 500 MB – 2 GB+ | 200 MB – 500 MB | **~15 – 25 MB** (Swift Puro) |
| **Lanzamiento de Aplicaciones** | Falla con frecuencia; requiere reconstrucciones | Confiable | **100% Confiable** (Escaneo directo) |
| **Latencia de Búsqueda** | Retardada (50 – 200 ms) | 10 – 30 ms | **< 1.0 ms** (síncrono instantáneo) |
| **Privacidad Offline** | Envía telemetría de Siri a Apple | Requiere cuenta para sincronización | **Local y Libre de Telemetría** (red solo para una comprobación de actualizaciones opcional, una consulta de IP que tú solicitas y las reglas de limpieza de cdm cuando abres Clean Dev Mac) |

---

## 🛠️ Personalización Centrada en el Desarrollador y Flujos de Trabajo Avanzados

Lightspot fue diseñado desde cero como el centro de comandos principal de un desarrollador. Cada aspecto puede ser moldeado según tus necesidades exactas de terminal, editor, script y flujo de trabajo:

### 1. ⚡ Comandos Personalizados y Ejecutores de Scripts (`⌘⇧C`)
Abre el Editor de Comandos Personalizados interactivo con **`⌘⇧C`** para crear y organizar atajos personalizados:
- **4 Motores de Ejecución**:
  - `terminal`: Ejecuta el comando directamente en tu emulador de terminal preferido.
  - `shell`: Ejecuta sin interfaz en segundo plano a través de `/bin/zsh`.
  - `applescript`: Ejecuta automatizaciones nativas de AppleScript de macOS.
  - `url`: Abre URLs parametrizadas en tu navegador predeterminado.
- **Expansión Dinámica de Parámetros**:
  - Usa `{query}`, `%s` o `%@` para sustituir cualquier argumento que escribas después del comando.
- **Disparadores de Prefijo**:
  - Asigna a un comando tu propio prefijo y escribe `<prefijo> <consulta>` (ej. `c <url>` para headers de curl, `png <host>` para hacer ping). El menú **Presets** del editor ofrece nueve comandos listos para usar: `gh`, `g`, `yt`, `so`, `ddg`, `wiki`, `npm`, `png` y `c`.
- **Palabras Clave Personalizadas e Íconos**:
  - Agrega palabras clave difusas (fuzzy) para descubrimiento instantáneo. El ícono de un comando es por defecto el de su aplicación ejecutora (tu navegador, terminal o Script Editor); puedes cambiar al símbolo integrado del ejecutor o elegir tu propia imagen o archivo de aplicación.

### 2. 💬 Fragmentos de Texto Dinámicos
Lightspot incluye cinco fragmentos de texto (snippets) — `date`, `iso`, `uuid`, `shrug` y `flip` — y expande variables dinámicas en el momento de copiarlos:
- `{{date}}`: Fecha actual (`YYYY-MM-DD`)
- `{{time}}`: Hora actual (`HH:mm:ss`)
- `{{iso}}`: Marca de tiempo ISO 8601 UTC (`2026-09-05T14:30:00Z`)
- `{{uuid}}`: UUID v4 aleatorio
- `{{clipboard}}`: Contenido actual de tu portapapeles

Escribe una palabra clave de snippet (ej. `iso`, `uuid`, `date`) o parte de su nombre y presiona **`↵`** para copiar la cadena evaluada directamente a tu portapapeles.

### 3. 💻 Elige Entre 7 Emuladores de Terminal Modernos
Lightspot se integra con tu emulador de terminal favorito. Cambia en cualquier momento a través de la barra de menú:
- **Ghostty**, **Warp**, **Alacritty**, **iTerm2**, **Kitty**, **WezTerm** y **Terminal de Apple**. (Warp abre carpetas, pero no acepta comandos enviados desde otra app, así que con Warp seleccionado los comandos del historial, fijados y personalizados de terminal se ejecutan en la Terminal de Apple.)
- **"Terminal en Carpeta de Finder"**: Escribe `term` o presiona la acción para lanzar instantáneamente tu terminal preferida dentro del directorio actualmente abierto en Finder.

### 4. 📂 Descubrimiento de Proyectos Recientes Multi-IDE
Lightspot monitorea automáticamente los espacios de trabajo recientes en:
- **VS Code**, **Cursor**, **Zed**, **IDEs de JetBrains** (IntelliJ IDEA, PyCharm —incluidas las ediciones Community—, WebStorm, GoLand, CLion, RustRover, Rider, PhpStorm, DataGrip, RubyMine, DataSpell), **Android Studio** y **Sublime Text**.
- **Modificadores de Teclado**:
  - `↵` (Return): Abrir el espacio de trabajo en su IDE asociado.
  - `⌘↵` (Command + Return): Lanzar tu terminal preferida en el directorio raíz del proyecto.
  - `⌥↵` (Option + Return): Revelar la carpeta del proyecto en Finder.

### 5. 🔌 Asesino de Procesos y Terminador de Puertos (`kill`)
Termina rápidamente servidores de desarrollo persistentes, tareas en segundo plano atascadas o procesos rebeldes:
- **Matar por puerto:** `kill :3000`, `kill :8080`, `kill :5173` (resuelve mediante `lsof` el proceso que *escucha* en el puerto; los clientes que solo están conectados a él no se listan).
- **Matar por nombre de proceso o PID:** `kill node`, `kill python`, `kill 14205`. Los procesos del sistema (`launchd`, `kernel_task`, `WindowServer`, `loginwindow`) y el propio Lightspot nunca se ofrecen.
- **Niveles de terminación:**
  - `↵` (Return): Terminación elegante (`SIGTERM`).
  - `⌥↵` (Option + Return): Cierre forzoso (`SIGKILL`).

### 6. 🛠️ Utilidades para Desarrolladores Offline Integradas (DevTools)
Realiza operaciones comunes de desarrollador en milisegundos sin abrir utilidades web ni instalar paquetes CLI:
- **`uuid`**: Genera un UUID v4 criptográficamente aleatorio.
- **`b64 <texto>`** / **`b64d <base64>`** (o **`b64 decode <base64>`**): Codifica y decodifica Base64.
- **`urlencode <url>`** / **`urldecode <url>`**: Codificación porcentual de URL.
- **`hash <texto>`** / **`hash sha256|sha1|md5 <texto>`**: Sumas de comprobación criptográficas instantáneas: las tres a la vez, o solo el algoritmo indicado.
- **`jwt <token>`**: Decodifica e imprime bonitamente los encabezados y la carga útil de JWT.
- **`json <raw>`**: Formatea, sangra y valida JSON minificado.
- **`epoch`** / **`now`**: Marca de tiempo Unix actual; **`epoch <marca>`** la convierte en una fecha legible y **`epoch 2024-01-15 10:30`** hace lo inverso (hora local, o ISO 8601 con zona horaria).
- **`#3498db`**: Muestra de vista previa de color en vivo con copia de Hex, RGB y HSL con un solo clic.

### 7. 🔐 Touch ID sin Interfaz para Sudo y Acciones Privilegiadas
Ejecuta acciones de mantenimiento privilegiadas (`Flush DNS Cache`, `Purge Inactive Memory`) con autenticación biométrica de huellas dactilares:
- **Sin Ventanas Emergentes de Terminal**: Se ejecuta a través de una pseudo-terminal (PTY) en segundo plano invocando `pam_tid.so` de macOS para una autenticación instantánea con Touch ID.
- **Alternar Touch ID para Sudo en Terminal**: Una Acción Rápida con búsqueda (escribe `touch id` o `sudo`) que edita `/etc/pam.d/sudo_local`, tras una solicitud de autorización de administrador, para que tus comandos `sudo` habituales en la terminal también puedan usar Touch ID. Su subtítulo indica si Touch ID para sudo está habilitado actualmente.

### 8. 📜 Historial de zsh y Comandos Fijados (`⌘P` / `⌘⇧P`)
- Busca en tu `~/.zsh_history` local (o `$HISTFILE` personalizado) con clasificación instantánea en menos de un milisegundo.
- Presiona **`⌘P`** en cualquier comando del historial para fijarlo en la parte superior de tu lanzador.
- Presiona **`⌘⇧P`** para administrar, reordenar o eliminar comandos fijados.

### 9. 📦 Copia de Seguridad de Ajustes y Sincronización entre Máquinas
- Usa **Export Settings…** / **Import Settings…** en la barra de menús para guardar tu configuración en un archivo JSON limpio y restaurarla después. Incluye comandos personalizados, comandos de shell fijados, historial de búsqueda y ranking, aplicaciones recientes y preferencias (tecla de acceso rápido global, inicio al iniciar sesión, visibilidad del ícono de la barra de menús, ventana del historial del navegador). No se incluyen los fragmentos de texto, tu terminal preferida ni tu motor de búsqueda web predeterminado.
- La sanitización automática de rutas reemplaza `/Users/username` con `~` para que las configuraciones puedan compartirse fluidamente entre Macs de trabajo y personales.

### 10. 🔄 Actualización Automática Integrada
- Consulta las Releases de GitHub en segundo plano (poco después del inicio y al abrir el menú de la barra de menús) y ofrece la nueva versión desde la barra de menús. Tras una comprobación correcta espera un día antes de la siguiente; una comprobación fallida (sin conexión, límite de peticiones) se repite en el siguiente inicio o al abrir el menú. **`Check for Updates...`** la ejecuta al instante, y **`Automatically Check for Updates`** desactiva por completo las comprobaciones automáticas.
- Se instala en el sitio: Lightspot descarga la compilación de la release para este Mac (`Lightspot-arm64.zip` en Apple silicon, `Lightspot-x86_64.zip` en Intel, según el procesador del propio Mac, así que una copia que se ejecuta con Rosetta pasa a la compilación nativa; `Lightspot.zip`, la app universal, si la release no las tiene), la verifica, sustituye su propio paquete, arranca la nueva versión y se cierra cuando esta ya está en marcha, sin ningún momento sin Lightspot. **`Skip This Version`** silencia una release concreta sin desactivar las comprobaciones. Los actualizadores de Lightspot 1.2.0 a 1.3.9 descargan el `Lightspot.zip` universal, así que traen 1.4.0 como app universal; las actualizaciones posteriores son la compilación para tu Mac.
- Cada descarga pasa por un filtro: solo HTTPS, solo hosts de GitHub (revalidados tras las redirecciones), el paquete descomprimido debe llevar el identificador de paquete de Lightspot, un ejecutable funcional con código para el procesador de este Mac (leído de su cabecera Mach-O) y exactamente la versión anunciada, y nunca se acepta una compilación anterior a la ya instalada.
- Las releases están firmadas de forma ad-hoc (este proyecto no incluye un Developer ID), por lo que no hay firma de código que verificar: las comprobaciones anteriores y HTTPS hacia GitHub son todo el modelo de confianza, el mismo que `install.sh` ya requiere.

### 11. 🧹 Clean Dev Mac (`cdm`)
[CleanDevMac](https://github.com/cleandevmac/cdm) (`cdm`) encuentra las cachés de desarrollo y los artefactos de compilación que llenan tu disco; Lightspot lo ejecuta dentro del panel. Escribe `cdm`, `clean dev mac` o el nombre de una caché (`derived data`, `npm cache`) y pulsa **`↵`**:
- **Primero mide, nada se marca a ciegas**: cada categoría que conocen las reglas de cdm (DerivedData de Xcode, Go, npm/pnpm/Yarn, Gradle, Cargo, pip/uv, CocoaPods, JetBrains, cachés de navegadores y apps Electron, imágenes de Android sin usar, la caché de módulos de clang, las copias de Chrome que deja un navegador que se cerró de golpe, …) se mide como lo haría `du`, se ordena de mayor a menor y se marcan los valores seguros por defecto de cdm. El panel muestra el disco antes y después. Como cdm, añade dos notas cuando vienen al caso: lo que liberaría un reinicio (swap, las carpetas temporales que macOS vacía al arrancar, archivos borrados que las apps aún mantienen abiertos) cuando supera el espacio libre, y, cuando el historial de sesiones de Claude Code pasa de 1 GB con transcripciones más antiguas que su límite, el ajuste `desktopSessionCleanupPeriodDays` con el que Claude Code borra también las sesiones de Claude Desktop y Cowork. Lightspot nunca cambia ese ajuste por ti.
- **Piezas de SDK instaladas y sesiones antiguas, sin marcar**: también llegan las filas opcionales de cdm: los toolchains de PlatformIO, el NDK de Android, CMake y las fuentes del SDK, todas las versiones de build-tools y plataformas de Android salvo la más reciente, la imagen de sistema de un AVD que nadie ha arrancado en 60 días (la fila nombra el AVD, que no arrancará hasta reinstalar la imagen) y las sesiones de Claude Code sin tocar en 30 días, que solo van a la Papelera. Cada fila dice cómo vuelve.
- **También tus repositorios**: tras las cachés, Clean Dev Mac pregunta, como cdm, si quieres escanear tus repositorios de código en busca de restos de compilación y dependencias; pulsa **`⇥`**. Obtienes una fila sin marcar por repositorio con sus `node_modules`, `dist`, `build`, `target`, `__pycache__` y otros archivos ignorados por git. No se ofrece nada que el propio git del repositorio no ignore (un `build/` versionado se queda), los archivos `.env*` nunca se ofrecen, ni tampoco una carpeta que contenga otro repositorio. Las carpetas regenerables se borran; los demás archivos ignorados van a la Papelera.
- **Teclas**: `↑↓` selecciona (la fila seleccionada muestra sus rutas y tamaños), `Space` marca, `⇥` escanea tus repositorios, `↵` muestra el plan detallado y `↵` otra vez limpia, `⌥↵` muestra la caché seleccionada en Finder, `Esc` vuelve atrás.
- **Las mismas reglas que cdm**: Lightspot lee los archivos de reglas de cdm (tu `~/.cleandevmac/rules` si lo tienes; si no, las reglas en vivo de cdm en GitHub; si no, la copia incluida en la app), así que cualquier caché que cdm aprenda a limpiar, Lightspot también la limpia.
- **La misma seguridad que cdm**: cada ruta pasa la comprobación de seguridad de cdm antes de que ocurra nada: debe estar dentro de tu carpeta de inicio, o en tus propias carpetas temporales de `/private/var/folders` donde las reglas de cdm nombran una caché (con los enlaces simbólicos resueltos en ambos casos), y `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, `~/.ssh`, `~/.gnupg` e iCloud Drive nunca se tocan. Antes de limpiar, el plan nombra las apps aún abiertas que reescribirían sus cachés (ciérralas primero). Cada limpieza queda registrada en `~/.cleandevmac/clean.log`, el mismo registro que lleva cdm.
- **El resto, a una tecla**: Docker / Podman, los toolchains de Rust y su documentación offline (se quitan con `rustup`), los datos de apps desinstaladas y las cachés de apps en sandbox necesitan un motor de contenedores, rustup o un análisis de tus apps, así que `⌘↵` ejecuta cdm completo en tu terminal preferida, directamente desde su última versión.

### 12. 📦 Instalaciones con una tecla: setup-zsh, MacStats y herramientas de desarrollo
Escribe `install` (o el nombre de una herramienta) y pulsa **`↵`**: Lightspot ejecuta el instalador propio de la herramienta en tu terminal preferida, así ves cada paso.
- **Install setup-zsh** ([setup-zsh](https://github.com/openhoangnc/setup-zsh)): autosugerencias de zsh que buscan en cualquier parte de tu historial, resaltado de sintaxis y un prompt que muestra el estado de git. Ejecuta `setup.sh` y luego abre un zsh nuevo que lo carga. Una vez instalado, la misma fila lo actualiza.
- **Install MacStats** ([mac-stats](https://github.com/openhoangnc/mac-stats)): CPU, RAM, velocidad de red y temperatura de la CPU en la barra de menús. Ejecuta su `install.sh`, que lo coloca en `/Applications` y lo inicia.
- **Install Dev Tools**: el menú `install-dev-tool` de setup-zsh: Homebrew, Node.js, Go, Python y uv, Rust, JDK, Bun, Git, VS Code, Chrome, OrbStack, Android Studio y más, además de actualizar tus paquetes globales. Escribe `install node`, `install go`, `install rust`…; sin setup-zsh, la fila lo instala primero.
- Cada fila indica si la herramienta ya está instalada; **`⌥↵`** abre su página de GitHub.

### 13. 🎛️ Ajustes de macOS
Los comandos `defaults write` que normalmente copiarías de un README de dotfiles, como acciones rápidas. Cada interruptor lee el ajuste actual y lo invierte, así que la misma fila lo revierte:
- **Dock**: **Clear Dock Icons** (guarda los iconos del Dock en `~/Library/Application Support/Lightspot/dock-backup.plist`, luego quita todas las apps fijadas y reinicia el Dock), **Restore Dock Icons** (los vuelve a poner donde estaban, conserva los iconos añadidos después y borra la copia solo cuando el Dock reiniciado los muestra; los dos esperan a que un Dock recién arrancado se estabilice y lo intentan una vez más si un reinicio pierde el cambio), **Toggle Dock Auto-Hide**, **Toggle Instant Dock Auto-Hide** (sin retardo), **Toggle Dock Recent Apps**, **Restart Dock**.
- **Finder**: **Toggle Hidden Files in Finder**, **Toggle File Extensions in Finder**, **Toggle Finder Path Bar**, **Toggle Desktop Icons** (útil antes de compartir pantalla), **Toggle .DS_Store on Network & USB Drives**, **Restart Finder**.
- **Escritura y capturas**: **Toggle Press-and-Hold Accents** (mantener una tecla la repite), **Toggle Smart Quotes & Dashes**, **Toggle Screenshot Shadows**.

Ninguno pide la contraseña de administrador. Restore Dock Icons deshace Clear Dock Icons, y cada interruptor se deshace a sí mismo. Para 41 ajustes más, cada uno con su estado y su deshacer, mira Settings de Mac Tweaks (sección 14).

### 14. 🧰 Mac Tweaks (`free up space`)
Mac Tweaks libera el espacio que macOS guarda, desactiva Apple Intelligence para todas las cuentas de este Mac, cambia 41 ajustes de macOS con opción de deshacer y desactiva los agentes y daemons de launchd que instalaron otras apps. Escribe `mac tweaks`, `free up space`, `debloat` o lo que quieras quitar (`remove garageband`, `macos installers`, `time machine snapshots`, `app caches`) y pulsa **`↵`**, o elige **Mac Tweaks...** en la barra de menús, justo debajo de **Clean Dev Mac...**; `turn off apple intelligence` lo abre en Apple Intelligence; `stop music from opening`, `turn off apple music`, `turn off mac analytics`, `turn off personalized ads` o `show the library folder` en Settings; y `turn off background items`, `turn off launch agents`, `disable launch agents`, `turn off google updater`, `leftover launch agents` o `launch daemons` en Background Items. Se abre sobre los resultados, como Clean Dev Mac, con una pestaña por sección, y cada sección muestra un plan detallado antes de cambiar nada y un recibo después. (Los interruptores `defaults` de la sección 13 son acciones rápidas, no forman parte de Mac Tweaks.)
- **Free Up Space** mide cada fila como lo hace Clean Dev Mac; una fila sin nada que ofrecer se oculta, nunca se ofrece nada de 0 bytes y las tres primeras filas vienen marcadas:
  - **macOS installers**: los `Install macOS*.app` antiguos de `/Applications`, solo con el identificador de paquete de Apple (`com.apple.InstallAssistant…`).
  - **iPhone and iPad updates**: las actualizaciones que descargó Finder, en `~/Library/iTunes/iPhone Software Updates` y `iPad Software Updates`.
  - **Unavailable simulators**: simuladores cuyo runtime ya no está instalado, mediante el `simctl` de Xcode; nunca `/usr/bin/xcrun`, así que un Mac con solo las Command Line Tools no tiene esta fila ni ve abrirse su instalador.
  - **Time Machine local snapshots**: las instantáneas locales, mostradas como un recuento (macOS no da su tamaño).
  - **Aerial videos**: los vídeos aéreos que comparten todas las cuentas del Mac (`/Library/Application Support/com.apple.idleassetsd/Customer`); las copias propias de cada cuenta son una fila de Clean Dev Mac.
  - **GarageBand and its sound library**: GarageBand y su biblioteca de sonidos; la biblioteca se queda mientras Logic Pro o MainStage estén instalados.
  - **iMovie**, **Keynote**, **Numbers** y **Pages**, solo los de Apple: un `Pages.app` que no sea de Apple se queda.
  - **App caches**: las cachés de `~/Library/Caches`, salvo las de macOS (`com.apple.*` y los demás nombres que escribe macOS), la de Lightspot y todas las que cubre una regla de Clean Dev Mac, para que las dos superposiciones nunca cuenten la misma carpeta. Mac Tweaks lee esas reglas de la memoria de Clean Dev Mac, de `~/.cleandevmac/rules` o de la copia incluida en la app, y nunca las descarga.
  - Tres filas de enlace: **Apple Intelligence models** (su tamaño, una vez escaneada esa sección y mientras estén en el disco) abre la sección Apple Intelligence, **Developer caches and project junk** abre Clean Dev Mac y **More in System Settings** abre Almacenamiento en los Ajustes del Sistema.
- **Adónde van los archivos de Free Up Space**: a la Papelera, así que puedes sacarlos mientras no la vacíes. Los simuladores (`simctl delete unavailable`) y las instantáneas (`tmutil deletelocalsnapshots`) se borran al momento, y sus filas lo indican; las copias de seguridad de tu disco de copias no se tocan. Su recibo dice lo que se liberó, lo que fue a la Papelera, lo que se borró y lo que se quedó y por qué, por ejemplo una app que macOS no deja mover a Lightspot sin el permiso App Management (`⌥↵` la muestra en Finder).
- **Apple Intelligence** (Apple silicon, macOS 15.1 o posterior): una fila por cada función que tiene este macOS (Siri, ChatGPT y otras extensiones de IA, Writing Tools, Genmoji, Image Playground, los resúmenes de Mail, de notificaciones, de Mensajes, de Safari y de Notas, las predicciones de texto en línea, Spatial Photos, Photos Clean Up y la compleción de código predictiva de Xcode), cada una con su estado (On, Off, Locked off, Managed, Unknown) y los modelos que necesita. Todas empiezan marcadas, lo que significa desactivar; desmarca las que quieras conservar. Al aplicar se instala un único perfil de configuración, **Lightspot Mac Tweaks**, que apruebas en Ajustes del Sistema › General › Gestión de dispositivos (Lightspot lo abre y espera hasta 10 minutos; `Esc` deja de esperar): desactiva las funciones marcadas para todas las cuentas de este Mac y dirige la descarga de sus modelos a un puerto local cerrado. Solo cuando el perfil está en vigor pide Lightspot al servicio de recursos de Apple que borre los modelos que ninguna función conservada necesita, lo reintenta mientras macOS aún los usa y comprueba el inventario hasta que desaparecen. **Finish removing the models** termina el trabajo tras un reinicio; **Turn Apple Intelligence back on** quita el perfil, o lo sustituye por uno sin Apple Intelligence cuando también contiene ajustes de Settings. Una función que fija otro perfil se queda como está, y el perfil de RemoveMacAI deja la sección en solo lectura. Lightspot nunca llama por sí mismo al framework privado de recursos: cada lectura y cada borrado se ejecutan en un proceso hijo de vida corta, `Lightspot --asset-service`, así que los 9–11 MB del framework nunca se quedan en la memoria de Lightspot.
- **Settings**: 41 ajustes en seis grupos (Privacy, Annoyances, Apple apps, Finder, Dock and windows, Typing), cada uno con su estado en este Mac: On, Off, Partly, Managed (lo fija otro perfil, así que Lightspot no lo toca) o Not on this macOS. Nada empieza marcado; los preajustes **Recommended** y **Maximum privacy** marcan los suyos que aún están desactivados. Los ajustes locales pasan por cfprefsd y se vuelven a leer, y Finder, el Dock o SystemUIServer se reinician una vez cuando un cambio lo necesita. Mac Analytics, los anuncios personalizados, Mejorar Siri y Dictado, Mejorar la búsqueda, los resultados de internet de Spotlight, las sugerencias de Look Up y de búsqueda de Safari, Game Center, la duplicación del iPhone, Apple Music y la Book Store van en el mismo perfil, que conserva su parte de Apple Intelligence tal como está, y el plan dice que el perfil se aplica a todas las cuentas de este Mac. Apple Music en tres niveles: el servicio Apple Music, la entrada de arranque de Música para que nada pueda abrirla, y las teclas de reproducir, pausar y saltar (`com.apple.rcd`). La fila seleccionada y el plan muestran cada cambio como un comando (`defaults write …`, `launchctl …`, `chflags …`, `profile: …`).
- **Background Items**: una fila por cada `.plist` de `~/Library/LaunchAgents`, `/Library/LaunchAgents` y `/Library/LaunchDaemons`, salvo los de macOS (`com.apple.*`), los plists sin `Label` (los stubs vacíos que deja Keystone de Google) y los archivos que empiezan por punto. Cada fila muestra la app a la que pertenece el elemento (la `.app` donde está su programa, lo que ejecuta o la app que nombra su `AssociatedBundleIdentifiers`, así que un asistente de Docker aparece como «Docker»), su etiqueta y lo que ejecuta (nunca sus demás argumentos, que pueden contener tokens), y su estado: On, Off, Not loaded (puede que los ítems de inicio de los Ajustes del Sistema lo hayan desactivado) o Unknown, leído con `launchctl print-disabled` y `launchctl print`. Los actualizadores (`update` en la etiqueta o en el nombre del programa) llevan la etiqueta **Updater**; una fila que no es ni actualizador ni sobrante avisa de que desactivar el elemento puede hacer que su app deje de funcionar. `Space` marca el cambio de la fila: desactivar el elemento (`launchctl disable` y después `bootout`), volver a activarlo (`enable` y después `bootstrap`) o, si es un **Leftover** cuyo programa macOS confirma que ya no existe, detenerlo y mover su plist a la Papelera; los sobrantes son las únicas filas que vienen marcadas. Un programa en una carpeta que macOS protege o en otro disco, y un intérprete que recibe código en línea (`-c`, `-e`), nunca se dan por desaparecidos, y un sobrante cuyo plist es un enlace simbólico o comparte etiqueta con otro plist nunca se mueve. Tus propios agentes cambian con tu usuario; el cambio de cada daemon y cada movimiento que solo puede hacer un administrador comparten una única petición de administrador, y el cambio de un daemon vale para todas las cuentas de este Mac, mientras que desactivar o activar un elemento de `/Library/LaunchAgents` solo vale para tu cuenta. Solo cuenta lo que launchd confirma: el recibo dice lo que sigue en marcha (un daemon hasta que reinicias, un agente hasta que cierras sesión) o no se cargó. Un plist que es un enlace simbólico se sigue carpeta a carpeta, nunca hacia una carpeta que macOS protege, otro disco o `~/Library/CloudStorage`. La última fila abre los ítems de inicio en los Ajustes del Sistema.
- **Deshacer**: antes de cambiar un ajuste por primera vez, Lightspot guarda el valor que encontró en `~/Library/Application Support/Lightspot/tweaks-journal.json`, y el cambio solo se hace una vez guardado. Marcar una fila On la deshace: vuelve a ese valor, o al valor por defecto de macOS cuando Lightspot no guardó ninguno, como indica el plan. **Undo everything Lightspot changed** devuelve todo lo registrado y quita el perfil tras una sola petición de administrador. También vuelve a activar los elementos en segundo plano que desactivó Lightspot (registrados antes de desactivarlos) y solo vuelve a poner en marcha lo que estaba en marcha, con sus daemons en esa misma petición. Una entrada cuyo plist ya no existe no ejecuta nada y se descarta, y launchd mantiene su interruptor desactivado. Un ajuste aplicado en parte es tuyo y solo se completa, nunca se deshace. Los archivos de la Papelera y la copia de Clear Dock Icons no entran.
- **Contraseña solo cuando tiene que actuar un administrador**: para borrar instantáneas, para mover un elemento que pertenece a otro usuario o que los permisos de una carpeta no te dejan mover (su fila dice **May ask for password**), para desactivar o activar un daemon y para quitar el perfil de Lightspot. Lo que una aplicación necesita como administrador va en un único script que se ejecuta una sola vez, con Touch ID para sudo o con el diálogo de contraseña. Instalar el perfil lo haces tú mismo en los Ajustes del Sistema.
- **Teclas**: `↑↓` selecciona (la fila seleccionada muestra sus elementos, modelos o comandos), `Space` marca (en un preajuste, sus filas; en Background Items, el cambio de la fila), `⇥` / `⇧⇥` cambian de sección, `↵` muestra el plan detallado y `↵` otra vez lo aplica, `⌥↵` muestra en Finder el primer elemento de una fila de Free Up Space o el plist de un elemento en segundo plano, `Esc` vuelve atrás, deja de esperar a los Ajustes del Sistema y luego cierra.
- **Recibos**: cada aplicación termina con uno, con una marca verde cuando hizo lo que se pidió. Aplicar sigue en marcha aunque el panel se oculte (cuando una petición de contraseña o los Ajustes del Sistema toman el foco), y al volver a abrir Mac Tweaks ves el progreso y después el recibo. Cada ejecución queda registrada en `~/Library/Application Support/Lightspot/mac-tweaks.log`. Una sección cuyo escaneo cambió la aplicación de otra vuelve a escanear: Apple Intelligence y Settings comparten el perfil, y Settings y Background Items el registro de deshacer.
- **Nunca se toca**: Free Up Space nunca toca nada bajo `/System`, `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, iCloud Drive, `~/Library/Containers`, `~/Library/Group Containers`, Mail, Mensajes ni las copias de seguridad del iPhone (`MobileSync`), ni nada dentro de un paquete de app: cada ruta debe estar directamente en una de las carpetas fijas de su fila, tal como está escrita y con los enlaces simbólicos resueltos, no puede ser ella misma un enlace simbólico, y vuelve a pasar esa comprobación justo antes de moverse. Apple Intelligence y Settings no tocan nada que fije otro perfil de configuración. Background Items nunca lista los elementos de macOS ni cambia nada fuera de sus tres carpetas, ejecuta `launchctl` directamente, nunca a través de una shell, y como root solo actúa sobre una etiqueta y un plist que encontró el escaneo. Mac Tweaks no lee nada hasta que lo abres y no hace ninguna petición de red.
- **Créditos**: Free Up Space, Apple Intelligence, Settings y Background Items adaptan la lógica de [RemoveMacAI](https://github.com/omlahore/RemoveMacAI), de omlahore (Licencia MIT). Su trabajo sobre Apple Intelligence se basa en [pared](https://github.com/4evy/pared), de 4evy (Licencia MIT), al que siguen el puente de Lightspot con el servicio de recursos, su catálogo de modelos y su bloqueo de descargas. Consulta [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

---

## ✨ Capacidades Adicionales Integradas

- **UI Exacta de Spotlight de macOS**: Píldora de ardilla translúcida flotante con expansión animada y panel de vista previa (`NSVisualEffectView`).
- **HUD de Hardware Mach / IOKit**: Diagnóstico de hardware instantáneo sin subprocesos (`sys`, `cpu`, `ram`, `memory`, `disk`, `battery`, `uptime`, `specs`, `resources`):
  - Carga de CPU multinúcleo normalizada %
  - RAM Física Activa, Cableada, Comprimida y Total
  - Almacenamiento libre y total del SSD de arranque
  - Porcentaje de batería y estado de carga
- **Matemáticas Inteligentes y Conversiones Relajadas**: Analizador matemático de descenso recursivo completo que admite unidades, monedas y bases numéricas:
  - Matemáticas: `(25 * 4) + sqrt(144)`, `2^16`, `log(1000)`
  - Unidades: `100km in mi`, `72F in C`, `16GB in MB`
  - Moneda: `$100 in EUR`, `50 GBP in USD`
  - Bases numéricas: `0xFF in dec`, `255 in hex`, `0b1010 in dec`
- **Marcadores, Historial y Pestañas del Navegador Predeterminado**: Integración sin redundancia solo para tu navegador predeterminado activo (**Chrome**, **Safari**, **Firefox**, **Arc**, **Brave**, **Edge**). Los marcadores y el historial reciente se leen de los propios archivos del navegador (el historial abarca los últimos 3 o 7 días, 7 por defecto, o se puede desactivar en **Browser History** de la barra de menús); las pestañas abiertas se consultan en Safari y en navegadores basados en Chromium.
- **Portapapeles Efímero en Memoria**: Búfer de anillo volátil solo en RAM (hasta 50 elementos) al que se accede mediante `clip <query>`. Nunca escribe en el disco y filtra estrictamente los administradores de contraseñas (`1Password`, `Bitwarden`).
- **Enlaces Profundos de Ajustes del Sistema de macOS**: 46 enlaces profundos directos que abren paneles de ajustes específicos de macOS (`x-apple.systempreferences:...`), encontrados con los mismos términos que usa la búsqueda de Ajustes del Sistema (`night shift`, `lockdown mode`, `sticky keys`), en los idiomas de tu sistema. En macOS 27.2, donde los Ajustes del Sistema pueden cerrarse sin que LaunchServices lo note durante un minuto o más, Lightspot abre el panel en unos Ajustes del Sistema nuevos en lugar del aviso de que ya no están abiertos.
- **Búsqueda Web Multimotor**: Atajos de prefijo integrados: `g` (Google), `gh` (GitHub), `so` (StackOverflow), `npm`, `crates`, `wiki`, `mdn`, `yt`, `ddg`, además de `brew <fórmula>`, que abre la página de esa fórmula en formulae.brew.sh en lugar de ejecutar una búsqueda.

---

## 🛑 Gestión Completa de Spotlight de macOS

Lightspot incluye automatizaciones integradas en la barra de menú para deshabilitar o rehabilitar el Spotlight integrado de Apple:

1. **Atajo de Spotlight (`⌘Space`)**: Deshabilita o restaura los atajos de Spotlight predeterminados de Apple, tanto `⌘Space` («Mostrar la búsqueda de Spotlight») como `⌥⌘Space` («Mostrar la ventana de búsqueda del Finder»), sin requerir root. El cambio se escribe a través del demonio de preferencias, se verifica releyéndolo y se aplica de inmediato (sin cerrar sesión); además, Lightspot reclama `⌘Space` para sí mismo en cuanto macOS lo libera.
2. **Proceso en Segundo Plano (`com.apple.Spotlight`)**: Deshabilita o habilita el agente de la GUI en segundo plano de Spotlight a través de `launchctl`. Al habilitarlo también carga e inicia el agente, así que Spotlight vuelve sin cerrar sesión.
3. **Indexación de Archivos (`mdutil`)**: Apaga por completo la indexación de metadatos del sistema de archivos (`mds` / `mds_stores`) en todos los volúmenes montados.
4. **Acciones Maestras de 1 Clic**:
   - **`Disable Everything (Shortcut + Process + Indexing)...`**: Apaga por completo Spotlight de Apple para recuperar CPU, RAM, espacio en disco y `⌘Space`.
   - **`Restore Default Spotlight...`**: Revierte cada ajuste de nuevo a los valores predeterminados de fábrica de macOS en cualquier momento.

---

## 🚀 Construcción e Instalación (No Requiere Xcode)

### 📦 Opción A: Instalación en una sola línea (Recomendada)
Descarga e instala la última versión precompilada directamente. Cada release incluye `Lightspot-arm64.zip` (Apple silicon, unos 1,6 MB) y `Lightspot-x86_64.zip` (Intel, unos 1,75 MB), que el instalador y el actualizador eligen para tu Mac, `Lightspot.zip`, la app universal (unos 2,9 MB), y `Lightspot.app.dSYM.zip`, los símbolos para leer los informes de fallos:
```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-lightspot/main/install.sh | bash
```

### 🛠️ Opción B: Construir desde el Código Fuente (Repositorio Local)
```bash
# 1. Compilar paquete de lanzamiento
./build.sh
# o: make build

# 2. Ejecutar directamente
./run.sh
# o: make run

# 3. Instalar en /Applications (o en ~/Applications con --user)
./install.sh
# o: make install

# 4. Desinstalar
./uninstall.sh
# o: make uninstall
```

`./build.sh` compila cada arquitectura con optimización completa en tiempo de enlace (LTO) y elimina los nombres de los símbolos locales, que guarda en `build/Lightspot.app.dSYM`: el binario universal de 1.4.0 ocupa 5,1 MB, un 42 % menos que los 8,8 MB de 1.3.9, y 2,2 MB solo para Apple silicon (2,9 MB para Intel).

### 4. Pruebas y Verificación
Lightspot no tiene un target de XCTest. Tres scripts independientes en `scripts/` se compilan al vuelo junto con las fuentes y se ejecutan desde la raíz del repositorio: un ejecutor de pruebas de lógica y motor (83 bloques de pruebas), un verificador del sistema en vivo (15 secciones, 204 comprobaciones en el Mac del desarrollador con macOS 27.2; algunas se omiten si, por ejemplo, no hay historial de zsh o VS Code instalado, o no se puede acceder a GitHub) y una comprobación que aloja fuera de pantalla la superposición real de Mac Tweaks con escaneos de solo lectura y la lleva, sección por sección, por reescaneos y cambios de sección:
```bash
# Pruebas de lógica central y motor (83 bloques de pruebas)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift && /tmp/test_engine

# Comprobaciones del sistema en vivo (15 secciones, 204 comprobaciones en macOS 27.2)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify

# La superposición de Mac Tweaks, fuera de pantalla (cerca de un minuto)
swiftc -parse-as-library -o /tmp/overlay_check scripts/overlay_check.swift $(find Sources/Lightspot -name '*.swift' ! -name AppMain.swift) && /tmp/overlay_check
```

---

## ⌨️ Atajos y Navegación

| Tecla | Acción |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** / **`⌥Space`** / **`⌃Space`** | Invocar o descartar Lightspot en cualquier lugar (configurable en la barra de menú) |
| **`↓` / `↑`** | Navegar a través de los resultados de búsqueda |
| **`Return` (`↵`)** | Abrir la aplicación seleccionada, proyecto en IDE, ejecutar comando o copiar cálculo |
| **`⌘Return` (`⌘↵`)** | Abrir proyecto seleccionado en la Terminal preferida |
| **`⌥Return` (`⌥↵`)** | Revelar proyecto en Finder / Forzar el cierre del proceso seleccionado (`SIGKILL`) / Abrir la página de GitHub de un instalador / Mostrar en Finder el primer elemento de una fila de Mac Tweaks |
| **`⌘P`** | Fijar o desfijar comando del Historial de la Terminal seleccionado |
| **`⌘⇧P`** | Abrir la superposición del administrador de comandos fijados |
| **`⌘⇧C`** | Abrir la superposición del administrador de comandos personalizados |
| **`Space`** | Marcar o desmarcar una categoría en Clean Dev Mac o una fila en Mac Tweaks |
| **`Tab` (`⇥`)** | Escanear también tus repositorios de código en Clean Dev Mac / Siguiente sección en Mac Tweaks (`⇧⇥` la anterior) |
| **`⌘Y`** / **`⌘⇧H`** | Abrir la superposición del administrador de historial de búsqueda |
| **`Escape`** | Descartar superposiciones, limpiar el campo de búsqueda o cerrar Lightspot |
| **Clic Afuera** | Descarta automáticamente el panel flotante |

El atajo para invocarlo es el que elijas entre los cuatro en **Shortcut**, en la barra de menús. macOS asigna `⌃Space` a «Seleccionar la fuente de entrada anterior», así que, si lo eliges, la pulsación también cambiará tu fuente de entrada; el submenú **Shortcut** indica qué atajo del sistema ya ocupa la combinación elegida.

---

## 🔒 Garantías de Privacidad y Seguridad

- **Cero Indexación de Archivos**: Lightspot nunca indexa tus archivos personales, documentos, descargas o repositorios de código. Clean Dev Mac mide solo las carpetas de caché que nombran las reglas de cdm y los pocos sitios que necesitan sus dos notas (ver más abajo), solo mientras lo tienes abierto, y no guarda nada salvo los tamaños; nunca lee los contenedores sandbox de otras apps. Para sus filas de Android y de Claude Code lee además las fechas de los archivos de tus carpetas de AVD y de `~/.claude/projects`, y los pequeños archivos de `~/.claude/sessions` que nombran las sesiones en curso; nunca lo que dice una transcripción. Para las copias de Chrome que deja un navegador que se cerró de golpe, las enumera en tu propia carpeta temporal y lee cuándo arrancaron tus apps abiertas. Para las dos notas de cdm lee cuánta swap está en uso, mide las carpetas temporales que macOS vacía al arrancar y `~/.claude/projects`, pide a `lsof` los archivos borrados que tus apps aún mantienen abiertos (solo guarda el total y los nombres de las tres apps que más ocupan) y lee dos claves de `~/.claude/settings.json` (`cleanupPeriodDays`, `desktopSessionCleanupPeriodDays`), que nunca modifica. Cuando le pides que escanee tus repositorios (`⇥`), busca repositorios git en tu carpeta de inicio, hasta seis niveles, sin entrar en `~/Library`, `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies` ni `~/Music`, y pregunta al git de cada repositorio qué archivos ignora. Mac Tweaks lee una lista fija de sitios, solo de la sección que abres. Free Up Space: los nombres de `/Applications` y el `Info.plist` de los Install macOS y de GarageBand, iMovie, Keynote, Numbers y Pages que haya allí; el contenido de `~/Library/iTunes/iPhone Software Updates` y `iPad Software Updates`, de `/Library/Application Support/com.apple.idleassetsd/Customer` y de `~/Library/Caches`, con el tamaño y el propietario de cada elemento que ofrece; las tres carpetas de la biblioteca de GarageBand y si Logic Pro o MainStage están instalados; la lista de simuladores no disponibles del `simctl` de Xcode y las fechas de las instantáneas locales que da `tmutil`; el índice de fondos de pantalla (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) cuando hay vídeos aéreos que ofrecer; y las reglas de Clean Dev Mac. Al aplicar, consulta los nombres de `~/.Trash` uno a uno y nunca lista la Papelera. Apple Intelligence: el inventario del servicio de recursos con los conjuntos de modelos y sus tamaños, que lee el proceso auxiliar de vida corta sin leer ninguna carpeta (solo durante un borrado, el número de entradas de la carpeta de un conjunto en `/System/Library/AssetsV2`, nunca un listado), y los ajustes de las funciones y las marcas de los dos perfiles mediante cfprefsd. Settings: las preferencias y restricciones de sus 41 ajustes, los iconos del Dock y la marca del perfil mediante cfprefsd, la lista de servicios desactivados de launchctl, los números de inodo de Music.app y de su ejecutable, el atributo oculto de la carpeta Library y su registro de deshacer. Background Items: los nombres de `~/Library/LaunchAgents`, `/Library/LaunchAgents` y `/Library/LaunchDaemons` y cada `.plist` que hay en ellas, solo si es un archivo normal de 1 MiB como mucho, del que solo guarda la etiqueta, el programa, los argumentos, los identificadores de las apps asociadas y `Disabled` (los argumentos nunca se muestran ni se registran); `launchctl print-disabled` de tu cuenta y del sistema, y `launchctl print` de cada elemento, del que solo guarda el código de salida, porque su salida lista el entorno del trabajo; cada programa que nombra un plist, o el script que ejecuta un intérprete, consultado carpeta a carpeta y nunca dentro de una carpeta que macOS protege, de otro disco o de `~/Library/CloudStorage`; el propietario de cada plist; LaunchServices, para las apps que nombra un plist; y las entradas de elementos en segundo plano del registro de deshacer. Mientras el registro contiene elementos en segundo plano, Settings lee una vez las tres carpetas para el plan de Undo everything. Cuando un escaneo tiene más de cinco minutos, cerrar Mac Tweaks descarta lo que encontró y solo guarda el total de Free Up Space y lo que el escaneo de Apple Intelligence leyó sobre los modelos.
- **Portapapeles Efímero Solo en RAM**: El historial del portapapeles permanece exclusivamente en memoria volátil e ignora activamente los tipos ocultos/administradores de contraseñas (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`). Nunca se escribe en el disco, ni siquiera en el historial de búsqueda, que tampoco guarda el texto que copias de resultados de la calculadora, las herramientas de desarrollo o los fragmentos.
- **Aislamiento del Navegador Predeterminado**: Los marcadores, las pestañas abiertas y el historial reciente se leen localmente y únicamente de tu navegador predeterminado configurado, evitando el raspado entre navegadores.
- **Comandos Iniciados por el Usuario**: Tus comandos, scripts y acciones rápidas se ejecutan solo tras la acción explícita del usuario (`Return` o `⌘↵`).
- **Comandos de Administrador que se Ejecutan una Sola Vez**: Un comando privilegiado se ejecuta con `sudo` y Touch ID, o con el diálogo de contraseña de macOS, y desde la 1.4.0 nunca dos veces: primero imprime una marca aleatoria y, en cuanto esa marca muestra que sudo lo ha iniciado, su resultado es definitivo, así que un comando que falla con Touch ID ya no se vuelve a ejecutar tras el diálogo de contraseña. Después de la marca su entrada estándar es `/dev/null`, así que nada de lo que ejecuta se queda esperando en la terminal oculta. Los scripts que construye el propio Lightspot (el lote de administrador de Mac Tweaks, con cada argumento entre comillas simples) pasan por otra vía que los deja tal como están. El registro del sistema solo guarda si un comando privilegiado se ejecutó y su código de salida, nunca su texto, que puede contener rutas de tus archivos.
- **Cero Telemetría, Dos Servicios Que Tú Controlas**: Sin analíticas, sin rastreo, sin cuentas. Lightspot se comunica por su cuenta con exactamente dos servicios, y tú decides sobre ambos. El primero es GitHub, para las actualizaciones: un `GET` sin autenticar a la API pública de releases (`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`) con `User-Agent: Lightspot/<versión> (+https://github.com/openhoangnc/mac-lightspot)`, poco después del inicio y al abrir el menú de la barra de menús, pero no más de una vez al día tras una comprobación correcta (una comprobación fallida se repite en el siguiente inicio o al abrir el menú). Desactiva **`Automatically Check for Updates`** en la barra de menús y nunca se ejecutará por sí sola. Instalar una actualización que aceptaste descarga su zip desde GitHub (`User-Agent: Lightspot/<versión>`). Ambas pasan por una sesión efímera, así que ninguna respuesta ni cookie se guarda en el disco. Las versiones anteriores usaban en su lugar la sesión compartida de macOS (la comprobación de actualizaciones hasta la 1.2.0, la consulta de IP antes de la 1.2.0), que guardaba las respuestas en `~/Library/Caches/com.lightspot.app` y las cookies en `~/Library/HTTPStorages`; Lightspot borra esos restos al iniciarse, y el desinstalador también los elimina. El segundo es ipify: `GET https://api.ipify.org` (un servicio de terceros) para conocer tu IP pública, y solo cuando la pides: al escribir una consulta que la nombra (`ip`, `my ip`, `public ip`, `ipv4`) o al pulsar `Return` en la fila **IP Address**. ipify ve tu dirección IP y un user agent estándar de macOS, como cualquier servidor web. La respuesta se guarda en memoria durante 15 minutos y nunca se escribe en el disco. Al abrir **Clean Dev Mac** también se piden a GitHub los archivos de reglas de cdm (`GET https://raw.githubusercontent.com/cleandevmac/cdm/main/rules/index.json` y los archivos que enumera, con un user agent estándar de macOS, a través de una sesión efímera), como mucho una vez por hora; se quedan en memoria y, sin conexión, se usa la copia incluida en la app. Lo evitas por completo si guardas tus propias reglas en `~/.cleandevmac/rules`. Mac Tweaks no hace ninguna petición: lee las reglas de Clean Dev Mac de la memoria, de `~/.cleandevmac/rules` o de la copia incluida en la app, y nunca las descarga. Ejecutar cdm en la terminal (`⌘↵`) descarga su script desde la release de cdm en GitHub, como indican las instrucciones del propio cdm. Las filas de instalación funcionan igual: cada una ejecuta el instalador de su herramienta en tu terminal, y es ese script, no Lightspot, el que descarga desde GitHub. Las búsquedas web, las URL y los marcadores los abre tu navegador, y solo cuando pulsas `Return`.
- **Lo Que Se Escribe en el Disco**: Las preferencias propias de Lightspot (`UserDefaults`, en `~/Library/Preferences/com.lightspot.app.plist`), un archivo de bloqueo, archivos temporales mientras se instala una actualización, un recibo en el registro de cdm cuando limpias y los archivos pequeños de Mac Tweaks cuando aplicas algo allí:
  - Ajustes: `lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state` (último estado conocido de Spotlight, para las etiquetas del menú), `lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version` (comprobaciones automáticas de actualizaciones).
  - Lo que creas: `lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`.
  - Uso: `lightspot_recent_app_bundle_ids` (apps abiertas recientemente) y `lightspot_search_history`: las consultas que escribiste y los resultados que abriste (títulos, rutas de apps y proyectos, URL, comandos de shell), más los recuentos de selección para la clasificación. Revísalo o bórralo en el gestor del historial de búsqueda (`⌘Y`). Las selecciones del portapapeles, la calculadora y las herramientas de desarrollo nunca se registran; las de fragmentos y del informe de hardware solo conservan la consulta y un recuento, nunca el texto copiado.
  - `~/.cleandevmac/clean.log`, solo cuando limpias con Clean Dev Mac: lo que cada limpieza borró o movió a la Papelera, añadido al registro que lleva el propio cdm (limitado a 1 MiB, como el de cdm). Lo que confirmas en el limpiador se borra definitivamente, salvo las categorías marcadas como Trash, que van a la Papelera.
  - `~/Library/Application Support/Lightspot/mac-tweaks.log`, solo cuando aplicas algo en Mac Tweaks: cuándo empezó y terminó cada ejecución, lo que cambió, movió a la Papelera o borró, lo que se quedó y por qué, y cuánto liberó. Por encima de 1 MiB conserva los 256 KiB más recientes, como el registro de cdm. Los archivos que confirmas en Free Up Space van a la Papelera; los simuladores no disponibles y las instantáneas de Time Machine se borran definitivamente.
  - `~/Library/Application Support/Lightspot/tweaks-journal.json`, el registro de deshacer de Mac Tweaks: el valor que tenía cada ajuste antes de que Lightspot lo cambiara, y si cada elemento en segundo plano que desactivó estaba desactivado y cargado, guardado antes del cambio y eliminado al deshacerlo. Un registro que Lightspot no puede leer nunca se sobrescribe: se aparta como `tweaks-journal-unreadable-<fecha>-<id>.json`. Settings también escribe preferencias de otras apps (las de Finder, del Dock, del dominio global…), solo las que aplicas, cada una registrada antes.
  - `~/Library/Application Support/Lightspot/dock-backup.plist`, que escribe Clear Dock Icons antes de vaciar el Dock y que Restore Dock Icons elimina cuando los iconos vuelven.
  - `~/Library/Application Support/Lightspot/LightspotMacTweaks.mobileconfig`, solo mientras una aplicación espera a que apruebes el perfil de Lightspot, y eliminado en cuanto se instala. El perfil, **Lightspot Mac Tweaks**, lo instalas tú en los Ajustes del Sistema y se aplica a todas las cuentas de este Mac; quitarlo allí deshace todo lo que cambió.
  - El desinstalador borra todo esto salvo los registros de deshacer y la copia del Dock, que conserva para que un Lightspot reinstalado pueda deshacer, y dice qué se queda y cómo deshacerlo; los elementos en segundo plano para todos los usuarios que desactivó Lightspot siguen desactivados en todas las cuentas.
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`, que impide que se inicie una segunda copia. Guarda el PID del proceso en ejecución y la ruta, el inodo y la fecha de modificación de su ejecutable, para que un nuevo inicio distinga la misma compilación de una más reciente.
  - Mientras se instala una actualización que aceptaste: la descarga, el paquete descomprimido y un pequeño script auxiliar en el directorio temporal de macOS (`NSTemporaryDirectory()`, carpetas `lightspot-update-…` y `lightspot-updater-…`), y la versión anterior guardada como `Lightspot.app.lightspot-old` junto a la app hasta que la nueva está en su sitio. El script auxiliar los borra todos al terminar.
  - **Export Settings** escribe una copia de seguridad JSON, con el historial de búsqueda incluido, solo en el archivo que elijas.
