<#
  Windows Rice - instalacion en una linea.
  En PowerShell (se pedira administrador solo):
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/PauLopNun/windows-rice/main/get.ps1 | iex"

  Descarga este repositorio como ZIP desde GitHub a %USERPROFILE%\windows-rice y ejecuta install.ps1.
  Lee el codigo antes si quieres: es corto y esta todo en el repo.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo   = 'PauLopNun/windows-rice'
$branch = 'main'

# Windows trae por defecto la ejecucion de scripts desactivada (Restricted): sin esto, install.ps1 da "acceso denegado".
# Solo afecta a este proceso, no cambia nada del sistema.
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch { }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[*] Pidiendo permisos de administrador (acepta el aviso de Windows)...' -ForegroundColor Cyan
    $cmd = "irm https://raw.githubusercontent.com/$repo/$branch/get.ps1 | iex"
    try {
        Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $cmd -ErrorAction Stop
    } catch {
        Write-Host "[!] No se pudo abrir PowerShell como administrador: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '    Abre "Terminal (Administrador)" desde el menu Inicio (clic derecho) y vuelve a pegar el comando.' -ForegroundColor Yellow
    }
    return
}

$dest = Join-Path $env:USERPROFILE 'windows-rice'
$tmp  = Join-Path $env:TEMP ('windows-rice-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Write-Host '[*] Descargando windows-rice...' -ForegroundColor Cyan
Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/$branch.zip" -OutFile (Join-Path $tmp 'r.zip') -UseBasicParsing
Expand-Archive (Join-Path $tmp 'r.zip') -DestinationPath $tmp -Force
$src = Get-ChildItem $tmp -Directory | Select-Object -First 1

# Se COPIA (no se mueve): el antivirus escanea lo recien extraido y Move-Item suele dar "acceso denegado".
Set-Location $env:TEMP   # si la consola esta dentro de la carpeta de destino, Windows no deja borrarla ("en uso")
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$copied = $false
for ($i = 0; $i -lt 5 -and -not $copied; $i++) {
    try { Copy-Item -Path (Join-Path $src.FullName '*') -Destination $dest -Recurse -Force -ErrorAction Stop; $copied = $true }
    catch { Start-Sleep -Seconds 2 }
}
if (-not $copied) { throw "No pude copiar los archivos a $dest. Cierra programas que usen esa carpeta (o el antivirus) y repite." }
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[+] Guardado en $dest (ahi tienes uninstall.ps1 para quitarlo)." -ForegroundColor Green
Set-Location $dest
# En un proceso aparte con Bypass: asi funciona aunque la consola tenga los scripts bloqueados.
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'install.ps1')
