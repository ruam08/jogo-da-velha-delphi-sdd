@echo off
rem Validacao da Entrega O5: ciclo de vida das salas (faxineiro, abandono, lembranca, desligamento).
rem Resultado em logs\online-o5.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o5.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
