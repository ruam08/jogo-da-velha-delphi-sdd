@echo off
rem Regressao de linha de base da Entrega O4 (antes de qualquer mudanca).
rem Roda a validacao completa da O3 sem altera-la e guarda o log como logs\online-o4-baseline.log.
rem O log aprovado da O3 e copiado antes para logs\online-o3-approved.log.
set "ROOT=%~dp0.."
if not exist "%ROOT%\logs\online-o3-approved.log" copy /y "%ROOT%\logs\online-o3.log" "%ROOT%\logs\online-o3-approved.log" >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o3.ps1"
set "RESULT=%ERRORLEVEL%"
copy /y "%ROOT%\logs\online-o3.log" "%ROOT%\logs\online-o4-baseline.log" >nul
copy /y "%ROOT%\logs\online-o3-approved.log" "%ROOT%\logs\online-o3.log" >nul
echo.
echo Fim (codigo %RESULT%). Log: logs\online-o4-baseline.log. Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
