@echo off
rem Validacao da Entrega 5: interface web e testes no navegador.
rem Resultado em logs\step5-validation.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-step5.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da validacao (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
