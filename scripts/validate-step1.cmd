@echo off
rem Validacao da Entrega 1: compila, inicia o servidor e testa /health.
rem O resultado completo fica em logs\step1-validation.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-step1.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da validacao (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
