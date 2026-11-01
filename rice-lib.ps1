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
    foreach ($pn in $script:AppProcs[$app]) { Get-Process -Name $pn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
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
    if (-not $m.wallpaper -or $state.wallpaper) { return }
    $src = Join-Path (Join-Path $cfgRoot 'wallpaper') $m.wallpaper
    if (-not (Test-Path $src)) { return }
    $dstDir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'windows-rice'
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    $dst = Join-Path $dstDir $m.wallpaper
    Copy-Item $src $dst -Force
    $d = Get-ItemProperty 'HKCU:\Control Panel\Desktop'
    $wk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
    $prevBg = (Get-ItemProperty $wk -ErrorAction SilentlyContinue).BackgroundType
    $state.wallpaper = [pscustomobject]@{ file = $dst; prev = $d.WallPaper; prevStyle = $d.WallpaperStyle; prevTile = $d.TileWallpaper; prevBg = $prevBg }
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
    if ($seelen -and -not $NoSeelen) { Start-RiceUnelevated "shell:AppsFolder\$($seelen.AppID)" }
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
    $lines = "@echo off", "`"$wg`" uninstall --id $id --exact --silent --accept-source-agreements", "echo %errorlevel%> `"$res`""
    Set-Content -Path $cmd -Value $lines -Encoding ASCII
    Start-Process explorer.exe -ArgumentList "`"$cmd`""
    for ($i = 0; $i -lt 100 -and -not (Test-Path $res); $i++) { Start-Sleep -Seconds 3 }
    $code = if (Test-Path $res) { (Get-Content $res -Raw).Trim() } else { 'timeout' }
    Remove-Item $cmd, $res -Force -ErrorAction SilentlyContinue
    return $code
}
