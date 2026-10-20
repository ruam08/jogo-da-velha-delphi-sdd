@echo off
rem Verificacao de compilacao da O6 numa copia (logs\o6-compile), sem alterar o projeto.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0o6-compile-check.ps1"
echo.
echo Fim. Esta janela fecha em 30 segundos.
timeout /t 30 >nul
