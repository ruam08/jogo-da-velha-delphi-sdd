@echo off
rem Validacao da Entrega O4: interface online (web\online.html, online.css, online.js).
rem Resultado em logs\online-o4.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o4.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
