@echo off
rem Carrega o ambiente do Delphi 10.1 Berlin (rsvars.bat) no processo atual.
rem Sem setlocal de proposito: as variaveis precisam valer para quem chamou.
rem Se o Delphi estiver em outro local, defina DELPHI_RSVARS antes.

if not defined DELPHI_RSVARS set "DELPHI_RSVARS=C:\Program Files (x86)\Embarcadero\Studio\18.0\bin\rsvars.bat"

if exist "%DELPHI_RSVARS%" goto load_env
echo [delphi-env] ERRO: rsvars.bat nao encontrado em "%DELPHI_RSVARS%".
echo [delphi-env] Defina DELPHI_RSVARS com o caminho do rsvars.bat do Delphi Berlin.
exit /b 1

:load_env
call "%DELPHI_RSVARS%"
where dcc32 >nul 2>&1
if not errorlevel 1 exit /b 0
echo [delphi-env] ERRO: dcc32 nao encontrado no PATH depois do rsvars.bat.
echo [delphi-env] A edicao Starter do Delphi nao inclui o compilador de linha de comando.
exit /b 1
