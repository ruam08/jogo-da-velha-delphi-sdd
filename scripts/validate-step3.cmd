@echo off
rem Validacao da Entrega 3: compila, roda o EngineCheck, testa a API HTTP real
rem (cenarios A e R), a sabotagem SB-04 e o /health.
rem Resultado em logs\step3-validation.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-step3.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da validacao (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
