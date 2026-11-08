#Requires -RunAsAdministrator
<#
  Windows Rice - desinstalador
  Deshace SOLO lo que hizo install.ps1 (lee %LOCALAPPDATA%\windows-rice\state.json).
  Lo que ya tenias antes (p. ej. PowerToys o Windows Terminal) no se toca.

  Uso (PowerShell como administrador):
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -Purge   # borra tambien configs de las apps
#>
[CmdletBinding()]
param([switch]$Purge)

$ErrorActionPreference = 'Continue'
$Marker    = 'windows-rice'
$StateDir  = Join-Path $env:LOCALAPPDATA 'windows-rice'
$StateFile = Join-Path $StateDir 'state.json'
. (Join-Path $PSScriptRoot 'rice-lib.ps1')

function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }

if (-not (Test-Path $StateFile)) {
    Warn "No hay ${StateFile}: no se que instalo el script, asi que no quito apps. Limpio solo los restos (vigilantes, autoarranque) y devuelvo la barra de tareas."
    Stop-RiceLeftovers
    Restore-RiceTaskbar $null
    exit 0
}
$state = Get-Content $StateFile -Raw | ConvertFrom-Json
# lo primero: parar vigilantes y quitar autoarranque, para que nada vuelva a lanzar las apps mientras se desinstalan
Stop-RiceLeftovers

# ---------------------------------------------------------------- winget
# En consolas de administrador a veces winget no esta en el PATH: lo buscamos a mano.
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    $wgPath = $null
    $cand = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $cand) { $wgPath = $cand }
    if (-not $wgPath) {
        $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
               Sort-Object Version -Descending | Select-Object -First 1
        if (-not $pkg) {
            Write-Host '[*] Registrando App Installer (winget)...' -ForegroundColor Cyan
            try {
                Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
                $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller | Sort-Object Version -Descending | Select-Object -First 1
            } catch { }
        }
        if ($pkg) {
            $c = Join-Path $pkg.InstallLocation 'winget.exe'
            if (Test-Path $c) { $wgPath = $c }
        }
    }
    if (-not $wgPath) {
        throw 'No encuentro winget. Instala "Instalador de aplicacion" (App Installer) desde la Microsoft Store y vuelve a ejecutar.'
    }
    Set-Alias -Name winget -Value $wgPath -Scope Script
    Write-Host "[+] winget encontrado en $wgPath" -ForegroundColor Green
}

# ---------------------------------------------------------------- perfil predeterminado de Terminal
if ($state.terminalDefault -and (Test-Path $state.terminalDefault.path)) {
    $td = $state.terminalDefault
    $raw   = Get-Content $td.path -Raw
    $clean = ($raw -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    try { $wt = $clean | ConvertFrom-Json } catch { $wt = $null }
    if ($wt -and $wt.defaultProfile -eq $td.new -and $td.prev) {
        $wt.defaultProfile = $td.prev
        $wt | ConvertTo-Json -Depth 32 | Set-Content -Path $td.path -Encoding UTF8
        Ok 'Terminal vuelve a abrir el perfil que tenias antes.'
    }
}

# ---------------------------------------------------------------- Windows Terminal
if ($state.terminal) {
    $t = $state.terminal
    if (Test-Path $t.path) {
        $raw   = Get-Content $t.path -Raw
        $clean = ($raw -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
        try { $wt = $clean | ConvertFrom-Json } catch { $wt = $null }
        if ($wt) {
            if ($t.addedScheme) {
                $wt.schemes = @(@($wt.schemes) | Where-Object { $_.name -ne 'Catppuccin Mocha' })
            }
            $def = $wt.profiles.defaults
            if ($def) {
                if ($def.colorScheme -eq 'Catppuccin Mocha') {
                    if ($t.prevColorScheme) { $def.colorScheme = $t.prevColorScheme }
                    else { $def.PSObject.Properties.Remove('colorScheme') }
                }
                if ($def.font -and $def.font.face -eq 'JetBrainsMono Nerd Font') {
                    if ($t.prevFontFace) { $def.font.face = $t.prevFontFace }
                    else {
                        $def.font.PSObject.Properties.Remove('face')
                        if (-not $def.font.PSObject.Properties.Name) { $def.PSObject.Properties.Remove('font') }
                    }
                }
            }
            $wt | ConvertTo-Json -Depth 32 | Set-Content -Path $t.path -Encoding UTF8
            Ok 'Windows Terminal: tema y fuente devueltos a como estaban.'
        } elseif (Test-Path $t.backup) {
            Copy-Item $t.backup $t.path -Force
            Ok 'Windows Terminal: restaurada la copia de seguridad.'
        }
    }
    if ($t.backup -and (Test-Path $t.backup)) { Remove-Item $t.backup -Force }
}

# ---------------------------------------------------------------- perfiles de PowerShell
$pattern = "(?s)\r?\n?# >>> $Marker >>>.*?# <<< $Marker <<<\r?\n?"
foreach ($pp in @($state.profilesModified)) {
    if ($pp -and (Test-Path $pp)) {
        $c = Get-Content $pp -Raw
        Set-Content -Path $pp -Value ([regex]::Replace($c, $pattern, "`r`n").TrimEnd()) -Encoding UTF8
        Ok "Quitado el bloque del perfil: $pp"
    }
}
foreach ($pp in @($state.profilesCreated)) {
    if ($pp -and (Test-Path $pp)) {
        $rest = [regex]::Replace((Get-Content $pp -Raw), $pattern, '').Trim()
        if ($rest) { Set-Content -Path $pp -Value $rest -Encoding UTF8; Ok "Limpiado perfil: $pp" }
        else { Remove-Item $pp -Force; Ok "Borrado perfil creado por el script: $pp" }
    }
}

# ---------------------------------------------------------------- starship.toml
if ($state.starshipConfig -and (Test-Path $state.starshipConfig)) {
    if ($state.starshipBackup -and (Test-Path $state.starshipBackup)) {
        Move-Item $state.starshipBackup $state.starshipConfig -Force
        Ok 'starship.toml: restaurado el que tenias antes.'
    } else {
        Remove-Item $state.starshipConfig -Force
        Ok 'starship.toml borrado.'
    }
}

# ---------------------------------------------------------------- execution policy
if ($state.executionPolicyPrev) {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $state.executionPolicyPrev -Force
        Ok "ExecutionPolicy (usuario) devuelta a $($state.executionPolicyPrev)."
    } catch { Warn "No pude restaurar la ExecutionPolicy: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- plugins de Flow
if (@($state.flowPlugins).Count) { Stop-RiceApp 'flow'; Start-Sleep -Seconds 1 }
foreach ($pp in @($state.flowPlugins)) {
    if ($pp -and (Test-Path -LiteralPath $pp)) { Remove-Item -LiteralPath $pp -Recurse -Force -ErrorAction SilentlyContinue; Ok "Plugin de Flow quitado: $(Split-Path $pp -Leaf)" }
}

# ---------------------------------------------------------------- config exportada
foreach ($c in @($state.configApplied)) { if ($c -and $c.app) { Stop-RiceApp $c.app } }
Start-Sleep -Seconds 1
foreach ($c in @($state.configApplied)) {
    if (-not $c -or -not $c.target) { continue }
    if (Test-Path -LiteralPath $c.target) { Remove-Item -LiteralPath $c.target -Recurse -Force -ErrorAction SilentlyContinue }
    if ($c.backup -and (Test-Path -LiteralPath $c.backup)) {
        Move-Item -LiteralPath $c.backup -Destination $c.target -Force
        Ok "Config de $($c.name): restaurada la que tenias antes."
    } else { Ok "Config de $($c.name) quitada." }
}

# ---------------------------------------------------------------- fondo, ajustes de Windows, autoarranque
Stop-RiceCursorWatcher
Restore-RiceCursor $state
Restore-RiceWallpaper $state
Restore-RiceTweaks $state
Remove-RiceAutostart $state

# ---------------------------------------------------------------- paquetes
$pkgs = @($state.installedPackages)
[array]::Reverse($pkgs)
foreach ($id in $pkgs) {
    if (-not $id) { continue }
    if ($id -eq 'Seelen.SeelenUI') { Stop-RiceApp 'seelen' }
    if ($id -eq 'Flow-Launcher.Flow-Launcher') { Get-Process -Name 'Flow.Launcher' -ErrorAction SilentlyContinue | Stop-Process -Force }
    Info "Desinstalando $id..."
    $code = Invoke-RiceWingetUninstall $id 300
    if ($code -eq 'timeout') {
        Warn "$id tarda demasiado (se ha colgado el desinstalador). Lo cierro y reintento una vez..."
        if ($id -eq 'Seelen.SeelenUI') { Stop-RiceApp 'seelen' }
        $code = Invoke-RiceWingetUninstall $id 300
    }
    if ($code -eq '0') { Ok "$id desinstalado." }
    elseif ($code -eq 'timeout') { Warn "${id}: sigue colgado. Quitalo desde Configuracion > Aplicaciones > Aplicaciones instaladas y sigue." }
    elseif ($code -eq '-1978335107') {
        Info "$id es de usuario: reintento sin privilegios de administrador..."
        $c = Uninstall-RiceUnelevated $id
        if ($c -eq "0") { Ok "$id desinstalado." } else { Warn "${id}: no se pudo (codigo $c). Quitalo desde Configuracion > Aplicaciones." }
    }
    else { Warn "${id}: winget devolvio $code (quitalo desde Configuracion > Aplicaciones si sigue ahi)." }
}

# ---------------------------------------------------------------- restos y barra de tareas de Windows
Stop-RiceLeftovers -Seelen:(@($state.installedPackages) -contains 'Seelen.SeelenUI')
Restore-RiceTaskbar $state

# ---------------------------------------------------------------- purge opcional
if ($Purge) {
    $map = @{
        'Seelen.SeelenUI'             = @((Join-Path $env:APPDATA 'com.seelen.seelen-ui'), (Join-Path $env:LOCALAPPDATA 'com.seelen.seelen-ui'))
        'Flow-Launcher.Flow-Launcher' = @((Join-Path $env:APPDATA 'FlowLauncher'))
        'ajeetdsouza.zoxide'          = @((Join-Path $env:LOCALAPPDATA 'zoxide'))
        'voidtools.Everything'        = @((Join-Path $env:APPDATA 'Everything'))
    }
    foreach ($id in @($state.installedPackages)) {
        if ($map.ContainsKey($id)) {
            foreach ($dir in $map[$id]) {
                if (Test-Path $dir) { Remove-Item $dir -Recurse -Force; Ok "Borrada config: $dir" }
            }
        }
    }
}

Remove-Item $StateDir -Recurse -Force
Write-Host ''
Ok 'Hecho. Reinicia (o cierra sesion) para que la barra de tareas de Windows vuelva del todo.'
if (-not $Purge) { Write-Host 'Si quieres borrar tambien las configs de las apps, ejecuta con -Purge la proxima vez.' }
