@echo off
rem Validacao da Entrega O6: endurecimento (limites, cabecalhos de seguranca e modo publico).
rem Resultado em logs\online-o6.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o6.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
