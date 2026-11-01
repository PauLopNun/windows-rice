<#
  Windows Rice - instalacion en una linea.
  En PowerShell (se pedira administrador solo):
    irm https://raw.githubusercontent.com/PauLopNun/windows-rice/main/get.ps1 | iex

  Descarga este repositorio como ZIP desde GitHub a %USERPROFILE%\windows-rice y ejecuta install.ps1.
  Lee el codigo antes si quieres: es corto y esta todo en el repo.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo   = 'PauLopNun/windows-rice'
$branch = 'main'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[*] Pidiendo permisos de administrador...' -ForegroundColor Cyan
    $cmd = "irm https://raw.githubusercontent.com/$repo/$branch/get.ps1 | iex"
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
    return
}

$dest = Join-Path $env:USERPROFILE 'windows-rice'
$tmp  = Join-Path $env:TEMP ('windows-rice-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Write-Host '[*] Descargando windows-rice...' -ForegroundColor Cyan
Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/$branch.zip" -OutFile (Join-Path $tmp 'r.zip') -UseBasicParsing
Expand-Archive (Join-Path $tmp 'r.zip') -DestinationPath $tmp -Force
$src = Get-ChildItem $tmp -Directory | Select-Object -First 1
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Move-Item $src.FullName $dest
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[+] Guardado en $dest (ahi tienes uninstall.ps1 para quitarlo)." -ForegroundColor Green
Set-Location $dest
& (Join-Path $dest 'install.ps1')
