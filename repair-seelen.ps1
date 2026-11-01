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

# 2) parar Seelen, copia de seguridad y restaurar
$app = Get-StartApps -Name '*Seelen*' -ErrorAction SilentlyContinue | Select-Object -First 1
Get-Process -Name 'seelen-ui', 'slu-service' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force -Path $tbDir | Out-Null
if (Test-Path $tbFile) { Copy-Item $tbFile "$tbFile.bak-repair" -Force; Write-Host "[+] Copia de tu barra: $tbFile.bak-repair" -ForegroundColor Green }
[IO.File]::WriteAllText($tbFile, $ref, (New-Object Text.UTF8Encoding $false))
Write-Host '[+] Barra superior restaurada (CPU, RAM, bandeja, idioma, bluetooth, red, volumen, energia, notificaciones, ajustes).' -ForegroundColor Green

if ($ResetDock) {
    $weg = Join-Path $cfg 'data\seelen-weg\state.yml'
    if (Test-Path $weg) { Copy-Item $weg "$weg.bak-repair" -Force; Remove-Item $weg -Force; Write-Host '[+] Dock reiniciado (Seelen lo recreara con las apps de tu barra de tareas).' -ForegroundColor Green }
}

# 3) volver a abrir Seelen (sin privilegios de administrador)
if ($app) { Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($app.AppID)"; Write-Host '[+] Seelen reiniciado.' -ForegroundColor Green }
else { Write-Host '[!] No encuentro Seelen en el menu Inicio: abrelo a mano.' -ForegroundColor Yellow }
