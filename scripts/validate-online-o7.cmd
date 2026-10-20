@echo off
rem Validacao da Entrega O7: regressao completa a partir de uma copia limpa (sem publicar nada).
rem Resultado em logs\online-o7.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o7.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
