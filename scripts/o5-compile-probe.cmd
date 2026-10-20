@echo off
rem Diagnostico da O5: encerra o dcc32 travado e compila variantes do teste do faxineiro.
rem Resultado em logs\o5-compile-probe.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0o5-compile-probe.ps1"
echo.
echo Fim. Esta janela fecha em 30 segundos.
timeout /t 30 >nul
