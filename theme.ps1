<#
  Windows Rice - cambiar entre modo oscuro y claro (Windows + Seelen)

  Uso (NO hace falta administrador):
    powershell -ExecutionPolicy Bypass -File .\theme.ps1              # alterna oscuro <-> claro
    powershell -ExecutionPolicy Bypass -File .\theme.ps1 -Mode dark   # oscuro (el aspecto del pack)
    powershell -ExecutionPolicy Bypass -File .\theme.ps1 -Mode light  # claro

  El tema de Seelen (dock y barra) sigue el modo de Windows y solo lo lee al arrancar,
  por eso este script lo reinicia. Flow Launcher y la Terminal mantienen su tema Catppuccin.
#>
[CmdletBinding()]
param(
    [ValidateSet('dark', 'light', 'toggle')][string]$Mode = 'toggle',
    [switch]$NoSeelenRestart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'rice-lib.ps1')

$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
$cur = Get-ItemProperty -Path $key -Name AppsUseLightTheme -ErrorAction SilentlyContinue
$isLight = ($null -ne $cur) -and ($cur.AppsUseLightTheme -eq 1)

$wantLight = switch ($Mode) { 'light' { $true } 'dark' { $false } default { -not $isLight } }
$val = if ($wantLight) { 1 } else { 0 }

Set-ItemProperty -Path $key -Name AppsUseLightTheme    -Value $val -Type DWord
Set-ItemProperty -Path $key -Name SystemUsesLightTheme -Value $val -Type DWord
Broadcast-RiceSettings
Write-Host ("[+] Windows en modo " + $(if ($wantLight) { 'CLARO' } else { 'OSCURO' }) + '.') -ForegroundColor Green

if (-not $NoSeelenRestart -and (Get-Process -Name 'seelen-ui' -ErrorAction SilentlyContinue)) {
    $seelen = Get-StartApps -Name '*Seelen*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($seelen) {
        Write-Host '[*] Reiniciando Seelen para que coja el modo nuevo...' -ForegroundColor Cyan
        Stop-RiceApp 'seelen'; Start-Sleep -Seconds 2
        Start-RiceUnelevated "shell:AppsFolder\$($seelen.AppID)"
        Write-Host '[+] Seelen reiniciado.' -ForegroundColor Green
    }
}
