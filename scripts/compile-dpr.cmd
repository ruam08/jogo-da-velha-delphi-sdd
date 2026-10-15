@echo off
rem Compila um programa Delphi com o dcc32 e as opcoes padrao do projeto.
rem Uso: compile-dpr.cmd <pasta-do-projeto> <arquivo.dpr>
rem A pasta precisa conter o .dpr e as subpastas src (e tests, se usada).
rem Saida: <pasta>\bin\*.exe  e  <pasta>\dcu\*.dcu
setlocal

set "PROJ_DIR=%~1"
set "DPR=%~2"
if "%PROJ_DIR%"=="" goto usage
if "%DPR%"=="" goto usage

call "%~dp0delphi-env.cmd"
if errorlevel 1 exit /b 1

if not exist "%PROJ_DIR%\bin" mkdir "%PROJ_DIR%\bin"
if not exist "%PROJ_DIR%\dcu" mkdir "%PROJ_DIR%\dcu"

pushd "%PROJ_DIR%"
echo [compile] %DPR% em %CD%
dcc32 -B -Q -CC -NS"System;Winapi;System.Win" -E"bin" -NU"dcu" -U"src;tests;%BDS%\lib\win32\release" -R"%BDS%\lib\win32\release" "%DPR%"
set "BUILD_ERROR=%ERRORLEVEL%"
popd
exit /b %BUILD_ERROR%

:usage
echo Uso: compile-dpr.cmd ^<pasta-do-projeto^> ^<arquivo.dpr^>
exit /b 2
