@echo off
rem Windows Rice - instalador con doble clic.
rem Pide administrador solo (sin usar PowerShell para pedirlo) y deja la ventana abierta al terminar.
setlocal
title Windows Rice - instalador

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Pidiendo permisos de administrador... acepta el aviso de Windows.
    > "%temp%\rice-elevar.vbs" echo Set UAC = CreateObject^("Shell.Application"^)
    >> "%temp%\rice-elevar.vbs" echo UAC.ShellExecute "cmd.exe", "/c """"%~f0"""" %*", "", "runas", 1
    cscript //nologo "%temp%\rice-elevar.vbs"
    del "%temp%\rice-elevar.vbs" >nul 2>&1
    exit /b
)

cd /d "%~dp0"
echo.
echo Instalando Windows Rice desde %cd% ...
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
echo ===== Terminado (codigo %errorlevel%). Si ha fallado algo, copia el texto de arriba. =====
pause
