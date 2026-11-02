#Requires -RunAsAdministrator
<#
  Windows Rice - instalador
  Combo: Seelen UI + PowerToys + Flow Launcher + Everything
         + Windows Terminal (Catppuccin Mocha + JetBrainsMono Nerd Font)
         + Starship + zoxide + fzf + lazygit + fastfetch

  Uso (PowerShell como administrador, dentro de esta carpeta):
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipRestorePoint
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoCli

  Es idempotente: si lo vuelves a ejecutar, salta lo que ya este hecho.
  Todo lo que hace queda apuntado en %LOCALAPPDATA%\windows-rice\state.json
  para que uninstall.ps1 deje el PC como estaba.
#>
[CmdletBinding()]
param(
    [switch]$SkipRestorePoint,
    [switch]$NoCli,
    [switch]$NoTweaks,   # no tocar modo oscuro / extensiones / botones de la barra
    [switch]$NoLaunch,   # no abrir las apps al terminar
    [switch]$NoSeelen,   # modo ligero: sin Seelen (dock/barra). Seelen gasta ~1 GB de RAM
    [switch]$NoCursor    # no cambiar el cursor del raton (Bibata)
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # la barra de progreso de Invoke-WebRequest ralentiza mucho las descargas en PowerShell 5.1
$Marker      = 'windows-rice'
$StateDir    = Join-Path $env:LOCALAPPDATA 'windows-rice'
$StateFile   = Join-Path $StateDir 'state.json'
$SchemeName  = 'Catppuccin Mocha'
$FontFace    = 'JetBrainsMono Nerd Font'
. (Join-Path $PSScriptRoot 'rice-lib.ps1')

function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------- estado
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
$state = [ordered]@{
    installedPackages   = @()
    profilesCreated     = @()
    profilesModified    = @()
    starshipConfig      = $null
    starshipBackup      = $null
    executionPolicyPrev = $null
    terminal            = $null
    terminalDefault     = $null
    configApplied       = @()
    wallpaper           = $null
    tweaks              = @()
    runEntries          = @()
    flowPlugins         = @()
    cursor              = $null
}
if (Test-Path $StateFile) {
    $old = Get-Content $StateFile -Raw | ConvertFrom-Json
    foreach ($p in $old.PSObject.Properties) { $state[$p.Name] = $p.Value }
    $state.installedPackages = @($state.installedPackages)
    $state.profilesCreated   = @($state.profilesCreated)
    $state.profilesModified  = @($state.profilesModified)
    $state.configApplied     = @($state.configApplied | Where-Object { $_ })
    $state.tweaks            = @($state.tweaks | Where-Object { $_ })
    $state.runEntries        = @($state.runEntries | Where-Object { $_ })
    $state.flowPlugins       = @($state.flowPlugins | Where-Object { $_ })
}
function Save-State { $state | ConvertTo-Json -Depth 10 | Set-Content -Path $StateFile -Encoding UTF8 }

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

# ---------------------------------------------------------------- punto de restauracion
if (-not $SkipRestorePoint) {
    Info 'Creando punto de restauracion (puede tardar un poco)...'
    # En un job con limite de tiempo: si el servicio de Windows no responde, Checkpoint-Computer se queda colgado para siempre.
    $job = Start-Job -ScriptBlock {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Antes de windows-rice' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    }
    if (Wait-Job $job -Timeout 90) {
        try { Receive-Job $job -ErrorAction Stop | Out-Null; Ok 'Punto de restauracion creado.' }
        catch {
            Warn "No se pudo crear el punto de restauracion: $($_.Exception.Message)"
            Warn 'Sigo igualmente (no es grave: es solo una copia de seguridad extra).'
        }
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Warn 'El punto de restauracion tardaba demasiado (Windows no respondia). Sigo sin el.'
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- paquetes
$packages = @(
    @{ Id = 'Seelen.SeelenUI';             Name = 'Seelen UI' }
    @{ Id = 'Microsoft.PowerToys';         Name = 'PowerToys' }
    @{ Id = 'Flow-Launcher.Flow-Launcher'; Name = 'Flow Launcher' }
    @{ Id = 'voidtools.Everything';        Name = 'Everything' }
    @{ Id = 'Microsoft.WindowsTerminal';   Name = 'Windows Terminal' }
    @{ Id = 'Microsoft.PowerShell';        Name = 'PowerShell 7' }
    @{ Id = 'DEVCOM.JetBrainsMonoNerdFont';Name = 'JetBrainsMono Nerd Font' }
    @{ Id = 'Starship.Starship';           Name = 'Starship' }
)
if (-not $NoCli) {
    $packages += @(
        @{ Id = 'Git.Git';               Name = 'Git' }
        @{ Id = 'ajeetdsouza.zoxide';    Name = 'zoxide' }
        @{ Id = 'junegunn.fzf';          Name = 'fzf' }
        @{ Id = 'JesseDuffield.lazygit'; Name = 'lazygit' }
        @{ Id = 'Fastfetch-cli.Fastfetch'; Name = 'fastfetch' }
    )
}

if ($NoSeelen) { $packages = @($packages | Where-Object { $_.Id -ne 'Seelen.SeelenUI' }) }

function Test-Installed($pkg) {
    if ($pkg.Appx) { return [bool](Get-AppxPackage -Name $pkg.Appx -ErrorAction SilentlyContinue) }
    # se mira el texto (no el codigo de salida): si un origen como msstore falla, winget devuelve error aunque el programa este
    $out = (winget list --id $pkg.Id --exact --accept-source-agreements 2>&1 | Out-String)
    return ($out -match [regex]::Escape($pkg.Id))
}

$failedPkgs = @()
$desktopBefore = Get-RiceDesktopLinks   # para no dejar accesos directos nuevos en el escritorio

foreach ($pkg in $packages) {
    if (Test-Installed $pkg) {
        Ok "$($pkg.Name) ya estaba instalado, no lo toco."
        continue
    }
    Info "Instalando $($pkg.Name)..."
    $wargs = @('install', '--id', $pkg.Id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
    # --source siempre: si un origen (p. ej. msstore) falla por certificado, winget se niega a elegir y no instala nada
    $srcName = if ($pkg.Source) { $pkg.Source } else { 'winget' }
    $wargs += @('--source', $srcName)
    winget @wargs
    $code = $LASTEXITCODE   # se guarda ya: Test-Installed lo sobrescribe
    if ($code -eq 0 -or (Test-Installed $pkg)) {
        Ok "$($pkg.Name) instalado."
        if ($state.installedPackages -notcontains $pkg.Id) { $state.installedPackages += $pkg.Id }
        Save-State
    } else {
        Warn "Fallo instalando $($pkg.Name) (codigo $code). Puedes reintentar: winget install --id $($pkg.Id) --exact --source winget"
        $failedPkgs += $pkg.Name
    }
}

Remove-RiceNewDesktopLinks $desktopBefore

# refrescar PATH para usar lo recien instalado en esta sesion
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

# ---------------------------------------------------------------- execution policy
$curPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($curPolicy -in @('Undefined', 'Restricted', 'AllSigned')) {
    if (-not $state.executionPolicyPrev) { $state.executionPolicyPrev = "$curPolicy" }
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        Ok 'ExecutionPolicy (usuario) = RemoteSigned, para que cargue el perfil de PowerShell.'
    } catch { Warn "No pude cambiar la ExecutionPolicy: $($_.Exception.Message)" }
    Save-State
}

# ---------------------------------------------------------------- starship config
$starshipDir  = Join-Path $HOME '.config'
$starshipToml = Join-Path $starshipDir 'starship.toml'
if (Test-Path (Join-Path $PSScriptRoot 'config\starship')) {
    Ok 'Starship: se usara el starship.toml de tu config exportada.'
} elseif (Get-Command starship -ErrorAction SilentlyContinue) {
    if (-not $state.starshipConfig) {
        New-Item -ItemType Directory -Force -Path $starshipDir | Out-Null
        if (Test-Path $starshipToml) {
            $backup = "$starshipToml.bak-windows-rice"
            Copy-Item $starshipToml $backup -Force
            $state.starshipBackup = $backup
            Info "Tenias starship.toml, copia de seguridad en $backup"
        }
        starship preset catppuccin-powerline -o $starshipToml 2>$null
        if ($LASTEXITCODE -ne 0) { starship preset nerd-font-symbols -o $starshipToml }
        # evita el aviso 'Scanning current directory timed out' en carpetas enormes (system32...)
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($starshipToml, "scan_timeout = 100`r`n" + [IO.File]::ReadAllText($starshipToml, $utf8), $utf8)
        $state.starshipConfig = $starshipToml
        Save-State
        Ok 'Starship configurado con preset Catppuccin.'
    } else { Ok 'Starship ya estaba configurado por este script.' }
} else { Warn 'starship no esta en el PATH; abre una terminal nueva y vuelve a ejecutar.' }

# ---------------------------------------------------------------- perfiles de PowerShell
$docs = [Environment]::GetFolderPath('MyDocuments')
if (-not $docs) { $docs = Join-Path $HOME 'Documents' }
$profilePaths = @(
    (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),  # PowerShell 5.1
    (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')          # PowerShell 7
)
$block = @"
# >>> $Marker >>>
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (&starship init powershell) }
if (Get-Command zoxide -ErrorAction SilentlyContinue) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }
# <<< $Marker <<<
"@
foreach ($pp in $profilePaths) {
    if (Test-Path $pp) {
        $content = Get-Content $pp -Raw
        if ($content -match [regex]::Escape("# >>> $Marker >>>")) { Ok "Perfil ya configurado: $pp"; continue }
        Add-Content -Path $pp -Value "`r`n$block" -Encoding UTF8
        if ($state.profilesModified -notcontains $pp) { $state.profilesModified += $pp }
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $pp) | Out-Null
        Set-Content -Path $pp -Value $block -Encoding UTF8
        if ($state.profilesCreated -notcontains $pp) { $state.profilesCreated += $pp }
    }
    Ok "Perfil configurado: $pp"
    Save-State
}

# ---------------------------------------------------------------- Windows Terminal
$wtCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
)
$wtPath = $wtCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($state.terminal) {
    Ok 'Windows Terminal ya estaba configurado por este script.'
} elseif (-not $wtPath) {
    Warn 'No encuentro settings.json de Windows Terminal (se crea al abrirlo por primera vez).'
    Warn 'Abre Windows Terminal una vez, cierralo y vuelve a ejecutar este script.'
} else {
    $raw = Get-Content $wtPath -Raw
    $clean = ($raw -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    try { $wt = $clean | ConvertFrom-Json } catch { $wt = $null }

    if (-not $wt -or -not $wt.profiles -or $wt.profiles -is [array]) {
        Warn 'settings.json de Terminal tiene un formato que no se tocar sin riesgo. Lo salto.'
        Warn "Pon a mano: esquema '$SchemeName' y fuente '$FontFace' en Configuracion > Valores predeterminados."
    } else {
        $backup = "$wtPath.bak-windows-rice"
        Copy-Item $wtPath $backup -Force

        $termState = [ordered]@{
            path = $wtPath; backup = $backup
            addedScheme = $false; prevColorScheme = $null; prevFontFace = $null
        }

        $scheme = [pscustomobject][ordered]@{
            name = $SchemeName
            cursorColor = '#F5E0DC'; selectionBackground = '#585B70'
            background = '#1E1E2E'; foreground = '#CDD6F4'
            black = '#45475A'; red = '#F38BA8'; green = '#A6E3A1'; yellow = '#F9E2AF'
            blue = '#89B4FA'; purple = '#F5C2E7'; cyan = '#94E2D5'; white = '#BAC2DE'
            brightBlack = '#585B70'; brightRed = '#F38BA8'; brightGreen = '#A6E3A1'
            brightYellow = '#F9E2AF'; brightBlue = '#89B4FA'; brightPurple = '#F5C2E7'
            brightCyan = '#94E2D5'; brightWhite = '#A6ADC8'
        }
        if (-not ($wt.PSObject.Properties.Name -contains 'schemes')) {
            $wt | Add-Member -NotePropertyName schemes -NotePropertyValue @()
        }
        if (-not (@($wt.schemes) | Where-Object { $_.name -eq $SchemeName })) {
            $wt.schemes = @($wt.schemes) + $scheme
            $termState.addedScheme = $true
        }

        if (-not ($wt.profiles.PSObject.Properties.Name -contains 'defaults')) {
            $wt.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
        }
        $def = $wt.profiles.defaults
        if ($def.PSObject.Properties.Name -contains 'colorScheme') {
            $termState.prevColorScheme = $def.colorScheme
            $def.colorScheme = $SchemeName
        } else {
            $def | Add-Member -NotePropertyName colorScheme -NotePropertyValue $SchemeName
        }
        if (-not ($def.PSObject.Properties.Name -contains 'font')) {
            $def | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{})
        }
        if ($def.font.PSObject.Properties.Name -contains 'face') {
            $termState.prevFontFace = $def.font.face
            $def.font.face = $FontFace
        } else {
            $def.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace
        }

        $wt | ConvertTo-Json -Depth 32 | Set-Content -Path $wtPath -Encoding UTF8
        $state.terminal = $termState
        Save-State
        Ok "Windows Terminal: tema $SchemeName + $FontFace (copia en $backup)."
    }
}

# ---------------------------------------------------------------- PowerShell 7 por defecto en Terminal
if ($state.terminalDefault) {
    Ok 'PowerShell 7 ya es el perfil predeterminado de Terminal.'
} elseif ($wtPath) {
    $raw   = Get-Content $wtPath -Raw
    $clean = ($raw -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    try { $wt = $clean | ConvertFrom-Json } catch { $wt = $null }
    $pwshProfile = $null
    if ($wt -and $wt.profiles -and $wt.profiles.list) {
        $pwshProfile = @($wt.profiles.list) | Where-Object { $_.source -eq 'Windows.Terminal.PowershellCore' } | Select-Object -First 1
    }
    if ($pwshProfile) {
        $state.terminalDefault = [ordered]@{ path = $wtPath; prev = $wt.defaultProfile; new = $pwshProfile.guid }
        if ($wt.PSObject.Properties.Name -contains 'defaultProfile') { $wt.defaultProfile = $pwshProfile.guid }
        else { $wt | Add-Member -NotePropertyName defaultProfile -NotePropertyValue $pwshProfile.guid }
        $wt | ConvertTo-Json -Depth 32 | Set-Content -Path $wtPath -Encoding UTF8
        Save-State
        Ok 'Terminal ahora abre PowerShell 7 por defecto.'
    } else {
        Warn 'Terminal aun no ha detectado PowerShell 7. Cierra TODAS las ventanas de Terminal,'
        Warn 'abre una nueva y vuelve a ejecutar este script: solo hara este paso.'
    }
}

# ---------------------------------------------------------------- config exportada (export-config.ps1)
$cfgRoot   = Join-Path $PSScriptRoot 'config'
$hasConfig = $false
if (Test-Path (Join-Path $cfgRoot 'manifest.json')) {
    Info 'Aplicando la configuracion exportada (Seelen, Flow Launcher, PowerToys, Everything...)'
    $skip = @(); if ($NoSeelen) { $skip = @("seelen") }
    $hasConfig = Apply-RiceConfig $cfgRoot $state { Save-State } $skip
    Apply-RiceWallpaper $cfgRoot $state { Save-State }
} else {
    Warn 'No hay carpeta config\ con manifest.json: solo se instalan las apps, sin configuracion.'
}

# ---------------------------------------------------------------- plugins de Flow Launcher (versiones fijas + SHA256)
Install-RicePlugins (Join-Path $PSScriptRoot 'plugins.json') $state { Save-State }

# ---------------------------------------------------------------- cursor (Bibata Modern Classic, version fija + SHA256)
if (-not $NoCursor) { Install-RiceCursor (Join-Path $PSScriptRoot 'cursor.json') $state { Save-State } }

# ---------------------------------------------------------------- ajustes de Windows + autoarranque
if (-not $NoTweaks) { Apply-RiceTweaks $state { Save-State } }
Set-RiceAutostart $state { Save-State } -NoSeelen:$NoSeelen

# ---------------------------------------------------------------- abrir todo
if (-not $NoLaunch) {
    Info 'Abriendo Seelen UI, Flow Launcher, PowerToys y Everything...'
    Start-RiceApps -NoSeelen:$NoSeelen
    if ($hasConfig -and -not $NoSeelen) { Ensure-RiceSeelenToolbar $cfgRoot }
}

Remove-RiceNewDesktopLinks $desktopBefore   # por si alguna app lo crea al abrirse por primera vez

# ---------------------------------------------------------------- fin
Write-Host ''
if ($failedPkgs.Count) {
    Warn "No se pudieron instalar: $($failedPkgs -join ', ')"
    Warn 'Suele ser la red o la fecha/hora de Windows. Comprueba que son correctas y vuelve a lanzar el comando: salta lo ya hecho y solo reintenta lo que falta.'
    Warn 'Si sigue con un error de certificado, prueba otra red (datos del movil) o desactiva un momento el antivirus o la VPN.'
} elseif ($hasConfig) {
    Ok 'Listo. Todo configurado igual que el PC de origen.'
    Write-Host '   - Abre una terminal NUEVA para ver Starship. Prueba: fastfetch, lazygit, z <carpeta>'
    Write-Host '   - Si el dock/barra no salen, cierra sesion y vuelve a entrar una vez.'
} else {
    Ok 'Listo. Pasos a mano que quedan (2 minutos):'
    Write-Host '   1. Abre Seelen UI y en el asistente activa Dock + Toolbar. Tiling apagado de inicio.'
    Write-Host '   2. Seelen > ajustes: activa "suspender widgets en modo juego".'
    Write-Host '   3. Flow Launcher > Settings > Theme: busca Catppuccin en la tienda de temas.'
    Write-Host '   4. Si Alt+Espacio choca entre Seelen y Flow, desactiva el lanzador de Seelen.'
    Write-Host '   5. Abre una terminal NUEVA para ver Starship. Prueba: fastfetch, lazygit, z <carpeta>'
}
Write-Host ''
Write-Host "Para quitarlo todo: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1" -ForegroundColor Magenta
