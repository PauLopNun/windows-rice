# Funciones compartidas por install.ps1, uninstall.ps1 y export-config.ps1 (no se ejecuta solo).

$script:UserTokens = [ordered]@{
    Esc   = '__RICE_USERPROFILE_ESC__'   # C:\\Users\\x  (dentro de JSON)
    Fwd   = '__RICE_USERPROFILE_FWD__'   # C:/Users/x
    Plain = '__RICE_USERPROFILE__'       # C:\Users\x
}
$script:TextExt = @('.json', '.yml', '.yaml', '.css', '.scss', '.toml', '.ini', '.txt', '.xml', '.config', '.js')
$script:ExcludeDirs  = @('logs', 'Logs', 'log', 'cache', 'Cache', 'Code Cache', 'GPUCache', 'EBWebView', 'Temp', 'tmp',
                         'Updates', 'RunnerLogs', 'crashpad', 'Crashpad')
$script:ExcludeFiles = @('*.log', '*.lock', '*.cli-lock', '*.tmp', '*History*', 'UserSelectedRecord.json', '*.bak*', '*.pre-rice', '*.etl',
                         'settings-placement.json', '*telemetry*', 'last_version_run.json')

# Apps cuya config se viaja. Path admite {APPDATA} {LOCALAPPDATA} {USERPROFILE} {PROGRAMFILES} y comodin *.
# Seelen aparece varias veces porque segun la instalacion (MSIX/exe) la guarda en sitios distintos:
# se exporta lo que exista de verdad en tu PC.
$script:RiceItems = @(
    @{ Key = 'seelen-home';     App = 'seelen';     Path = '{USERPROFILE}\.config\seelen' }
    @{ Key = 'seelen-roaming';  App = 'seelen';     Path = '{APPDATA}\com.seelen.seelen-ui' }
    @{ Key = 'seelen-local';    App = 'seelen';     Path = '{LOCALAPPDATA}\com.seelen.seelen-ui' }
    @{ Key = 'seelen-msix';     App = 'seelen';     Path = '{LOCALAPPDATA}\Packages\Seelen.SeelenUI_*\LocalCache\Roaming' }
    @{ Key = 'flow';            App = 'flow';       Path = '{APPDATA}\FlowLauncher' }
    @{ Key = 'powertoys';       App = 'powertoys';  Path = '{LOCALAPPDATA}\Microsoft\PowerToys' }
    @{ Key = 'everything-user'; App = 'everything'; Path = '{APPDATA}\Everything\Everything.ini' }
    @{ Key = 'everything-pf';   App = 'everything'; Path = '{PROGRAMFILES}\Everything\Everything.ini' }
    @{ Key = 'starship';        App = 'starship';   Path = '{USERPROFILE}\.config\starship.toml' }
)
$script:AppProcs = @{
    seelen     = @('seelen*', 'slu-*')
    flow       = @('Flow.Launcher')
    powertoys  = @('PowerToys*', 'Microsoft.CmdPal*')
    everything = @('Everything*')
    starship   = @()
}

# Cambios de Windows (HKCU) que se aplican y se deshacen.
$script:Tweaks = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme';    Value = 0 }
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Value = 0 }
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'HideFileExt';          Value = 0 }
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'TaskbarDa';            Value = 0 }  # boton widgets
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'TaskbarMn';            Value = 0 }  # chat
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name = 'ShowTaskViewButton';   Value = 0 }
)

function Expand-RicePath([string]$p) {
    $pf = if ($env:ProgramFiles) { $env:ProgramFiles } else { 'C:\Program Files' }
    $p.Replace('{APPDATA}', $env:APPDATA).Replace('{LOCALAPPDATA}', $env:LOCALAPPDATA).
       Replace('{USERPROFILE}', $env:USERPROFILE).Replace('{PROGRAMFILES}', $pf)
}
function Compress-RicePath([string]$p) {
    $pf = if ($env:ProgramFiles) { $env:ProgramFiles } else { 'C:\Program Files' }
    foreach ($pair in @(@($env:LOCALAPPDATA, '{LOCALAPPDATA}'), @($env:APPDATA, '{APPDATA}'), @($pf, '{PROGRAMFILES}'), @($env:USERPROFILE, '{USERPROFILE}'))) {
        if ($pair[0] -and $p.StartsWith($pair[0], [StringComparison]::OrdinalIgnoreCase)) { return $pair[1] + $p.Substring($pair[0].Length) }
    }
    $p
}
function Resolve-RiceGlob([string]$expanded) {
    if ($expanded -notmatch '\*') { if (Test-Path -LiteralPath $expanded) { return $expanded } else { return $null } }
    $m = Get-Item -Path $expanded -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { $m.FullName } else { $null }
}

function Convert-RiceText([string]$file, [string]$mode) {   # mode: 'tokenize' | 'detokenize'
    if ($script:TextExt -notcontains ([IO.Path]::GetExtension($file).ToLower())) { return }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $t = [IO.File]::ReadAllText($file, $utf8)
    $u = $env:USERPROFILE
    if ($mode -eq 'tokenize') {
        $n = $t.Replace($u.Replace('\', '\\'), $script:UserTokens.Esc).
                Replace($u.Replace('\', '/'),  $script:UserTokens.Fwd).
                Replace($u,                    $script:UserTokens.Plain)
    } else {
        if ($t -notmatch '__RICE_USERPROFILE') { return }
        $n = $t.Replace($script:UserTokens.Esc,   $u.Replace('\', '\\')).
                Replace($script:UserTokens.Fwd,   $u.Replace('\', '/')).
                Replace($script:UserTokens.Plain, $u)
    }
    if ($n -ne $t) { [IO.File]::WriteAllText($file, $n, $utf8) }
}

function Copy-RiceTree([string]$src, [string]$dst, [string[]]$extraXD = @()) {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    $xd = @($script:ExcludeDirs | ForEach-Object { $_ }) + $extraXD
    robocopy $src $dst /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD @xd /XF @($script:ExcludeFiles) | Out-Null
    # robocopy: codigos < 8 = bien
    if ($LASTEXITCODE -ge 8) { Write-Host "[!] robocopy fallo copiando $src (codigo $LASTEXITCODE)" -ForegroundColor Yellow }
    $global:LASTEXITCODE = 0
}

# ------------------------------------------------------------------ exportar
function Get-WallpaperSource {
    # el fondo activo; si Windows lo tiene como TranscodedWallpaper (copia interna), el original esta en WallpaperSource
    $p = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).WallPaper
    if (-not $p -or $p -match 'TranscodedWallpaper' -or -not (Test-Path -LiteralPath $p)) {
        $p = (Get-ItemProperty 'HKCU:\Software\Microsoft\Internet Explorer\Desktop\General' -ErrorAction SilentlyContinue).WallpaperSource
    }
    if ($p -and (Test-Path -LiteralPath $p)) { $p } else { $null }
}

function Export-RiceConfig([string]$outDir) {
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $outDir | Out-Null
    $manifest = [ordered]@{
        exportedAt = (Get-Date).ToString('s'); items = @(); wallpaper = $null; versions = [ordered]@{}
    }
    foreach ($it in $script:RiceItems) {
        $real = Resolve-RiceGlob (Expand-RicePath $it.Path)
        if (-not $real) { continue }
        $dest = Join-Path $outDir $it.Key
        $isFile = (Test-Path -LiteralPath $real -PathType Leaf)
        if ($isFile) {
            New-Item -ItemType Directory -Path $dest | Out-Null
            Copy-Item -LiteralPath $real -Destination $dest -Force
            Get-ChildItem $dest -File | ForEach-Object { Convert-RiceText $_.FullName 'tokenize' }
        } else {
            if (-not (Get-ChildItem -LiteralPath $real -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)) { continue }
            # de Flow no se copian los DLL de plugins (install.ps1 los baja de su release oficial); si sus ajustes
            $extra = @(); if ($it.App -eq 'flow') { $extra = @((Join-Path $real 'Plugins')) }
            Copy-RiceTree $real $dest $extra
            # el dock lleva las apps ancladas de TU PC: en otro PC saldrian rotas, que Seelen cree el suyo
            if ($it.App -eq 'seelen') { Remove-Item (Join-Path $dest 'data\seelen-weg\state.yml') -Force -ErrorAction SilentlyContinue }
            Get-ChildItem $dest -Recurse -File | ForEach-Object { Convert-RiceText $_.FullName 'tokenize' }
        }
        $bytes = (Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum
        $manifest.items += [ordered]@{ key = $it.Key; app = $it.App; path = $it.Path; literal = (Compress-RicePath $real); isFile = $isFile; bytes = $bytes }
        Write-Host ("[+] {0,-16} {1}  ({2:N1} MB)" -f $it.Key, $real, ($bytes / 1MB)) -ForegroundColor Green
    }
    # fondo de pantalla
    $wp = Get-WallpaperSource
    if ($wp) {
        $wd = Join-Path $outDir 'wallpaper'
        New-Item -ItemType Directory -Path $wd | Out-Null
        $name = 'wallpaper' + [IO.Path]::GetExtension($wp)
        if (-not [IO.Path]::GetExtension($wp)) { $name = 'wallpaper.jpg' }
        Copy-Item -LiteralPath $wp -Destination (Join-Path $wd $name) -Force
        $manifest.wallpaper = $name
        Write-Host "[+] fondo de pantalla: $wp" -ForegroundColor Green
    }
    # versiones (para avisar si el formato de ajustes puede haber cambiado)
    $sv = Get-AppxPackage -Name 'Seelen.SeelenUI' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sv) { $manifest.versions.seelen = "$($sv.Version)" }
    $fl = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'FlowLauncher') -Directory -Filter 'app-*' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if ($fl) { $manifest.versions.flow = $fl.Name -replace '^app-', '' }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $outDir 'manifest.json') -Encoding UTF8

    # aviso de posibles secretos
    $sus = Get-ChildItem $outDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $script:TextExt -contains $_.Extension.ToLower() -and $_.Length -lt 5MB } |
        Select-String -Pattern '(api[_-]?key|secret|password|passwd|bearer|access[_-]?token|auth[_-]?token)' -List -ErrorAction SilentlyContinue
    if ($sus) {
        Write-Host ''
        Write-Host '[!] Estos archivos mencionan claves/contrasenas/tokens. Revisalos antes de pasarlos:' -ForegroundColor Yellow
        $sus | ForEach-Object { Write-Host "    $($_.Path.Substring($outDir.Length + 1))" -ForegroundColor Yellow }
    }
    return $manifest
}

# ------------------------------------------------------------------ aplicar
function Stop-RiceApp([string]$app) {
    # un proceso con permisos elevados (p. ej. slu-service) no se puede cerrar sin administrador: se ignora, no debe abortar nada
    foreach ($pn in $script:AppProcs[$app]) {
        foreach ($proc in @(Get-Process -Name $pn -ErrorAction SilentlyContinue)) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { }
        }
    }
}

function Apply-RiceConfig([string]$cfgRoot, $state, [scriptblock]$save, [string[]]$skipApps = @()) {
    $mf = Join-Path $cfgRoot 'manifest.json'
    if (-not (Test-Path $mf)) { return $false }
    $m = Get-Content $mf -Raw | ConvertFrom-Json
    $stopped = @{}
    foreach ($it in @($m.items)) {
        $src = Join-Path $cfgRoot $it.key
        if (-not (Test-Path $src)) { continue }
        if ($skipApps -contains $it.app) { continue }
        # destino: la ruta con comodin si existe ya en este PC; si no, la ruta exacta del PC origen
        $target = Resolve-RiceGlob (Expand-RicePath $it.path)
        if (-not $target) { $target = Expand-RicePath $it.literal }
        # config que vive junto a un programa (Program Files): si el programa no esta instalado, no se crea su carpeta
        if ($it.path -like '{PROGRAMFILES}*' -and -not (Test-Path -LiteralPath (Split-Path -Parent $target))) {
            Write-Host "[!] $($it.key): $(Split-Path -Parent $target) no existe (el programa no esta instalado), lo salto." -ForegroundColor Yellow; continue
        }
        if (@($state.configApplied | ForEach-Object { $_.target }) -contains $target) {
            Write-Host "[+] $($it.key): ya aplicada antes, no la piso." -ForegroundColor Green; continue
        }
        if (-not $stopped[$it.app]) { Stop-RiceApp $it.app; $stopped[$it.app] = $true; Start-Sleep -Seconds 1 }
        try {
        $backup = $null
        if (Test-Path -LiteralPath $target) {
            $backup = "$target.bak-windows-rice"
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
            Move-Item -LiteralPath $target -Destination $backup -Force
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        if ($it.isFile) {
            $f = Get-ChildItem $src -File | Select-Object -First 1
            Copy-Item -LiteralPath $f.FullName -Destination $target -Force
            Convert-RiceText $target 'detokenize'
        } else {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            Copy-Item (Join-Path $src '*') -Destination $target -Recurse -Force
            Get-ChildItem -LiteralPath $target -Recurse -File | ForEach-Object { Convert-RiceText $_.FullName 'detokenize' }
        }
        $state.configApplied += [pscustomobject]@{ name = $it.key; app = $it.app; target = $target; backup = $backup }
        & $save
        Write-Host "[+] $($it.key): aplicada en $target" -ForegroundColor Green
        } catch { Write-Host "[!] $($it.key): no se pudo aplicar ($($_.Exception.Message))" -ForegroundColor Yellow }
    }
    # avisos de version
    $sv = Get-AppxPackage -Name 'Seelen.SeelenUI' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sv -and $m.versions.seelen -and "$($sv.Version)" -ne $m.versions.seelen) {
        Write-Host "[!] Seelen: la config se exporto con la v$($m.versions.seelen) y aqui hay la v$($sv.Version). Si algo no carga, es por eso." -ForegroundColor Yellow
    }
    return $true
}

# ------------------------------------------------------------------ fondo de pantalla
function Set-RiceWallpaper([string]$file) {
    if (-not ('RiceNative' -as [type])) {
        Add-Type -Namespace '' -Name RiceNative -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SystemParametersInfo(int a, int b, string c, int d);
'@
    }
    [void][RiceNative]::SystemParametersInfo(20, 0, $file, 3)
}

function Apply-RiceWallpaper([string]$cfgRoot, $state, [scriptblock]$save) {
    $mf = Join-Path $cfgRoot 'manifest.json'
    if (-not (Test-Path $mf)) { return }
    $m = Get-Content $mf -Raw | ConvertFrom-Json
    if (-not $m.wallpaper) { return }
    $src = Join-Path (Join-Path $cfgRoot 'wallpaper') $m.wallpaper
    if (-not (Test-Path $src)) { return }
    # NO en la carpeta Imagenes: en muchos PC esta redirigida a OneDrive y el archivo puede quedar "solo en la nube" (Windows no lo carga)
    $dstDir = Join-Path $env:LOCALAPPDATA 'windows-rice\wallpaper'
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    $dst = Join-Path $dstDir $m.wallpaper
    # si ya se puso y sigue puesto, no se toca; si algo lo cambio (o el archivo falta), se vuelve a poner
    $curWp = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').WallPaper
    if ($state.wallpaper -and $state.wallpaper.file -and (Test-Path -LiteralPath $state.wallpaper.file) -and ($curWp -eq $state.wallpaper.file)) { return }
    Copy-Item $src $dst -Force
    $d = Get-ItemProperty 'HKCU:\Control Panel\Desktop'
    $wk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
    $prevBg = (Get-ItemProperty $wk -ErrorAction SilentlyContinue).BackgroundType
    if ($state.wallpaper) {   # re-aplicar: se conserva lo ORIGINAL del usuario para poder devolverlo al desinstalar
        $state.wallpaper = [pscustomobject]@{ file = $dst; prev = $state.wallpaper.prev; prevStyle = $state.wallpaper.prevStyle; prevTile = $state.wallpaper.prevTile; prevBg = $state.wallpaper.prevBg }
    } else {
        $state.wallpaper = [pscustomobject]@{ file = $dst; prev = $d.WallPaper; prevStyle = $d.WallpaperStyle; prevTile = $d.TileWallpaper; prevBg = $prevBg }
    }
    & $save
    # si Windows esta en modo "Presentacion" (2) o Spotlight, el fondo fijado se pierde: pasar a imagen fija (0)
    if (-not (Test-Path $wk)) { New-Item $wk -Force | Out-Null }
    Set-ItemProperty $wk -Name BackgroundType -Value 0 -Type DWord
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value '0'
    Set-RiceWallpaper $dst
    Write-Host '[+] Fondo de pantalla puesto.' -ForegroundColor Green
}

function Restore-RiceWallpaper($state) {
    $w = $state.wallpaper
    if (-not $w) { return }
    if ($w.prevStyle) { Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value $w.prevStyle }
    if ($w.prevTile)  { Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name TileWallpaper  -Value $w.prevTile }
    if ($null -ne $w.prevBg) { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -Name BackgroundType -Value $w.prevBg -Type DWord }
    if ($w.prev -and (Test-Path -LiteralPath $w.prev)) { Set-RiceWallpaper $w.prev }
    if ($w.file -and (Test-Path -LiteralPath $w.file)) {
        Remove-Item -LiteralPath $w.file -Force
        $dir = Split-Path $w.file
        if (-not (Get-ChildItem $dir -Force -ErrorAction SilentlyContinue)) { Remove-Item $dir -Force }
    }
    Write-Host '[+] Fondo de pantalla devuelto.' -ForegroundColor Green
}

# ------------------------------------------------------------------ ajustes de Windows (registro)
function Broadcast-RiceSettings {
    if (-not ('RiceBroadcast' -as [type])) {
        Add-Type -Namespace '' -Name RiceBroadcast -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr h, uint m, System.UIntPtr w, string l, uint f, uint t, out System.UIntPtr r);
'@
    }
    $r = [UIntPtr]::Zero
    [void][RiceBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$r)
}

function Apply-RiceTweaks($state, [scriptblock]$save) {
    if (-not $state.tweaks) { $state.tweaks = @() }
    $okN = 0; $failed = @()
    foreach ($t in $script:Tweaks) {
        try {
            if (-not (Test-Path $t.Path)) { New-Item -Path $t.Path -Force | Out-Null }
            $cur = Get-ItemProperty -Path $t.Path -Name $t.Name -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $t.Path -Name $t.Name -Value $t.Value -Type DWord -ErrorAction Stop
            # solo se apunta (para deshacerlo) lo que de verdad se pudo cambiar
            $known = @($state.tweaks) | Where-Object { $_.path -eq $t.Path -and $_.name -eq $t.Name }
            if (-not $known) {
                $state.tweaks = @($state.tweaks) + [pscustomobject]@{
                    path = $t.Path; name = $t.Name; existed = [bool]$cur; prev = $(if ($cur) { $cur.($t.Name) } else { $null })
                }
                & $save
            }
            $okN++
        } catch { $failed += $t.Name }
    }
    Broadcast-RiceSettings
    Write-Host "[+] Windows: $okN ajustes aplicados (modo oscuro, extensiones visibles, barra de tareas limpia)." -ForegroundColor Green
    if ($failed.Count) { Write-Host "[!] Windows protege estos ajustes y no se pudieron cambiar (no pasa nada): $($failed -join ', ')" -ForegroundColor Yellow }
}

function Restore-RiceTweaks($state) {
    foreach ($t in @($state.tweaks)) {
        if (-not $t) { continue }
        try {
            if ($t.existed) { Set-ItemProperty -Path $t.path -Name $t.name -Value $t.prev -Type DWord -ErrorAction Stop }
            else { Remove-ItemProperty -Path $t.path -Name $t.name -ErrorAction Stop }
        } catch { }
    }
    if (@($state.tweaks).Count) { Broadcast-RiceSettings; Write-Host '[+] Ajustes de Windows devueltos.' -ForegroundColor Green }
}

# ------------------------------------------------------------------ autoarranque + lanzar
$script:RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Find-RiceExe([string]$app) {
    switch ($app) {
        'flow'       { $c = Join-Path $env:LOCALAPPDATA 'FlowLauncher\Flow.Launcher.exe' }
        'everything' { $c = Join-Path $env:ProgramFiles 'Everything\Everything.exe' }
        'powertoys'  { $c = @((Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe'), (Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe')) }
    }
    $c | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Set-RiceAutostart($state, [scriptblock]$save, [switch]$NoSeelen) {
    $want = @(
        @{ Name = 'windows-rice-flow';       Exe = (Find-RiceExe 'flow');       Args = '' }
        @{ Name = 'windows-rice-everything'; Exe = (Find-RiceExe 'everything'); Args = ' -startup' }
    )
    # Seelen (MSIX) no trae tarea de inicio propia: se arranca igual que desde el menu Inicio (shell:AppsFolder)
    if (-not $NoSeelen) {
        $sa = Get-StartApps -Name '*Seelen*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($sa) { $want += @{ Name = 'windows-rice-seelen'; Exe = 'explorer.exe'; Args = " shell:AppsFolder\$($sa.AppID)" } }
    }
    foreach ($w in $want) {
        if (-not $w.Exe) { continue }
        Set-ItemProperty $script:RunKey -Name $w.Name -Value ('"{0}"{1}' -f $w.Exe, $w.Args)
        if (@($state.runEntries) -notcontains $w.Name) { $state.runEntries = @($state.runEntries) + $w.Name }
    }
    & $save
    Write-Host '[+] Seelen, Flow Launcher y Everything arrancaran con Windows (PowerToys ya lo hace por su tarea de inicio).' -ForegroundColor Green
}

function Remove-RiceAutostart($state) {
    foreach ($n in @($state.runEntries)) { if ($n) { Remove-ItemProperty $script:RunKey -Name $n -ErrorAction SilentlyContinue } }
}

# Lanza SIN privilegios de administrador (via explorer), para que las apps no queden elevadas.
function Start-RiceUnelevated([string]$target) { Start-Process explorer.exe -ArgumentList "`"$target`"" }

function Start-RiceApps([switch]$NoSeelen) {
    $seelen = Get-StartApps -Name '*Seelen*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($seelen -and -not $NoSeelen) {
        # Seelen lee el modo claro/oscuro de Windows al arrancar: si ya estaba abierto, se reinicia para que coja el modo oscuro
        Stop-RiceApp 'seelen'; Start-Sleep -Seconds 2
        Start-RiceUnelevated "shell:AppsFolder\$($seelen.AppID)"
    }
    foreach ($a in 'flow', 'powertoys') { $e = Find-RiceExe $a; if ($e) { Start-RiceUnelevated $e } }
    $ev = Find-RiceExe 'everything'; if ($ev) { Start-Process explorer.exe -ArgumentList "`"$ev`"" }
}

# ------------------------------------------------------------------ plugins de Flow Launcher
# Versiones fijas de plugins.json: se descargan del release oficial de cada plugin y se verifica el SHA256.
function Install-RicePlugins([string]$listFile, $state, [scriptblock]$save) {
    if (-not (Test-Path $listFile)) { return }
    $dir = Join-Path $env:APPDATA 'FlowLauncher\Plugins'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Stop-RiceApp 'flow'; Start-Sleep -Seconds 1
    if (-not $state.flowPlugins) { $state.flowPlugins = @() }
    $tmpRoot = Join-Path $env:TEMP ('rice-plugins-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpRoot | Out-Null
    $plist = Get-Content $listFile -Raw | ConvertFrom-Json
    foreach ($p in $plist) {
        $target = Join-Path $dir ("{0}-{1}" -f ($p.name -replace '[^\w\.\- ]', ''), $p.version)
        if (Test-Path $target) { Write-Host "[+] Plugin $($p.name) ya estaba." -ForegroundColor Green; continue }
        try {
            $zip = Join-Path $tmpRoot ([guid]::NewGuid().ToString('N') + '.zip')
            Invoke-WebRequest $p.url -OutFile $zip -UseBasicParsing
            if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $p.sha256) { throw 'el hash no coincide, no lo instalo' }
            $x = Join-Path $tmpRoot ([guid]::NewGuid().ToString('N')); Expand-Archive $zip $x -Force
            $src = if ($p.subdir) { Join-Path $x $p.subdir } else { $x }
            if (-not (Test-Path (Join-Path $src 'plugin.json'))) { throw 'no hay plugin.json' }
            New-Item -ItemType Directory -Path $target | Out-Null
            Copy-Item (Join-Path $src '*') -Destination $target -Recurse -Force
            $state.flowPlugins = @($state.flowPlugins) + $target; & $save
            Write-Host "[+] Plugin de Flow: $($p.name) $($p.version)" -ForegroundColor Green
        } catch { Write-Host "[!] Plugin $($p.name): $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------ accesos directos del escritorio
# Los instaladores (Flow, Everything, PowerToys...) a veces crean .lnk en el escritorio. Se apuntan antes de instalar
# y se borran SOLO los que han aparecido durante la instalacion (nunca los que ya tenias).
function Get-RiceDesktopLinks {
    $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    $r = @()
    foreach ($d in $dirs) { $r += @(Get-ChildItem -LiteralPath $d -Filter *.lnk -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    return $r
}
function Remove-RiceNewDesktopLinks($before) {
    $n = 0
    foreach ($f in @(Get-RiceDesktopLinks)) {
        if (@($before) -notcontains $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue; $n++ }
    }
    if ($n) { Write-Host "[+] Quitados $n acceso(s) directo(s) que los instaladores dejaron en el escritorio." -ForegroundColor Green }
}

# winget no deja desinstalar apps instaladas "para el usuario" (Flow, PowerToys...) desde una consola de administrador.
# Se reintenta SIN privilegios (via explorer) y se espera el resultado.
function Uninstall-RiceUnelevated([string]$id) {
    $base = Join-Path $env:TEMP ('rice-un-' + [guid]::NewGuid().ToString('N'))
    $cmd = "$base.cmd"; $res = "$base.result"
    $wc = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -First 1
    $wg = if ($wc -and $wc.CommandType -eq 'Alias') { $wc.Definition } elseif ($wc) { $wc.Source } else { Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe' }
    $lines = "@echo off", "`"$wg`" uninstall --id $id --exact --silent --source winget --accept-source-agreements", "echo %errorlevel%> `"$res`""
    Set-Content -Path $cmd -Value $lines -Encoding ASCII
    Start-Process explorer.exe -ArgumentList "`"$cmd`""
    for ($i = 0; $i -lt 100 -and -not (Test-Path $res); $i++) { Start-Sleep -Seconds 3 }
    $code = if (Test-Path $res) { (Get-Content $res -Raw).Trim() } else { 'timeout' }
    Remove-Item $cmd, $res -Force -ErrorAction SilentlyContinue
    return $code
}

# ------------------------------------------------------------------ cursor (Bibata): uno para modo oscuro y otro para claro
# Se descargan del release oficial (version fija + SHA256), se instalan solo para el usuario (sin admin) y se guardan los
# valores anteriores del registro para devolverlos al desinstalar. Bibata es GPL-3.0: no se redistribuye en este repo.
$script:CursorMap = [ordered]@{
    Arrow = 'Pointer.cur'; Help = 'Help.cur'; AppStarting = 'Work.ani'; Wait = 'Busy.ani'; crosshair = 'Cross.cur'
    precisionhair = 'Cross.cur'; IBeam = 'Text.cur'; NWPen = 'Handwriting.cur'; No = 'Unavailable.cur'; SizeNS = 'Vert.cur'
    SizeWE = 'Horz.cur'; SizeNWSE = 'Dgn1.cur'; SizeNESW = 'Dgn2.cur'; Grab = 'Move.cur'; SizeAll = 'Move.cur'
    UpArrow = 'Alternate.cur'; Hand = 'Link.cur'; Pin = 'Pin.cur'; Person = 'Person.cur'; Pan = 'Pan.cur'
    Grabbing = 'Grabbing.cur'; 'Zoom-in' = 'Zoom-in.cur'; 'Zoom-out' = 'Zoom-out.cur'
}
function Send-RiceCursorChange {
    if (-not ('RiceNative' -as [type])) {
        Add-Type -Namespace '' -Name RiceNative -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SystemParametersInfo(int a, int b, string c, int d);
'@
    }
    [void][RiceNative]::SystemParametersInfo(0x57, 0, $null, 3)   # SPI_SETCURSORS: recargar los cursores ya
    # refresco estandar de Windows: aplica los cambios de HKCU al instante (tambien cuando se llama desde un proceso elevado)
    try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\rundll32.exe') -ArgumentList 'user32.dll,UpdatePerUserSystemParameters 1, True' -WindowStyle Hidden -Wait } catch { }
}
function Get-RiceCursorRoot { Join-Path $env:LOCALAPPDATA 'windows-rice\cursors' }
function Get-RiceWindowsMode {
    $p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
    if ($p -and $p.AppsUseLightTheme -eq 1) { 'light' } else { 'dark' }
}
# Pone en el registro el cursor de un modo (dark|light). Devuelve $false si ese cursor no esta instalado.
function Set-RiceCursorMode([string]$jsonFile, [string]$mode) {
    $c = Get-Content $jsonFile -Raw | ConvertFrom-Json
    $v = $c.variants.$mode
    if (-not $v) { return $false }
    $dir = Join-Path (Get-RiceCursorRoot) $v.name
    if (-not (Test-Path (Join-Path $dir 'Pointer.cur'))) { return $false }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors', $true)
    $key.SetValue('', $v.name, 'String')
    foreach ($kv in $script:CursorMap.GetEnumerator()) { $key.SetValue($kv.Key, (Join-Path $dir $kv.Value), 'ExpandString') }
    $key.SetValue('Scheme Source', 1, 'DWord')
    $key.Close()
    Send-RiceCursorChange
    return $true
}
function Install-RiceCursorVariant($v, [string]$root) {
    $ProgressPreference = 'SilentlyContinue'
    $tmp = Join-Path $env:TEMP ('rice-cur-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $zip = Join-Path $tmp 'c.zip'
        Invoke-WebRequest $v.url -OutFile $zip -UseBasicParsing
        if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $v.sha256) { throw "el hash de $($v.name) no coincide, no lo instalo" }
        Expand-Archive $zip -DestinationPath (Join-Path $tmp 'x') -Force
        $src = Join-Path (Join-Path $tmp 'x') $v.subdir
        if (-not (Test-Path (Join-Path $src 'Pointer.cur'))) { throw "el paquete $($v.name) no tiene el formato esperado" }
        $dir = Join-Path $root $v.name
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Copy-Item (Join-Path $src '*.cur'), (Join-Path $src '*.ani') -Destination $dir -Force
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
function Install-RiceCursor([string]$jsonFile, $state, [scriptblock]$save) {
    if (-not (Test-Path $jsonFile)) { return }
    $c = Get-Content $jsonFile -Raw | ConvertFrom-Json
    $root = Get-RiceCursorRoot
    try {
        # lo que habia antes, UNA sola vez, para devolverlo al desinstalar
        if (-not $state.cursor) {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors', $true)
            $prev = @()
            foreach ($n in (@('') + @($script:CursorMap.Keys) + @('Scheme Source'))) {
                $v = $key.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $prev += [pscustomobject]@{ name = $n; value = $v; kind = $(if ($null -ne $v) { "$($key.GetValueKind($n))" } else { $null }) }
            }
            $key.Close()
            $state.cursor = [pscustomobject]@{ dir = $root; prev = $prev }; & $save
        }
        # descargar las variantes que falten (la de oscuro y la de claro)
        foreach ($m in 'dark', 'light') {
            $v = $c.variants.$m
            if ($v -and -not (Test-Path (Join-Path (Join-Path $root $v.name) 'Pointer.cur'))) {
                Install-RiceCursorVariant $v $root
                Write-Host "[+] Cursor $($v.name) descargado (modo $m)." -ForegroundColor Green
            }
        }
        $mode = Get-RiceWindowsMode
        if (Set-RiceCursorMode $jsonFile $mode) { Write-Host "[+] Cursor aplicado para el modo $(if ($mode -eq 'light') { 'claro' } else { 'oscuro' })." -ForegroundColor Green }
        else { Write-Host '[!] Cursor: no se pudo aplicar.' -ForegroundColor Yellow }
    } catch { Write-Host "[!] Cursor: $($_.Exception.Message)" -ForegroundColor Yellow }
}
function Restore-RiceCursor($state) {
    $cur = $state.cursor
    if (-not $cur) { return }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors', $true)
    foreach ($p in @($cur.prev)) {
        if ($null -eq $p.value) { $key.DeleteValue($p.name, $false) }
        else {
            $kind = if ($p.kind) { $p.kind } else { 'String' }
            $key.SetValue($p.name, $p.value, $kind)
        }
    }
    $key.Close()
    Send-RiceCursorChange
    foreach ($d in @($cur.dir, (Get-RiceCursorRoot))) { if ($d -and (Test-Path -LiteralPath $d)) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
    Write-Host '[+] Cursor devuelto al que tenias.' -ForegroundColor Green
}

# ------------------------------------------------------------------ comprobar la barra superior de Seelen
# Seelen puede reescribir su barra al arrancar (o puede venir de una instalacion a medias). Tras abrirlo se compara
# con la del pack por modulos y orden (no por formato) y, si no coincide, se restaura y se reinicia Seelen.
function Get-RiceToolbarSig([string]$text) {
    $sec = ''; $sig = @()
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '^(left|center|right):') { $sec = $Matches[1] }
        elseif ($l -match "^- '?(@[^'\s]+)'?\s*$") { $sig += "$sec|$($Matches[1])" }
        elseif ($l -match '^- id:') { $sig += "$sec|(propio)" }
    }
    return ($sig -join ';')
}
function Ensure-RiceSeelenToolbar([string]$cfgRoot, [int]$waitSeconds = 15) {
    $ref = Join-Path $cfgRoot 'seelen-roaming\data\seelen-fancy-toolbar\state.yml'
    $dst = Join-Path $env:APPDATA 'com.seelen.seelen-ui\data\seelen-fancy-toolbar\state.yml'
    if (-not (Test-Path $ref)) { return }
    Start-Sleep -Seconds $waitSeconds   # darle tiempo a Seelen para que escriba lo que vaya a escribir
    $want = Get-RiceToolbarSig ([IO.File]::ReadAllText($ref))
    $have = if (Test-Path $dst) { Get-RiceToolbarSig ([IO.File]::ReadAllText($dst)) } else { '' }
    if ($want -eq $have) { Write-Host '[+] Barra superior de Seelen: correcta.' -ForegroundColor Green; return }
    Write-Host '[!] La barra superior de Seelen no coincide con la del pack: la restauro y reinicio Seelen.' -ForegroundColor Yellow
    Stop-RiceApp 'seelen'; Start-Sleep -Seconds 2
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    if (Test-Path $dst) { Copy-Item $dst "$dst.bak-windows-rice" -Force }
    Copy-Item $ref $dst -Force
    $app = Get-StartApps -Name '*Seelen*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($app) { Start-RiceUnelevated "shell:AppsFolder\$($app.AppID)" }
    Write-Host '[+] Barra superior de Seelen restaurada.' -ForegroundColor Green
}

# ------------------------------------------------------------------ WebView2 (el motor con el que Seelen dibuja barra y dock)
# El tema de Seelen usa CSS moderno (light-dark() = Chromium 123, oklch(from ...) = Chromium 119). Con un WebView2 antiguo
# el dock sale SIN fondo y los colores de los modulos de la barra fallan.
function Get-RiceWebView2Version {
    foreach ($k in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
                     'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
                     'HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}')) {
        $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).pv
        if ($v) { try { return [version]$v } catch { } }
    }
    return $null
}
function Ensure-RiceWebView2([version]$min = '123.0.0.0') {
    $v = Get-RiceWebView2Version
    if ($v -and $v -ge $min) { Write-Host "[+] WebView2 $v (suficiente para Seelen)." -ForegroundColor Green; return $true }
    Write-Host ("[!] WebView2 " + $(if ($v) { "$v es demasiado antiguo" } else { 'no encontrado' }) + " (Seelen necesita $min o superior): lo actualizo...") -ForegroundColor Yellow
    $wc = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -First 1
    $wg = if ($wc -and $wc.CommandType -eq 'Alias') { $wc.Definition } elseif ($wc) { $wc.Source } else { Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe' }
    & $wg install --id Microsoft.EdgeWebView2Runtime --exact --silent --source winget --accept-package-agreements --accept-source-agreements | Out-Host
    $v2 = Get-RiceWebView2Version
    if ($v2 -and $v2 -ge $min) { Write-Host "[+] WebView2 actualizado a $v2." -ForegroundColor Green; return $true }
    Write-Host '[!] No pude actualizar WebView2. Sin eso el dock sale sin fondo y la barra con colores raros.' -ForegroundColor Yellow
    Write-Host '    Descarga el "Evergreen Standalone Installer" de https://developer.microsoft.com/microsoft-edge/webview2 , instalalo y reinicia Seelen.' -ForegroundColor Yellow
    return $false
}
