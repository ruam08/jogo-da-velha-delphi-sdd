@echo off
rem Fase vermelha da Entrega O1: testes novos contra os esqueletos das units de sala.
rem Resultado em logs\online-o1-red.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o1.ps1" -RedPhase
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da fase vermelha (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
