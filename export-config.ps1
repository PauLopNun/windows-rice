<#
  Windows Rice - exportar tu configuracion
  Guarda en .\config tus ajustes de Seelen UI, Flow Launcher, PowerToys, Everything,
  Starship y tu fondo de pantalla, para que install.ps1 se los aplique a quien lo ejecute.

  Uso (NO hace falta administrador), dentro de esta carpeta:
    powershell -ExecutionPolicy Bypass -File .\export-config.ps1

  Consejo: cierra Seelen y Flow Launcher antes (asi se guardan todos los ajustes) y vuelve a abrirlos.
  Las rutas con tu usuario (C:\Users\tu-usuario) se guardan como marcador y se cambian por
  el usuario de quien instale.
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'rice-lib.ps1')

$outDir = Join-Path $PSScriptRoot 'config'
Write-Host '[*] Exportando lo que haya en este PC...' -ForegroundColor Cyan
$m = Export-RiceConfig $outDir

Write-Host ''
if (@($m.items).Count -eq 0) {
    Write-Host '[!] No he encontrado ninguna config. Abre Seelen/Flow, ajustalos a tu gusto, cierralos y repite.' -ForegroundColor Yellow
} else {
    $apps = @($m.items | ForEach-Object { $_.app } | Select-Object -Unique) -join ', '
    Write-Host "[+] Exportado: $apps$(if ($m.wallpaper) { ' + fondo de pantalla' })." -ForegroundColor Green
    if (-not ($m.items | Where-Object { $_.app -eq 'seelen' })) {
        Write-Host '[!] No hay config de Seelen: nunca se ha guardado nada. Abrelo, ajustalo, cierralo y repite.' -ForegroundColor Yellow
    }
    if (-not ($m.items | Where-Object { $_.app -eq 'flow' })) {
        Write-Host '[!] No hay config de Flow Launcher: abrelo una vez, ajustalo, cierralo y repite.' -ForegroundColor Yellow
    }
}
Write-Host ''
Write-Host 'Ahora comprime la carpeta entera (con config dentro) y pasasela a tu amigo.' -ForegroundColor Cyan
