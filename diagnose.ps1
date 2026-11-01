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

Sec 'Errores recientes del registro de Seelen'
if (Test-Path $log) {
    Get-Content $log -Tail 4000 | Where-Object { $_ -match '\[(ERROR|WARN)\]' -and $_ -notmatch 'Tray icon .* added without registry|telemetry' } |
        Select-Object -Last 25 | ForEach-Object { Line ($_.Substring(0, [Math]::Min(230, $_.Length))) }
    $mons = Get-Content $log -Tail 4000 | Where-Object { $_ -match 'weg\?monitorId=.*Ready|fancy-toolbar\?monitorId=.*Ready' } | Select-Object -Last 4
    Line ''; Line 'Barra/dock listos por monitor:'; $mons | ForEach-Object { Line ('   ' + $_.Substring(0, [Math]::Min(150, $_.Length))) }
} else { Line 'No hay registro de Seelen (nunca se ha abierto?)' }

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
