@echo off
rem Fase vermelha da Entrega 2: compila o EngineCheck contra o esqueleto do
rem motor e confirma que os testes falham. Resultado em logs\step2-red.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-step2.ps1" -RedPhase
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da fase vermelha (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
