@echo off
rem Validacao da Entrega 4: Playwright + TypeScript contra a API real.
rem Resultado em logs\step4-validation.log e tests\playwright-report\index.html
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-step4.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da validacao (codigo %RESULT%). Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
