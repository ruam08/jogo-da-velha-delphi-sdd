@echo off
rem Fase vermelha da Entrega O6: testes novos com os limites em esqueleto e o servidor da O5.
rem Resultado em logs\online-o6-red.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o6.ps1" -RedPhase
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
