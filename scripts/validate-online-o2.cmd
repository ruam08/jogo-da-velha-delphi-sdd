@echo off
rem Validacao da Entrega O2: API REST de salas, --bind, sabotagens e regressao Playwright.
rem Resultado em logs\online-o2.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o2.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da validacao (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
