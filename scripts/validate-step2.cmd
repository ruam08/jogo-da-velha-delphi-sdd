@echo off
rem Validacao da Entrega 2: compila, roda o EngineCheck, aplica sabotagens
rem e confere a regressao do /health. Resultado em logs\step2-validation.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-step2.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da validacao (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
