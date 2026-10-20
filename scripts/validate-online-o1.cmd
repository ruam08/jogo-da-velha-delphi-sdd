@echo off
rem Validacao da Entrega O1: dominio das salas, EngineCheck, sabotagens e regressao Playwright.
rem Resultado em logs\online-o1.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o1.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da validacao (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
