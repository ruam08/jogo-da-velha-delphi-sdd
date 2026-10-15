@echo off
rem Fase vermelha da Entrega 3: roda os testes novos antes da implementacao.
rem Resultado em logs\step3-red.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-step3.ps1" -RedPhase
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da fase vermelha (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
