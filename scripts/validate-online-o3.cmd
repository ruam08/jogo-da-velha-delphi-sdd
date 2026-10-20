@echo off
rem Validacao da Entrega O3: canal em tempo real e politica de origem.
rem Resultado em logs\online-o3.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o3.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
