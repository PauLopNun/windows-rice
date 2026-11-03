<#
  Windows Rice - guardia de ventana sin bordes (se lanza oculto al iniciar sesion; lo instala install.ps1)

  Cuando la ventana en primer plano es un juego (u otra app) en ventana sin bordes que cubre un monitor entero,
  deja el cursor a 2 px del borde inferior de ese monitor. Asi, al tirar el cursor hacia abajo, no sale el dock de
  Seelen ni la barra de tareas de Windows (ambos reaccionan al llegar a la ultima fila de pixeles).
  Al salir del juego (o cambiar a una ventana normal) se suelta el cursor al instante.

  Solo mira la ventana en primer plano 3 veces por segundo. Solo hay una copia a la vez. Se puede cerrar desde el
  Administrador de tareas (powershell.exe) sin consecuencias: al cerrarse suelta el cursor.
#>
$ErrorActionPreference = 'SilentlyContinue'

$mutex = New-Object System.Threading.Mutex($false, 'Local\windows-rice-borderless-guard')
if (-not $mutex.WaitOne(0)) { return }
$PID | Set-Content -Path (Join-Path $PSScriptRoot 'guard-pid.txt') -Encoding ASCII

Add-Type -Namespace '' -Name RiceGuard -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct RECT { public int L, T, R, B; }
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public int dwFlags; }
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RECT r);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetWindowLong(System.IntPtr h, int i);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr MonitorFromWindow(System.IntPtr h, int flags);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetMonitorInfo(System.IntPtr m, ref MONITORINFO mi);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ClipCursor(ref RECT r);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetClipCursor(out RECT r);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ClipCursor(System.IntPtr r);
[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(System.IntPtr h, int attr, out int val, int size);
'@
[void][RiceGuard]::SetProcessDPIAware()   # sin esto, con escalado de pantalla las coordenadas no coinciden con las del juego

$WS_CAPTION = 0xC00000
$MARGIN     = 2     # px que se dejan libres abajo
$skipClass  = @('Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd', 'XamlExplorerHostIslandWindow')
$sb = New-Object System.Text.StringBuilder 256

# devuelve el rectangulo (RECT) al que limitar el cursor, o $null si la ventana en primer plano no es "sin bordes a pantalla completa"
function Get-GuardRect {
    $h = [RiceGuard]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero -or -not [RiceGuard]::IsWindowVisible($h) -or [RiceGuard]::IsIconic($h)) { return $null }
    if (([RiceGuard]::GetWindowLong($h, -16) -band $WS_CAPTION) -eq $WS_CAPTION) { return $null }   # tiene barra de titulo: ventana normal
    [void]$sb.Clear(); [void][RiceGuard]::GetClassName($h, $sb, 256)
    if ($skipClass -contains $sb.ToString()) { return $null }
    $cloaked = 0; [void][RiceGuard]::DwmGetWindowAttribute($h, 14, [ref]$cloaked, 4)               # DWMWA_CLOAKED (apps UWP en segundo plano)
    if ($cloaked) { return $null }
    $w = New-Object RiceGuard+RECT
    if (-not [RiceGuard]::GetWindowRect($h, [ref]$w)) { return $null }
    $mon = [RiceGuard]::MonitorFromWindow($h, 2)                                                    # MONITOR_DEFAULTTONEAREST
    $mi  = New-Object RiceGuard+MONITORINFO; $mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
    if (-not [RiceGuard]::GetMonitorInfo($mon, [ref]$mi)) { return $null }
    $m = $mi.rcMonitor
    # tiene que cubrir el monitor entero (como un juego en ventana sin bordes o a pantalla completa)
    if ($w.L -gt $m.L -or $w.T -gt $m.T -or $w.R -lt $m.R -or $w.B -lt $m.B) { return $null }
    # zona permitida: todo el escritorio virtual si el monitor del juego es el que llega mas abajo (se puede seguir pasando
    # a otro monitor a los lados); si no, solo ese monitor
    $vl = [RiceGuard]::GetSystemMetrics(76); $vt = [RiceGuard]::GetSystemMetrics(77)
    $vr = $vl + [RiceGuard]::GetSystemMetrics(78); $vb = $vt + [RiceGuard]::GetSystemMetrics(79)
    $c = New-Object RiceGuard+RECT
    if ($m.B -eq $vb) { $c.L = $vl; $c.T = $vt; $c.R = $vr; $c.B = $vb - $MARGIN }
    else              { $c.L = $m.L; $c.T = $m.T; $c.R = $m.R; $c.B = $m.B - $MARGIN }
    # si el juego ya limita el cursor (p. ej. a su ventana), se respeta: solo se recorta lo de abajo, sin soltarlo hacia otros monitores
    $cur = New-Object RiceGuard+RECT
    if ([RiceGuard]::GetClipCursor([ref]$cur)) {
        $c.L = [Math]::Max($c.L, $cur.L); $c.T = [Math]::Max($c.T, $cur.T)
        $c.R = [Math]::Min($c.R, $cur.R); $c.B = [Math]::Min($c.B, $cur.B)
        if ($c.R -le $c.L -or $c.B -le $c.T) { return $null }
    }
    return $c
}

$clipped = $false
try {
    while ($true) {
        $rect = Get-GuardRect
        if ($rect) { [void][RiceGuard]::ClipCursor([ref]$rect); $clipped = $true }                 # se repite: algunos juegos sueltan el cursor
        elseif ($clipped) { [void][RiceGuard]::ClipCursor([IntPtr]::Zero); $clipped = $false }
        Start-Sleep -Milliseconds 300
    }
} finally {
    if ($clipped) { [void][RiceGuard]::ClipCursor([IntPtr]::Zero) }
}
