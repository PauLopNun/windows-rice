<#
  Windows Rice - vigilante del cursor (se lanza oculto al iniciar sesion; lo instala install.ps1)

  Espera (sin gastar CPU) a que Windows cambie entre modo oscuro y claro, ya sea desde Configuracion,
  desde Seelen o desde theme.ps1, y entonces cambia el cursor: Classic (negro) en oscuro, Ice (blanco) en claro.
  Solo hay una copia a la vez. Se puede cerrar desde el Administrador de tareas (powershell.exe) sin consecuencias.
#>
$ErrorActionPreference = 'SilentlyContinue'

$mutex = New-Object System.Threading.Mutex($false, 'Local\windows-rice-cursor-watcher')
if (-not $mutex.WaitOne(0)) { return }
$PID | Set-Content -Path (Join-Path $PSScriptRoot 'pid.txt') -Encoding ASCII

. (Join-Path $PSScriptRoot 'rice-lib.ps1')
$json = Join-Path $PSScriptRoot 'cursor.json'

Add-Type -Namespace '' -Name RiceReg -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("advapi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int RegOpenKeyEx(System.UIntPtr hKey, string subKey, int options, int sam, out System.IntPtr result);
[System.Runtime.InteropServices.DllImport("advapi32.dll")]
public static extern int RegNotifyChangeKeyValue(System.IntPtr hKey, bool watchSubtree, int filter, System.IntPtr hEvent, bool async);
[System.Runtime.InteropServices.DllImport("advapi32.dll")]
public static extern int RegCloseKey(System.IntPtr hKey);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool SetProcessWorkingSetSize(System.IntPtr proc, System.IntPtr min, System.IntPtr max);
'@

# devuelve a Windows la memoria que no se usa mientras el vigilante duerme (baja la RAM residente de ~100 MB a unos pocos)
function Trim-Memory { [GC]::Collect(); [void][RiceReg]::SetProcessWorkingSetSize([System.Diagnostics.Process]::GetCurrentProcess().Handle, [IntPtr](-1), [IntPtr](-1)) }

$HKCU   = New-Object System.UIntPtr ([uint64]2147483649)    # HKEY_CURRENT_USER
$subKey = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

# al arrancar, el cursor del modo actual
$last = Get-RiceWindowsMode
[void](Set-RiceCursorMode $json $last)

$ev = New-Object System.Threading.ManualResetEvent($false)
while ($true) {
    $h = [IntPtr]::Zero
    if ([RiceReg]::RegOpenKeyEx($HKCU, $subKey, 0, 0x10, [ref]$h) -ne 0) { Start-Sleep -Seconds 10; continue }
    [void]$ev.Reset()
    [void][RiceReg]::RegNotifyChangeKeyValue($h, $false, 4, $ev.SafeWaitHandle.DangerousGetHandle(), $true)   # 4 = cambio de un valor
    # se comprueba DESPUES de armar el aviso: si el modo cambio mientras se aplicaba el anterior, no se pierde
    $now = Get-RiceWindowsMode
    if ($now -ne $last) {
        [void][RiceReg]::RegCloseKey($h)
        $last = $now; [void](Set-RiceCursorMode $json $now)
        continue
    }
    Trim-Memory
    [void]$ev.WaitOne()                                                                                       # duerme hasta que cambie
    [void][RiceReg]::RegCloseKey($h)
    Start-Sleep -Milliseconds 500                                                                              # Windows escribe varios valores seguidos
}
