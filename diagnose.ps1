<#
  Windows Rice - diagnostico (solo LEE, no cambia nada)
  Recoge lo necesario para entender por que algo no se ve bien (dock, barra, iconos) y lo copia al portapapeles.

  Uso, sin administrador:
    irm https://raw.githubusercontent.com/PauLopNun/windows-rice/main/diagnose.ps1 | iex
  o, si ya tienes el pack:
    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\windows-rice\diagnose.ps1"

  Se quita tu nombre de usuario del texto. Pegalo en el chat.
#>
$ErrorActionPreference = 'SilentlyContinue'
$out = New-Object System.Collections.Generic.List[string]
function Line($s) { $out.Add([string]$s) }
function Sec($s)  { $out.Add(''); $out.Add("=== $s ===") }

$cfg = Join-Path $env:APPDATA 'com.seelen.seelen-ui'
$log = Join-Path $env:LOCALAPPDATA 'com.seelen.seelen-ui\logs\Seelen UI.log'

Sec 'Sistema'
Line ("Windows: " + (Get-CimInstance Win32_OperatingSystem).Caption + " build " + [Environment]::OSVersion.Version.Build)
Line ("PowerShell: " + $PSVersionTable.PSVersion)
$p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
Line ("Modo apps claro=" + $p.AppsUseLightTheme + " | modo sistema claro=" + $p.SystemUsesLightTheme + " | transparencia=" + $p.EnableTransparency + "   (0 = oscuro)")
Add-Type -AssemblyName System.Windows.Forms
Line ("Monitores: " + (([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)" }) -join ' + '))
Line ("Fecha/hora del PC: " + (Get-Date).ToString('yyyy-MM-dd HH:mm') + " | zona: " + (Get-TimeZone).Id)

Sec 'Seelen'
$pkg = Get-AppxPackage -Name 'Seelen.SeelenUI' | Select-Object -First 1
Line ("Version instalada: " + $(if ($pkg) { $pkg.Version } else { 'NO INSTALADO' }))
$mf = Join-Path $PSScriptRoot 'config\manifest.json'
if ($PSScriptRoot -and (Test-Path $mf)) { Line ("Version con la que se exporto la config: " + ((Get-Content $mf -Raw | ConvertFrom-Json).versions.seelen)) }
Line ("Procesos: seelen-ui=" + [bool](Get-Process seelen-ui) + " | slu-service=" + [bool](Get-Process slu-service))
Line ("Config en disco: " + (Test-Path $cfg))
if (Test-Path "$cfg\settings.json") { Line ("settings.json: " + (Get-Content "$cfg\settings.json" -Raw)) } else { Line 'settings.json: NO EXISTE' }
Line ("seelen-weg/state.yml (dock): " + (Test-Path "$cfg\data\seelen-weg\state.yml"))

Sec 'Modulos de la barra superior (toolbar state.yml)'
$tb = "$cfg\data\seelen-fancy-toolbar\state.yml"
if (Test-Path $tb) {
    $sec = ''
    foreach ($l in (Get-Content $tb)) {
        if ($l -match '^(left|center|right):') { $sec = $Matches[1]; Line "[$sec]" }
        elseif ($l -match "^- '?(@[^'\s]+)'?") { Line ("   " + $Matches[1]) }
        elseif ($l -match '^- id:') { Line '   (modulo propio)' }
    }
} else { Line 'NO EXISTE state.yml de la barra' }

Sec 'Ventanas y motor grafico de Seelen'
try {
    Add-Type -TypeDefinition @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class DiagWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static string[] Tauri() { var res = new List<string>();
    EnumWindows((h,l) => { var c = new StringBuilder(64); GetClassName(h, c, 64); if (c.ToString() != "Tauri Window") return true;
      var t = new StringBuilder(128); GetWindowText(h, t, 128); RECT r; GetWindowRect(h, out r);
      res.Add("visible=" + IsWindowVisible(h) + "  " + (r.R - r.L) + "x" + (r.B - r.T) + "  " + t); return true; }, IntPtr.Zero); return res.ToArray(); } }
"@
    $w = [DiagWin]::Tauri()
    Line ("Ventanas de Seelen: " + @($w).Count); $w | Sort-Object | ForEach-Object { Line ("   " + $_) }
} catch { Line ("No pude listar las ventanas: " + $_.Exception.Message) }
$wv2 = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') |
    ForEach-Object { (Get-ItemProperty $_).pv } | Where-Object { $_ } | Select-Object -First 1
$wvTxt = if (-not $wv2) { 'NO ENCONTRADO (Seelen lo necesita para dibujar la barra)' } elseif ([version]$wv2 -lt [version]'123.0.0.0') { "$wv2   <-- DEMASIADO ANTIGUO: el dock sale sin fondo y la barra con colores mal (hace falta 123 o superior)" } else { "$wv2 (correcto)" }
Line ("WebView2 Runtime: " + $wvTxt)
$osw = Get-CimInstance Win32_OperatingSystem
Line ("WMI/CIM: " + $(if ($osw -and $osw.Caption) { 'responde' } else { 'NO RESPONDE (repositorio WMI danado; Seelen registra errores de WMI)' }))
$wvp = @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" | Where-Object { $_.CommandLine -match 'seelen' })
Line ("Procesos WebView2 de Seelen: " + $wvp.Count + "   (en un PC con 2 monitores sanos salen ~12)")
$gpu = (Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name + " drv " + $_.DriverVersion }) -join ' | '
Line ("Grafica: " + $gpu)

Sec 'Errores recientes del registro de Seelen (sin ruido de iconos)'
if (Test-Path $log) {
    $allLog = Get-Content $log -Tail 6000
    Line ("(se ignoran " + @($allLog | Where-Object { $_ -match 'icon_extractor' }).Count + " errores de iconos y los avisos de bandeja/brillo, que son normales)")
    $allLog | Where-Object { $_ -match '\[(ERROR|WARN)\]' -and $_ -notmatch 'icon_extractor|Tray icon .* added without registry|telemetry|brightness' } |
        Select-Object -Last 30 | ForEach-Object { Line ($_.Substring(0, [Math]::Min(230, $_.Length))) }
    Line ''; Line 'Carga de recursos:'
    $allLog | Where-Object { $_ -match 'seelen_ui::resources\]|\[measure\] RESOURCES|Registering widget' } | Select-Object -Last 6 | ForEach-Object { Line ('   ' + $_.Substring(0, [Math]::Min(150, $_.Length))) }
    Line ("Widgets registrados en esta sesion: " + @($allLog | Where-Object { $_ -match 'Registering widget' }).Count)
    $mons = Get-Content $log -Tail 4000 | Where-Object { $_ -match 'weg\?monitorId=.*Ready|fancy-toolbar\?monitorId=.*Ready' } | Select-Object -Last 4
    Line ''; Line 'Barra/dock listos por monitor:'; $mons | ForEach-Object { Line ('   ' + $_.Substring(0, [Math]::Min(150, $_.Length))) }
} else { Line 'No hay registro de Seelen (nunca se ha abierto?)' }

Sec 'Fondo de escritorio'
$dk = Get-ItemProperty 'HKCU:\Control Panel\Desktop'
Line ("WallPaper: " + $dk.WallPaper)
$wpx = $dk.WallPaper
Line ("El archivo existe: " + $(if ($wpx -and (Test-Path -LiteralPath $wpx)) { "si ($([int]((Get-Item -LiteralPath $wpx).Length/1KB)) KB)" } else { 'NO' }))
Line ("Estilo=" + $dk.WallpaperStyle + " | tipo de fondo=" + (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers').BackgroundType + "   (0 = imagen, 2 = presentacion, 3 = Spotlight)")
Line ("Carpeta Imagenes en OneDrive: " + ([Environment]::GetFolderPath('MyPictures') -match 'OneDrive'))

Sec 'Windows Rice'
$st = Join-Path $env:LOCALAPPDATA 'windows-rice\state.json'
if (Test-Path $st) { $s = Get-Content $st -Raw | ConvertFrom-Json
    Line ("Paquetes instalados por el script: " + (@($s.installedPackages) -join ', '))
    Line ("Config aplicada: " + ((@($s.configApplied) | ForEach-Object { $_.name }) -join ', '))
    Line ("Plugins de Flow: " + @($s.flowPlugins).Count + " | cursor: " + [bool]$s.cursor + " | fondo: " + [bool]$s.wallpaper)
} else { Line 'state.json: NO EXISTE (el instalador no llego a ejecutarse)' }
Line ("Arranque con Windows: " + (((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run').PSObject.Properties | Where-Object Name -like 'windows-rice*' | ForEach-Object Name) -join ', '))

$text = ($out -join "`r`n").Replace($env:USERPROFILE, '%USERPROFILE%').Replace($env:USERNAME, '<usuario>')
Write-Host $text
try { Set-Clipboard -Value $text; Write-Host ''; Write-Host '[+] Copiado al portapapeles: pegalo (Ctrl+V) en el chat.' -ForegroundColor Green } catch { Write-Host ''; Write-Host '[!] No pude copiarlo: selecciona el texto de arriba y copialo a mano.' -ForegroundColor Yellow }
