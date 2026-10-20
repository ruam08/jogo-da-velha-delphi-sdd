@echo off
rem Complemento da validacao da Entrega O7: matriz CAO e sabotagens do modo local (SB-01 a SB-06).
rem Rode depois de validate-online-o7.cmd. Resultado em logs\online-o7-complemento.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o7-complemento.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
