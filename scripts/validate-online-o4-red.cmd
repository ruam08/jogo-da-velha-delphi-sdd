@echo off
rem Fase vermelha da Entrega O4: testes novos contra o servidor sem a interface online.
rem Resultado em logs\online-o4-red.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o4.ps1" -RedPhase
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
