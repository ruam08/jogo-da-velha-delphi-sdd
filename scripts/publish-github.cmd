@echo off
setlocal
rem Publica o projeto em https://github.com/ruam08/jogo-da-velha-delphi-sdd
rem usando o Git e as credenciais deste computador.
cd /d "%~dp0.."
set "LOG=logs\publish-github.log"
if not exist logs mkdir logs
set "GIT=git"
where git >nul 2>&1 || set "GIT=C:\Program Files\Git\cmd\git.exe"
(
  echo ===== Publicação %date% %time%
  if not exist .git "%GIT%" init -b main
  "%GIT%" fetch scripts\sdd.bundle main:refs/remotes/bundle/main
  "%GIT%" reset bundle/main
  "%GIT%" remote remove origin 2>nul
  "%GIT%" remote add origin https://github.com/ruam08/jogo-da-velha-delphi-sdd.git
  "%GIT%" status --short
  "%GIT%" log --oneline
) > "%LOG%" 2>&1
echo Enviando para o GitHub (pode abrir uma janela de login)...
"%GIT%" push -u origin main >> "%LOG%" 2>&1
if errorlevel 1 (echo FALHOU >> "%LOG%" & echo Falhou. Veja %LOG%) else (echo PUBLICADO >> "%LOG%" & echo Publicado com sucesso.)
pause
