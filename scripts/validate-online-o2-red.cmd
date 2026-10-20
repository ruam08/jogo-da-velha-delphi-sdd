@echo off
rem Fase vermelha da Entrega O2: testes novos contra os esqueletos de uServerOptions e uRoomHttp.
rem Resultado em logs\online-o2-red.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o2.ps1" -RedPhase
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da fase vermelha (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
