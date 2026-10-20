@echo off
rem Fase vermelha da Entrega O5: testes novos com o faxineiro em esqueleto (nao varre).
rem Resultado em logs\online-o5-red.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o5.ps1" -RedPhase
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
