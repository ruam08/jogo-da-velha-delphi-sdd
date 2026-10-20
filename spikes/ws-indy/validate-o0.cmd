@echo off
rem Validacao da Entrega O0: prova de conceito WebSocket (descartavel).
rem Resultado em logs\online-o0.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-o0.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da validacao (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
