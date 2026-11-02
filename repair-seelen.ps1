<#
  Windows Rice - reparar la barra superior de Seelen

  Restaura la barra superior del pack (modulos y orden) si Seelen la ha reescrito o no se aplico bien.
  Hace copia de seguridad de la tuya (.bak-repair) y reinicia Seelen. No necesita administrador.

  Uso, sin descargar nada:
    irm https://raw.githubusercontent.com/PauLopNun/windows-rice/main/repair-seelen.ps1 | iex
  o, con el pack ya descargado:
    powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\windows-rice\repair-seelen.ps1"

  Opcional: -ResetDock tambien reconstruye el dock desde cero (Seelen lo vuelve a crear con las apps de tu barra de tareas).
#>
param([switch]$ResetDock)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$cfg    = Join-Path $env:APPDATA 'com.seelen.seelen-ui'
$tbDir  = Join-Path $cfg 'data\seelen-fancy-toolbar'
$tbFile = Join-Path $tbDir 'state.yml'
$rel    = 'config/seelen-roaming/data/seelen-fancy-toolbar/state.yml'
$url    = "https://raw.githubusercontent.com/PauLopNun/windows-rice/main/$rel"

# 1) el state.yml de referencia: del pack si esta aqui; si no, de GitHub
$ref = $null
if ($PSScriptRoot) { $local = Join-Path $PSScriptRoot ($rel -replace '/', '\'); if (Test-Path $local) { $ref = [IO.File]::ReadAllText($local) } }
if (-not $ref) {
    Write-Host '[*] Descargando la barra de referencia desde GitHub...' -ForegroundColor Cyan
    $ref = (Invoke-WebRequest $url -UseBasicParsing).Content
}
if ($ref -notmatch '(?m)^right:' -or $ref -notmatch '@default/power') { throw 'El archivo de referencia no tiene el formato esperado; no toco nada.' }

# 1b) WebView2: el tema de Seelen usa CSS moderno (Chromium 123+). Con uno antiguo el dock sale SIN fondo y la barra con colores mal.
$wvKeys = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}')
$wvVer = $null; foreach ($k in $wvKeys) { $pv = (Get-ItemProperty $k -ErrorAction SilentlyContinue).pv; if ($pv) { $wvVer = [version]$pv; break } }
if (-not $wvVer -or $wvVer -lt [version]'123.0.0.0') {
    Write-Host ("[!] WebView2 " + $(if ($wvVer) { "$wvVer es demasiado antiguo" } else { 'no encontrado' }) + " (hace falta 123 o superior): lo actualizo (puede pedir permisos de administrador)...") -ForegroundColor Yellow
    $wg = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $wg) { & $wg install --id Microsoft.EdgeWebView2Runtime --exact --silent --source winget --accept-package-agreements --accept-source-agreements | Out-Host }
    else { Write-Host '[!] No encuentro winget. Instala el WebView2 desde https://developer.microsoft.com/microsoft-edge/webview2' -ForegroundColor Yellow }
} else { Write-Host "[+] WebView2 $wvVer correcto." -ForegroundColor Green }

# 2) parar Seelen, copia de seguridad y restaurar
$app = Get-StartApps -Name '*Seelen*' -ErrorAction SilentlyContinue | Select-Object -First 1
# solo la parte visual: slu-service va con permisos elevados y no se puede cerrar sin administrador (Seelen lo gestiona solo)
foreach ($proc in @(Get-Process -Name 'seelen-ui' -ErrorAction SilentlyContinue)) { try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { Write-Host "[!] No pude cerrar Seelen: $($_.Exception.Message)" -ForegroundColor Yellow } }
Start-Sleep -Seconds 2
try {
    New-Item -ItemType Directory -Force -Path $tbDir | Out-Null
    if (Test-Path $tbFile) { Copy-Item $tbFile "$tbFile.bak-repair" -Force; Write-Host "[+] Copia de tu barra: $tbFile.bak-repair" -ForegroundColor Green }
    [IO.File]::WriteAllText($tbFile, $ref, (New-Object Text.UTF8Encoding $false))
    Write-Host '[+] Barra superior restaurada (CPU, RAM, bandeja, idioma, bluetooth, red, volumen, energia, notificaciones, ajustes).' -ForegroundColor Green

    if ($ResetDock) {
        $weg = Join-Path $cfg 'data\seelen-weg\state.yml'
        if (Test-Path $weg) { Copy-Item $weg "$weg.bak-repair" -Force; Remove-Item $weg -Force; Write-Host '[+] Dock reiniciado (Seelen lo recreara con las apps de tu barra de tareas).' -ForegroundColor Green }
    }
} finally {
    # 3) volver a abrir Seelen SIEMPRE (sin privilegios de administrador), pase lo que pase arriba
    if ($app) { Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($app.AppID)"; Write-Host '[+] Seelen reiniciado.' -ForegroundColor Green }
    else { Write-Host '[!] No encuentro Seelen en el menu Inicio: abrelo a mano.' -ForegroundColor Yellow }
}
