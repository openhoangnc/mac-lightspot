# Lightspot 🔍

[English](README.md) | [简体中文](README_zh-CN.md) | [Español](README_es.md) | [日本語](README_ja.md) | [Français](README_fr.md)

> **Un reemplazo ligero y perfecto para Spotlight de macOS, construido en Swift puro, diseñado para desarrolladores y usuarios avanzados que desean velocidad instantánea sin la sobrecarga de la indexación de archivos.**

Lightspot reproduce fielmente el moderno diseño de píldora flotante y la estética de cristal translúcido de Spotlight de macOS (`NSVisualEffectView`). Bajo el capó, ofrece una capacidad de respuesta por debajo del milisegundo (< 1.0 ms de búsqueda) con **cero indexación de archivos en segundo plano**. En reposo, su único trabajo periódico es una comprobación ligera del portapapeles cada 0.6 s, y usa menos de **25 MB de RAM**.

![Captura de pantalla de Lightspot](screenshot.png)

---

## ⚡ Inicio Rápido

### 📦 Descarga e Instalación en una sola línea
Simplemente copia y pega este comando en tu Terminal para descargar, extraer e instalar automáticamente el último **Lightspot** en tu carpeta `/Applications`:

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
| **Almacenamiento en Disco** | 10 GB – 200 GB+ en caché oculta | 100 MB – 1 GB | **Sin índice ni caché** (tus ajustes en `UserDefaults` y un archivo de bloqueo) |
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
- Se instala en el sitio: Lightspot descarga la release, la verifica, sustituye su propio paquete, arranca la nueva versión y se cierra cuando esta ya está en marcha, sin ningún momento sin Lightspot. **`Skip This Version`** silencia una release concreta sin desactivar las comprobaciones.
- Cada descarga pasa por un filtro: solo HTTPS, solo hosts de GitHub (revalidados tras las redirecciones), el paquete descomprimido debe llevar el identificador de paquete de Lightspot, un ejecutable funcional y exactamente la versión anunciada, y nunca se acepta una compilación anterior a la ya instalada.
- Las releases están firmadas de forma ad-hoc (este proyecto no incluye un Developer ID), por lo que no hay firma de código que verificar: las comprobaciones anteriores y HTTPS hacia GitHub son todo el modelo de confianza, el mismo que `install.sh` ya requiere.

### 11. 🧹 Clean Dev Mac (`cdm`)
[CleanDevMac](https://github.com/cleandevmac/cdm) (`cdm`) encuentra las cachés de desarrollo y los artefactos de compilación que llenan tu disco; Lightspot lo ejecuta dentro del panel. Escribe `cdm`, `clean dev mac` o el nombre de una caché (`derived data`, `npm cache`) y pulsa **`↵`**:
- **Primero mide, nada se marca a ciegas**: cada categoría que conocen las reglas de cdm (DerivedData de Xcode, Go, npm/pnpm/Yarn, Gradle, Cargo, pip/uv, CocoaPods, JetBrains, cachés de navegadores y apps Electron, imágenes de Android sin usar, …) se mide como lo haría `du`, se ordena de mayor a menor y se marcan los valores seguros por defecto de cdm. El panel muestra el disco antes y después. Como cdm, añade dos notas cuando vienen al caso: lo que liberaría un reinicio (swap, las carpetas temporales que macOS vacía al arrancar, archivos borrados que las apps aún mantienen abiertos) cuando supera el espacio libre, y, cuando el historial de sesiones de Claude Code pasa de 1 GB con transcripciones más antiguas que su límite, el ajuste `desktopSessionCleanupPeriodDays` con el que Claude Code borra también las sesiones de Claude Desktop y Cowork. Lightspot nunca cambia ese ajuste por ti.
- **Piezas de SDK instaladas y sesiones antiguas, sin marcar**: también llegan las filas opcionales de cdm: los toolchains de PlatformIO, el NDK de Android, CMake y las fuentes del SDK, todas las versiones de build-tools y plataformas de Android salvo la más reciente, la imagen de sistema de un AVD que nadie ha arrancado en 60 días (la fila nombra el AVD, que no arrancará hasta reinstalar la imagen) y las sesiones de Claude Code sin tocar en 30 días, que solo van a la Papelera. Cada fila dice cómo vuelve.
- **También tus repositorios**: tras las cachés, Clean Dev Mac pregunta, como cdm, si quieres escanear tus repositorios de código en busca de restos de compilación y dependencias; pulsa **`⇥`**. Obtienes una fila sin marcar por repositorio con sus `node_modules`, `dist`, `build`, `target`, `__pycache__` y otros archivos ignorados por git. No se ofrece nada que el propio git del repositorio no ignore (un `build/` versionado se queda), los archivos `.env*` nunca se ofrecen, ni tampoco una carpeta que contenga otro repositorio. Las carpetas regenerables se borran; los demás archivos ignorados van a la Papelera.
- **Teclas**: `↑↓` selecciona (la fila seleccionada muestra sus rutas y tamaños), `Space` marca, `⇥` escanea tus repositorios, `↵` muestra el plan detallado y `↵` otra vez limpia, `⌥↵` muestra la caché seleccionada en Finder, `Esc` vuelve atrás.
- **Las mismas reglas que cdm**: Lightspot lee los archivos de reglas de cdm (tu `~/.cleandevmac/rules` si lo tienes; si no, las reglas en vivo de cdm en GitHub; si no, la copia incluida en la app), así que cualquier caché que cdm aprenda a limpiar, Lightspot también la limpia.
- **La misma seguridad que cdm**: cada ruta pasa la comprobación de seguridad de cdm antes de que ocurra nada: debe estar dentro de tu carpeta de inicio (con los enlaces simbólicos resueltos), y `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, `~/.ssh`, `~/.gnupg` e iCloud Drive nunca se tocan. Antes de limpiar, el plan nombra las apps aún abiertas que reescribirían sus cachés (ciérralas primero). Cada limpieza queda registrada en `~/.cleandevmac/clean.log`, el mismo registro que lleva cdm.
- **El resto, a una tecla**: Docker / Podman, los toolchains de Rust (se quitan con `rustup`), los datos de apps desinstaladas y las cachés de apps en sandbox necesitan un motor de contenedores, rustup o un análisis de tus apps, así que `⌘↵` ejecuta cdm completo en tu terminal preferida, directamente desde su última versión.

### 12. 📦 Instalaciones con una tecla: setup-zsh, MacStats y herramientas de desarrollo
Escribe `install` (o el nombre de una herramienta) y pulsa **`↵`**: Lightspot ejecuta el instalador propio de la herramienta en tu terminal preferida, así ves cada paso.
- **Install setup-zsh** ([setup-zsh](https://github.com/openhoangnc/setup-zsh)): autosugerencias de zsh que buscan en cualquier parte de tu historial, resaltado de sintaxis y un prompt que muestra el estado de git. Ejecuta `setup.sh` y luego abre un zsh nuevo que lo carga. Una vez instalado, la misma fila lo actualiza.
- **Install MacStats** ([mac-stats](https://github.com/openhoangnc/mac-stats)): CPU, RAM, velocidad de red y temperatura de la CPU en la barra de menús. Ejecuta su `install.sh`, que lo coloca en `/Applications` y lo inicia.
- **Install Dev Tools**: el menú `install-dev-tool` de setup-zsh: Homebrew, Node.js, Go, Python y uv, Rust, JDK, Bun, Git, VS Code, Chrome, OrbStack, Android Studio y más, además de actualizar tus paquetes globales. Escribe `install node`, `install go`, `install rust`…; sin setup-zsh, la fila lo instala primero.
- Cada fila indica si la herramienta ya está instalada; **`⌥↵`** abre su página de GitHub.

### 13. 🎛️ Ajustes de macOS
Los comandos `defaults write` que normalmente copiarías de un README de dotfiles, como acciones rápidas. Cada interruptor lee el ajuste actual y lo invierte, así que la misma fila lo revierte:
- **Dock**: **Clear Dock Icons** (quita todas las apps fijadas y reinicia el Dock: `defaults write com.apple.dock persistent-apps -array && killall Dock`), **Toggle Dock Auto-Hide**, **Toggle Instant Dock Auto-Hide** (sin retardo), **Toggle Dock Recent Apps**, **Restart Dock**.
- **Finder**: **Toggle Hidden Files in Finder**, **Toggle File Extensions in Finder**, **Toggle Finder Path Bar**, **Toggle Desktop Icons** (útil antes de compartir pantalla), **Toggle .DS_Store on Network & USB Drives**, **Restart Finder**.
- **Escritura y capturas**: **Toggle Press-and-Hold Accents** (mantener una tecla la repite), **Toggle Smart Quotes & Dashes**, **Toggle Screenshot Shadows**.

Ninguno pide la contraseña de administrador. Clear Dock Icons no se puede deshacer; los interruptores sí.

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
- **Enlaces Profundos de Ajustes del Sistema de macOS**: 46 enlaces profundos directos que abren paneles de ajustes específicos de macOS (`x-apple.systempreferences:...`), encontrados con los mismos términos que usa la búsqueda de Ajustes del Sistema (`night shift`, `lockdown mode`, `sticky keys`), en los idiomas de tu sistema.
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
Descarga e instala la última versión precompilada directamente:
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

### 4. Pruebas y Verificación
Lightspot no tiene un target de XCTest. Dos scripts independientes en `scripts/` se compilan al vuelo junto con las fuentes y se ejecutan desde la raíz del repositorio: un ejecutor de pruebas de lógica y motor (41 bloques de pruebas) y un verificador del sistema en vivo (11 secciones, 140 comprobaciones en una máquina completamente equipada; algunas se omiten si, por ejemplo, no hay historial de zsh o VS Code instalado, o no se puede acceder a GitHub):
```bash
# Pruebas de lógica central y motor (41 bloques de pruebas)
swiftc -o /tmp/test_engine scripts/test_engine.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift Sources/Lightspot/System/AutoStartManager.swift Sources/Lightspot/System/SpotlightManager.swift Sources/Lightspot/System/FirstRunManager.swift Sources/Lightspot/System/UpdateManager.swift Sources/Lightspot/System/SingleInstanceGuard.swift Sources/Lightspot/System/LegacyNetworkStores.swift Sources/Lightspot/System/HotkeyManager.swift Sources/Lightspot/System/SystemShortcutConflicts.swift && /tmp/test_engine

# Comprobaciones del sistema en vivo (11 secciones, 140 comprobaciones en una máquina completamente equipada)
swiftc -o /tmp/deep_verify scripts/deep_verify.swift Sources/Lightspot/Core/*.swift Sources/Lightspot/System/TerminalLauncher.swift && /tmp/deep_verify
```

---

## ⌨️ Atajos y Navegación

| Tecla | Acción |
|---|---|
| **`⌘Space`** / **`⌘⇧Space`** / **`⌥Space`** / **`⌃Space`** | Invocar o descartar Lightspot en cualquier lugar (configurable en la barra de menú) |
| **`↓` / `↑`** | Navegar a través de los resultados de búsqueda |
| **`Return` (`↵`)** | Abrir la aplicación seleccionada, proyecto en IDE, ejecutar comando o copiar cálculo |
| **`⌘Return` (`⌘↵`)** | Abrir proyecto seleccionado en la Terminal preferida |
| **`⌥Return` (`⌥↵`)** | Revelar proyecto en Finder / Forzar el cierre del proceso seleccionado (`SIGKILL`) / Abrir la página de GitHub de un instalador |
| **`⌘P`** | Fijar o desfijar comando del Historial de la Terminal seleccionado |
| **`⌘⇧P`** | Abrir la superposición del administrador de comandos fijados |
| **`⌘⇧C`** | Abrir la superposición del administrador de comandos personalizados |
| **`Space`** | Marcar o desmarcar una categoría en Clean Dev Mac |
| **`Tab` (`⇥`)** | Escanear también tus repositorios de código en Clean Dev Mac |
| **`⌘Y`** / **`⌘⇧H`** | Abrir la superposición del administrador de historial de búsqueda |
| **`Escape`** | Descartar superposiciones, limpiar el campo de búsqueda o cerrar Lightspot |
| **Clic Afuera** | Descarta automáticamente el panel flotante |

El atajo para invocarlo es el que elijas entre los cuatro en **Shortcut**, en la barra de menús. macOS asigna `⌃Space` a «Seleccionar la fuente de entrada anterior», así que, si lo eliges, la pulsación también cambiará tu fuente de entrada; el submenú **Shortcut** indica qué atajo del sistema ya ocupa la combinación elegida.

---

## 🔒 Garantías de Privacidad y Seguridad

- **Cero Indexación de Archivos**: Lightspot nunca indexa tus archivos personales, documentos, descargas o repositorios de código. Clean Dev Mac mide solo las carpetas de caché que nombran las reglas de cdm y los pocos sitios que necesitan sus dos notas (ver más abajo), solo mientras lo tienes abierto, y no guarda nada salvo los tamaños; nunca lee los contenedores sandbox de otras apps. Para sus filas de Android y de Claude Code lee además las fechas de los archivos de tus carpetas de AVD y de `~/.claude/projects`, y los pequeños archivos de `~/.claude/sessions` que nombran las sesiones en curso; nunca lo que dice una transcripción. Para las dos notas de cdm lee cuánta swap está en uso, mide las carpetas temporales que macOS vacía al arrancar y `~/.claude/projects`, pide a `lsof` los archivos borrados que tus apps aún mantienen abiertos (solo guarda el total y los nombres de las tres apps que más ocupan) y lee dos claves de `~/.claude/settings.json` (`cleanupPeriodDays`, `desktopSessionCleanupPeriodDays`), que nunca modifica. Cuando le pides que escanee tus repositorios (`⇥`), busca repositorios git en tu carpeta de inicio, hasta seis niveles, sin entrar en `~/Library`, `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/Movies` ni `~/Music`, y pregunta al git de cada repositorio qué archivos ignora.
- **Portapapeles Efímero Solo en RAM**: El historial del portapapeles permanece exclusivamente en memoria volátil e ignora activamente los tipos ocultos/administradores de contraseñas (`org.nspasteboard.ConcealedType`, `1Password`, `Bitwarden`). Nunca se escribe en el disco, ni siquiera en el historial de búsqueda, que tampoco guarda el texto que copias de resultados de la calculadora, las herramientas de desarrollo o los fragmentos.
- **Aislamiento del Navegador Predeterminado**: Los marcadores, las pestañas abiertas y el historial reciente se leen localmente y únicamente de tu navegador predeterminado configurado, evitando el raspado entre navegadores.
- **Comandos Iniciados por el Usuario**: Tus comandos, scripts y acciones rápidas se ejecutan solo tras la acción explícita del usuario (`Return` o `⌘↵`).
- **Cero Telemetría, Dos Servicios Que Tú Controlas**: Sin analíticas, sin rastreo, sin cuentas. Lightspot se comunica por su cuenta con exactamente dos servicios, y tú decides sobre ambos. El primero es GitHub, para las actualizaciones: un `GET` sin autenticar a la API pública de releases (`api.github.com/repos/openhoangnc/mac-lightspot/releases/latest`) con `User-Agent: Lightspot/<versión> (+https://github.com/openhoangnc/mac-lightspot)`, poco después del inicio y al abrir el menú de la barra de menús, pero no más de una vez al día tras una comprobación correcta (una comprobación fallida se repite en el siguiente inicio o al abrir el menú). Desactiva **`Automatically Check for Updates`** en la barra de menús y nunca se ejecutará por sí sola. Instalar una actualización que aceptaste descarga su zip desde GitHub (`User-Agent: Lightspot/<versión>`). Ambas pasan por una sesión efímera, así que ninguna respuesta ni cookie se guarda en el disco. Las versiones anteriores usaban en su lugar la sesión compartida de macOS (la comprobación de actualizaciones hasta la 1.2.0, la consulta de IP antes de la 1.2.0), que guardaba las respuestas en `~/Library/Caches/com.lightspot.app` y las cookies en `~/Library/HTTPStorages`; Lightspot borra esos restos al iniciarse, y el desinstalador también los elimina. El segundo es ipify: `GET https://api.ipify.org` (un servicio de terceros) para conocer tu IP pública, y solo cuando la pides: al escribir una consulta que la nombra (`ip`, `my ip`, `public ip`, `ipv4`) o al pulsar `Return` en la fila **IP Address**. ipify ve tu dirección IP y un user agent estándar de macOS, como cualquier servidor web. La respuesta se guarda en memoria durante 15 minutos y nunca se escribe en el disco. Al abrir **Clean Dev Mac** también se piden a GitHub los archivos de reglas de cdm (`GET https://raw.githubusercontent.com/cleandevmac/cdm/main/rules/index.json` y los archivos que enumera, con un user agent estándar de macOS, a través de una sesión efímera), como mucho una vez por hora; se quedan en memoria y, sin conexión, se usa la copia incluida en la app. Lo evitas por completo si guardas tus propias reglas en `~/.cleandevmac/rules`. Ejecutar cdm en la terminal (`⌘↵`) descarga su script desde la release de cdm en GitHub, como indican las instrucciones del propio cdm. Las filas de instalación funcionan igual: cada una ejecuta el instalador de su herramienta en tu terminal, y es ese script, no Lightspot, el que descarga desde GitHub. Las búsquedas web, las URL y los marcadores los abre tu navegador, y solo cuando pulsas `Return`.
- **Lo Que Se Escribe en el Disco**: Las preferencias propias de Lightspot (`UserDefaults`, en `~/Library/Preferences/com.lightspot.app.plist`), un archivo de bloqueo, archivos temporales mientras se instala una actualización y un recibo en el registro de cdm cuando limpias:
  - Ajustes: `lightspot_hotkey_option`, `lightspot_terminal_app`, `lightspot_search_engine`, `lightspot_browser_history_days`, `lightspot_hide_menubar_icon`, `lightspot_auto_start_enabled`, `lightspot_first_run_completed`, `lightspot_spotlight_state` (último estado conocido de Spotlight, para las etiquetas del menú), `lightspot_auto_update_enabled`, `lightspot_last_update_check`, `lightspot_skipped_version` (comprobaciones automáticas de actualizaciones).
  - Lo que creas: `lightspot_pinned_commands`, `lightspot_custom_commands`, `lightspot_snippets`.
  - Uso: `lightspot_recent_app_bundle_ids` (apps abiertas recientemente) y `lightspot_search_history`: las consultas que escribiste y los resultados que abriste (títulos, rutas de apps y proyectos, URL, comandos de shell), más los recuentos de selección para la clasificación. Revísalo o bórralo en el gestor del historial de búsqueda (`⌘Y`). Las selecciones del portapapeles, la calculadora y las herramientas de desarrollo nunca se registran; las de fragmentos y del informe de hardware solo conservan la consulta y un recuento, nunca el texto copiado.
  - `~/.cleandevmac/clean.log`, solo cuando limpias con Clean Dev Mac: lo que cada limpieza borró o movió a la Papelera, añadido al registro que lleva el propio cdm (limitado a 1 MiB, como el de cdm). Lo que confirmas en el limpiador se borra definitivamente, salvo las categorías marcadas como Trash, que van a la Papelera.
  - `~/Library/Application Support/Lightspot/com.lightspot.app.lock`, que impide que se inicie una segunda copia. Guarda el PID del proceso en ejecución y la ruta, el inodo y la fecha de modificación de su ejecutable, para que un nuevo inicio distinga la misma compilación de una más reciente.
  - Mientras se instala una actualización que aceptaste: la descarga, el paquete descomprimido y un pequeño script auxiliar en el directorio temporal de macOS (`NSTemporaryDirectory()`, carpetas `lightspot-update-…` y `lightspot-updater-…`), y la versión anterior guardada como `Lightspot.app.lightspot-old` junto a la app hasta que la nueva está en su sitio. El script auxiliar los borra todos al terminar.
  - **Export Settings** escribe una copia de seguridad JSON, con el historial de búsqueda incluido, solo en el archivo que elijas.
