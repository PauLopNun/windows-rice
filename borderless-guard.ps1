<#
  Windows Rice - guardia de ventana sin bordes (se lanza oculto al iniciar sesion; lo instala install.ps1)

  Cuando la ventana en primer plano es un juego (u otra app) en ventana sin bordes que cubre un monitor entero,
  deja el cursor a 2 px del borde inferior de ese monitor. Asi, al tirar el cursor hacia abajo, no sale el dock de
  Seelen ni la barra de tareas de Windows (ambos reaccionan al llegar a la ultima fila de pixeles).
  Tambien intercepta la tecla Windows mientras tanto: abrir Inicio sacaria la barra de tareas, asi que en su lugar abre el
  menu de apps de Seelen (slu widget trigger @seelen/apps-menu). Los atajos Win+tecla se ignoran en el juego.
  La barra de tareas de Windows se mantiene oculta siempre mientras corre la guardia (Seelen ya hace de barra); al cerrarla
  se restaura.
  Al salir del juego (o cambiar a una ventana normal) se suelta el cursor y la tecla al instante.

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
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern System.IntPtr FindWindow(string c, string n);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int cmd);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetWindowPos(System.IntPtr h, System.IntPtr after, int x, int y, int cx, int cy, uint flags);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(System.IntPtr h, out int pid);
[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(System.IntPtr h, int attr, out int val, int size);
'@
[void][RiceGuard]::SetProcessDPIAware()   # sin esto, con escalado de pantalla las coordenadas no coinciden con las del juego

# Tecla Windows: abre Inicio y Windows saca la barra de tareas aunque el cursor este frenado. Mientras la guardia esta activa
# (juego sin bordes en primer plano) se ignora la tecla Windows. Gancho de teclado de bajo nivel en su propio hilo, sin PowerShell
# en la devolucion de llamada, para que no dependa del bucle de abajo.
Add-Type -Namespace '' -Name RiceKb -UsingNamespace System.Threading -MemberDefinition @'
public static volatile bool Active;
delegate IntPtr HookProc(int n, IntPtr w, IntPtr l);
static HookProc proc = Callback;
[StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }
[DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc p, IntPtr mod, uint tid);
[DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
[DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
[DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
public static string SluPath;      // slu.exe de Seelen (lo rellena el bucle de abajo)
public static string LogPath;      // guard.log (solo cambios de estado y pulsaciones de Windows)
public static void Log(string s) { try { if (LogPath != null) System.IO.File.AppendAllText(LogPath, DateTime.Now.ToString("HH:mm:ss.fff") + " " + s + "\r\n"); } catch { } }
static bool winDown, other;
static void OpenSeelenMenu() {
    string p = SluPath;
    if (string.IsNullOrEmpty(p)) return;
    ThreadPool.QueueUserWorkItem(delegate(object o) {
        try {
            System.Diagnostics.ProcessStartInfo si = new System.Diagnostics.ProcessStartInfo(p, "widget trigger @seelen/apps-menu");
            si.UseShellExecute = false; si.CreateNoWindow = true;
            System.Diagnostics.Process.Start(si);
        } catch { }
    });
}
static IntPtr Callback(int n, IntPtr w, IntPtr l) {
    if (n >= 0 && LogPath != null) {
        int k = Marshal.ReadInt32(l); int m = (int)w;
        if ((k == 0x5B || k == 0x5C) && (m == 0x100 || m == 0x101)) Log("tecla Win " + (m == 0x100 ? "abajo" : "arriba") + " Active=" + Active + " slu=" + (SluPath != null));
    }
    if (n >= 0 && Active) {
        int vk = Marshal.ReadInt32(l); int msg = (int)w;
        bool down = (msg == 0x100 || msg == 0x104);
        if (vk == 0x5B || vk == 0x5C) {
            if (down) { if (!winDown) { winDown = true; other = false; } }
            else if (winDown) { winDown = false; if (!other) OpenSeelenMenu(); }   // pulsar y soltar sola: menu de Seelen
            return (IntPtr)1;
        }
        if (down && winDown) other = true;
    }
    return CallNextHookEx(IntPtr.Zero, n, w, l);
}
// Barra de tareas de Windows: Seelen ya hace de barra, asi que se mantiene oculta mientras corra la guardia. Hilo propio y
// muy rapido (20 ms): el Explorador la vuelve a mostrar con su animacion al cambiar de ventana/monitor, y asi ni se llega a ver.
public static volatile bool HideTray;
[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string c, string n);
[DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
public static void ShowTray() {
    foreach (string c in new string[] { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" }) { IntPtr h = FindWindow(c, null); if (h != IntPtr.Zero) ShowWindow(h, 4); }
}
public static void Start() {
    Thread t = new Thread(delegate() { SetWindowsHookEx(13, proc, GetModuleHandle(null), 0); MSG m; while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { } });
    t.IsBackground = true; t.Start();
    Thread u = new Thread(delegate() {
        while (true) {
            if (HideTray) {
                foreach (string c in new string[] { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" }) {
                    IntPtr h = FindWindow(c, null);
                    if (h != IntPtr.Zero && IsWindowVisible(h)) ShowWindow(h, 0);
                }
            }
            Thread.Sleep(20);
        }
    });
    u.IsBackground = true; u.Start();
}
'@
[RiceKb]::LogPath = Join-Path $PSScriptRoot 'guard.log'
if ((Test-Path ([RiceKb]::LogPath)) -and (Get-Item ([RiceKb]::LogPath)).Length -gt 200KB) { Remove-Item ([RiceKb]::LogPath) -Force }
[RiceKb]::Start()

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
    $script:gameHwnd = $h; $script:gameMon = $m      # para devolverle el pixel que Windows le quita cuando pierde el foco (ver el bucle)
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
$wasActive = $false; $wasMenu = $false; $lastGame = $null; $lastFg = ''; $fixLogged = $false; $script:gameHwnd = $null
[RiceKb]::HideTray = $true
try {
    while ($true) {
        $rect = Get-GuardRect
        if ([bool]$rect -ne $wasActive) {      # log: solo cuando cambia el estado
            $wasActive = [bool]$rect
            $fh = [RiceGuard]::GetForegroundWindow(); [void]$sb.Clear(); [void][RiceGuard]::GetClassName($fh, $sb, 256)
            [RiceKb]::Log("guardia " + $(if ($wasActive) { 'ACTIVA' } else { 'inactiva' }) + " | ventana: clase=" + $sb.ToString())
        }
        # el menu de Seelen (lo abre la tecla Win) toma el foco: justo despues de un juego se sigue interceptando Win,
        # para que la siguiente pulsacion lo cierre en vez de abrir Inicio (y con el la barra de Windows)
        $seelenMenu = $false
        if (-not $rect -and $lastGame -and ((Get-Date) - $lastGame).TotalSeconds -lt 60) {
            $fh2 = [RiceGuard]::GetForegroundWindow(); [void]$sb.Clear(); [void][RiceGuard]::GetClassName($fh2, $sb, 256)
            if ($sb.ToString() -eq 'Tauri Window') {
                $wp = 0; [void][RiceGuard]::GetWindowThreadProcessId($fh2, [ref]$wp)
                if ((Get-Process -Id $wp -ErrorAction SilentlyContinue).ProcessName -eq 'seelen-ui') { $seelenMenu = $true }
            }
        }
        if ($rect) { $lastGame = Get-Date }
        # Al quitarle el foco (menu de Seelen), Windows recorta 1 px de alto a la ventana del juego y esa fila deja ver lo que hay
        # detras (una linea oscura abajo). Se le devuelve el tamano completo del monitor.
        if ($seelenMenu -and $script:gameHwnd -and [RiceGuard]::IsWindowVisible($script:gameHwnd)) {
            $gw = New-Object RiceGuard+RECT
            if ([RiceGuard]::GetWindowRect($script:gameHwnd, [ref]$gw)) {
                $gm = $script:gameMon; $short = $gm.B - $gw.B
                if ($short -ge 1 -and $short -le 3 -and $gw.L -le $gm.L -and $gw.R -ge $gm.R -and $gw.T -le $gm.T) {
                    [void][RiceGuard]::SetWindowPos($script:gameHwnd, [IntPtr]::Zero, $gw.L, $gw.T, ($gw.R - $gw.L), ($gm.B - $gw.T), 0x0014)   # SWP_NOZORDER | SWP_NOACTIVATE
                    if (-not $fixLogged) { $fixLogged = $true; [RiceKb]::Log("juego recortado $short px: devuelto al tamano completo") }
                }
            }
        }
        if (-not $seelenMenu) { $fixLogged = $false }
        # diagnostico: ventana que toma el foco poco despues de un juego (para ver que sale en el hueco al abrir el menu)
        if ($lastGame -and ((Get-Date) - $lastGame).TotalSeconds -lt 8) {
            $fh3 = [RiceGuard]::GetForegroundWindow(); [void]$sb.Clear(); [void][RiceGuard]::GetClassName($fh3, $sb, 256)
            if ($sb.ToString() -ne $lastFg) { $lastFg = $sb.ToString(); [RiceKb]::Log("  foco -> " + $lastFg) }
        }
        if ($seelenMenu -ne $wasMenu) { $wasMenu = $seelenMenu; [RiceKb]::Log("menu de Seelen en primer plano: " + $seelenMenu) }
        if ($rect) {
            if (-not [RiceKb]::SluPath -or -not (Test-Path ([RiceKb]::SluPath))) {      # slu.exe va junto a seelen-ui.exe (la ruta cambia al actualizar Seelen)
                $sp = (Get-Process seelen-ui -ErrorAction SilentlyContinue | Select-Object -First 1).Path
                if ($sp) { [RiceKb]::SluPath = Join-Path (Split-Path $sp) 'slu.exe' }
            }
            [void][RiceGuard]::ClipCursor([ref]$rect); $clipped = $true; [RiceKb]::Active = $true
        }   # se repite: algunos juegos sueltan el cursor
        else { [RiceKb]::Active = $seelenMenu; if ($clipped) { [void][RiceGuard]::ClipCursor([IntPtr]::Zero); $clipped = $false } }
        Start-Sleep -Milliseconds 300
    }
} finally {
    [RiceKb]::HideTray = $false; [RiceKb]::ShowTray()      # al cerrarse la guardia, la barra de Windows vuelve
    [RiceKb]::Active = $false
    if ($clipped) { [void][RiceGuard]::ClipCursor([IntPtr]::Zero) }
}
