<div align="center">

# 🍚 windows-rice

**Windows 11 con dock y barra tipo Mac, terminal de programador y un lanzador rápido, en un solo comando.**

`Seelen UI` · `Flow Launcher` · `PowerToys` · `Everything` · `Windows Terminal` · `Starship`

Paleta **Catppuccin Mocha** en todo · se instala con un script · se quita con otro

</div>

---

## ⚡ Instalar (1 minuto)

Abre **PowerShell** y pega:

```powershell
irm https://raw.githubusercontent.com/PauLopNun/windows-rice/main/get.ps1 | iex
```

Pedirá permisos de administrador, descargará el pack a `%USERPROFILE%\windows-rice`, instalará todo y lo dejará configurado. **No tienes que tocar nada más.**

<details>
<summary>¿Prefieres no ejecutar un one-liner? Instalación manual</summary>

1. Descarga el ZIP del repo (*Code → Download ZIP*) y descomprímelo.
2. PowerShell **como administrador**, dentro de la carpeta:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```
</details>

### Opciones

| Opción | Efecto |
|---|---|
| `-NoSeelen` | **Modo ligero**: sin dock ni barra (Seelen es lo que más RAM gasta, ver abajo) |
| `-NoCli` | Sin Git, zoxide, fzf, lazygit ni fastfetch |
| `-NoTweaks` | No toca modo oscuro, extensiones ni botones de la barra |
| `-NoLaunch` | No abre las apps al terminar |
| `-SkipRestorePoint` | No crea punto de restauración (Windows solo permite uno cada 24 h) |

Es **idempotente**: puedes repetirlo y salta lo que ya está hecho. Si ya tenías alguna app, **no la toca** y el desinstalador **no la quita**.

## ✨ Qué incluye

| | |
|---|---|
| 🖥️ **Seelen UI** | Dock y barra superior estilo macOS con CPU y RAM, colores que salen del fondo |
| 🚀 **Flow Launcher** | `Alt+Espacio` abre apps, archivos, calcula y busca en la web. Tema Catppuccin Mocha |
| 🔌 **Plugins de Flow** | Clipboard+ (historial del portapapeles), Window Walker (saltar entre ventanas), Windows Settings, Colors, Search Unicode & Emoji |
| 🧰 **PowerToys** | Cuentagotas, copiar texto de imágenes, vista previa con Espacio, ventana siempre encima… |
| 🔎 **Everything** | Búsqueda instantánea de archivos (Flow la usa por debajo) |
| 💻 **Terminal** | Catppuccin Mocha, JetBrainsMono Nerd Font, PowerShell 7 y prompt **Starship** |
| 🛠️ **CLI** | Git, zoxide (`z carpeta`), fzf, lazygit, fastfetch |
| 🖼️ **Fondo** | Degradado oscuro Catppuccin generado para este repo |
| 🌙 **Windows** | Modo oscuro, extensiones de archivo visibles, sin botón de chat ni de vistas (el de widgets lo protege Windows 11) |
| ⚡ **Autoarranque** | Flow y Everything arrancan con Windows; se abre todo al terminar |

## 📊 Rendimiento

Medido en un PC con 32 GB y **dos monitores** (memoria privada):

| App | RAM aprox. |
|---|---|
| Seelen UI (app + WebViews de dock/barra) | **~1,3 GB** |
| Flow Launcher | ~120 MB |
| PowerToys | ~95 MB |
| Everything | ~11 MB |

Seelen dibuja dock y barra con WebView2, y cada monitor suma. En un PC con 16 GB o más casi no se nota; en uno de **8 GB o menos**, instala con `-NoSeelen`. Tu caso puede variar.

## 🎁 Pasar tu propia configuración

Deja todo a tu gusto, **ciérralo** (así guarda todo) y ejecuta, sin administrador:

```powershell
powershell -ExecutionPolicy Bypass -File .\export-config.ps1
```

Se crea `config\` con tus ajustes de Seelen, Flow, PowerToys, Everything y Starship, y tu fondo de pantalla. Quien instale desde tu carpeta tendrá tu mismo setup.

- Las rutas con tu usuario se cambian solas por las de quien instala.
- No se copian logs, cachés, historiales ni los DLL de los plugins.
- El dock de Seelen **no** se exporta (llevaría tus apps ancladas).
- ⚠️ El export avisa si algún archivo menciona claves, contraseñas o tokens. Revísalos antes de compartir.

## 🧹 Quitarlo todo

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\windows-rice\uninstall.ps1"          # quita apps y cambios
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\windows-rice\uninstall.ps1" -Purge   # y borra las configs de las apps
```

Deshace **solo** lo que hizo el script: apps instaladas, plugins, tema y fuente de Terminal, bloque del perfil de PowerShell, `starship.toml`, ExecutionPolicy, ajustes de Windows, fondo, autoarranque, y devuelve la configuración que tenías antes. Reinicia después.

Plan B: *Panel de control → Recuperación → Restaurar sistema* → **"Antes de windows-rice"**. El registro de cambios está en `%LOCALAPPDATA%\windows-rice\state.json`.

## 🗂️ Estructura

| Archivo | Para qué |
|---|---|
| `get.ps1` | Instalación en una línea |
| `install.ps1` / `uninstall.ps1` | Instala y configura / lo deshace |
| `export-config.ps1` | Guarda tu config en `config\` |
| `rice-lib.ps1` | Funciones compartidas |
| `plugins.json` | Plugins de Flow con versión fija y SHA256 |
| `config\` | Ajustes que se aplican al instalar |
| `assets\` | Fondo de pantalla |

## 📝 Notas

- Requiere Windows 10/11 con `winget` (App Installer); si falta, el script intenta registrarlo.
- Seelen se instala como MSIX. Su tema y ajustes globales los eliges tú desde sus ajustes (`slu.exe settings`) y luego puedes volver a exportar.
- Créditos y licencias de terceros en [THIRD-PARTY.md](THIRD-PARTY.md).

## Licencia

[MIT](LICENSE)
