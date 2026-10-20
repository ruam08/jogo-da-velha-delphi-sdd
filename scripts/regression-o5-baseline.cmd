@echo off
rem Regressao de linha de base da Entrega O5 (antes de qualquer mudanca).
rem Roda a validacao completa da O4 sem altera-la e guarda o log como logs\online-o5-baseline.log.
rem O log aprovado da O4 e copiado antes para logs\online-o4-approved.log.
set "ROOT=%~dp0.."
if not exist "%ROOT%\logs\online-o4-approved.log" copy /y "%ROOT%\logs\online-o4.log" "%ROOT%\logs\online-o4-approved.log" >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate-online-o4.ps1"
set "RESULT=%ERRORLEVEL%"
copy /y "%ROOT%\logs\online-o4.log" "%ROOT%\logs\online-o5-baseline.log" >nul
copy /y "%ROOT%\logs\online-o4-approved.log" "%ROOT%\logs\online-o4.log" >nul
echo.
echo Fim (codigo %RESULT%). Log: logs\online-o5-baseline.log. Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
