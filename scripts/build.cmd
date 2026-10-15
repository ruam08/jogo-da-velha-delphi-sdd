@echo off
rem Compila o servidor e o EngineCheck com o dcc32 do Delphi 10.1 Berlin.
rem Uso: scripts\build.cmd
rem Se o Delphi estiver em outro local, defina DELPHI_RSVARS com o caminho
rem completo do rsvars.bat antes de chamar este script.
setlocal

set "ROOT=%~dp0.."

call "%~dp0delphi-env.cmd"
if errorlevel 1 exit /b 1

echo [build] BDS=%BDS%
echo [build] Compilador:
dcc32 2>&1 | findstr /b /c:"Embarcadero Delphi"

call "%~dp0compile-dpr.cmd" "%ROOT%\server" TicTacToeServer.dpr
if errorlevel 1 goto failed
echo [build] OK: server\bin\TicTacToeServer.exe

call "%~dp0compile-dpr.cmd" "%ROOT%\server" EngineCheck.dpr
if errorlevel 1 goto failed
echo [build] OK: server\bin\EngineCheck.exe
exit /b 0

:failed
echo [build] FALHOU
exit /b 1
