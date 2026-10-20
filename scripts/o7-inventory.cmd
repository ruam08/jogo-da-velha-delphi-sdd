@echo off
rem Entrega O7: inventario somente leitura (Git, arquivos de diagnostico, rede, firewall e SHA-256).
rem Resultado em logs\o7-inventory-autorizado.log e logs\o7-hashes-autorizado.txt
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0o7-inventory.ps1" -Tag autorizado
echo.
echo Fim. Esta janela fecha em 30 segundos.
timeout /t 30 >nul
