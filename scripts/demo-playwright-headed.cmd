@echo off
rem Demonstracao visual do Playwright (fora da validacao oficial).
rem Abre o Chromium na tela e roda, devagar, 11 testes de interface sem medicao de tempo:
rem partida local, vitoria, duas abas; sala online entre dois navegadores, reconexao, nova partida e saida.
rem Desde a O7, registra o resultado de cada teste e confere (SHA-256) que nenhum arquivo do projeto mudou:
rem logs\demo-playwright-headed.log
rem Requer server\bin\TicTacToeServer.exe compilado e a porta 8765 livre.
echo Demonstracao do Playwright com o navegador visivel. Nao mexa nas janelas do Chromium enquanto roda.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0demo-playwright-headed.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
echo Fim da demonstracao (codigo %RESULT%). Resultado em logs\demo-playwright-headed.log. Esta janela fecha em 60 segundos.
timeout /t 60 >nul
exit /b %RESULT%
