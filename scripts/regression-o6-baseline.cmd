@echo off
rem Regressao de linha de base da Entrega O6 (antes de qualquer mudanca).
rem Roda a validacao completa da O5 sem altera-la e guarda o log como logs\online-o6-baseline.log.
rem O log aprovado da O5 e copiado antes para logs\online-o5-approved.log.
set "ROOT=%~dp0.."
if not exist "%ROOT%\logs\online-o5-approved.log" copy /y "%ROOT%\logs\online-o5.log" "%ROOT%\logs\online-o5-approved.log" >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o5.ps1"
set "RESULT=%ERRORLEVEL%"
copy /y "%ROOT%\logs\online-o5.log" "%ROOT%\logs\online-o6-baseline.log" >nul
copy /y "%ROOT%\logs\online-o5-approved.log" "%ROOT%\logs\online-o5.log" >nul
echo.
echo Fim (codigo %RESULT%). Log: logs\online-o6-baseline.log. Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
