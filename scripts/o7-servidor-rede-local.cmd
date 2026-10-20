@echo off
rem Entrega O7: servidor para a validacao manual na rede local (roteiro MV-L).
rem Mostra o endereco para o celular e grava o log em logs\o7-rede-local-*.log. Ctrl+C encerra.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0o7-servidor-rede-local.ps1"
echo.
echo Fim. Pressione uma tecla para fechar.
pause >nul
