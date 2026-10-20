# Demonstração visual do Playwright (fora da validação oficial; O6, registrada a partir da O7).
#  1. SHA-256 de todos os arquivos do projeto antes (scripts\o7-inventory.ps1 -HashesOnly);
#  2. os 11 testes de interface com o Chromium visível e pausa entre as ações
#     (tests\playwright.demo.config.ts), com o resultado de cada teste;
#  3. SHA-256 depois e comparação: a demonstração não pode alterar nenhum arquivo do projeto
#     (código, interface, testes, documentos, capturas de tela de referência).
# Saída: logs\demo-playwright-headed.log e logs\demo-playwright-headed-results.json.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root 'logs'
$TestsDir = Join-Path $Root 'tests'
$Log = Join-Path $LogDir 'demo-playwright-headed.log'
$Json = Join-Path $LogDir 'demo-playwright-headed-results.json'
foreach ($f in @($Log, $Json)) { if (Test-Path $f) { Remove-Item $f -Force } }
function W([string]$Text) { Add-Content -Path $Log -Value $Text -Encoding UTF8; Write-Host $Text }
$Grep = '(^|\s)(U-01|U-02|U-15|U-04-D1|OU-01|OU-03|OU-05|OU-07|OU-14|OU-16|OU-19)\s\['
$Inventory = Join-Path $PSScriptRoot 'o7-inventory.ps1'

W ("===== Demonstração do Playwright com o navegador visível - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$slow = if ($env:DEMO_SLOWMO) { $env:DEMO_SLOWMO } else { '400' }
W "Pausa entre as ações: $slow ms; servidor: server\bin\TicTacToeServer.exe na porta 8765 (iniciado pelo Playwright)."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Inventory -Tag 'demo-antes' -HashesOnly | Out-Null
W "SHA-256 antes: logs\o7-hashes-demo-antes.txt"

$env:PLAYWRIGHT_JSON_OUTPUT_NAME = $Json
$env:FORCE_COLOR = '0'
$start = Get-Date
Push-Location $TestsDir
try {
    $out = & cmd.exe /c "npx --no-install playwright test -c playwright.demo.config.ts --reporter=list,json --grep `"$Grep`" 2>&1" | ForEach-Object { Write-Host $_; $_ }
    $code = $LASTEXITCODE
} finally { Pop-Location }
$secs = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
W "`n----- Saída do Playwright"
foreach ($l in $out) { W ([string]$l) }
W ("Código de saída: {0}; duração {1} s" -f $code, $secs)

W "`n----- Resultado por teste"
$passed = 0; $failed = 0
if (Test-Path $Json) {
    $data = Get-Content $Json -Raw -Encoding UTF8 | ConvertFrom-Json
    $walk = {
        param($suite, $file)
        foreach ($spec in @($suite.specs)) {
            foreach ($t in @($spec.tests)) {
                foreach ($r in @($t.results)) {
                    if ($r.status -eq 'passed') { $script:passed++ } else { $script:failed++ }
                    W ("  {0,-8} [{1}] {2} ({3:N1} s)" -f $r.status, $t.projectName, $spec.title, ($r.duration / 1000))
                }
            }
        }
        foreach ($s in @($suite.suites)) { if ($s) { & $walk $s $file } }
    }
    foreach ($s in @($data.suites)) { & $walk $s $s.file }
} else { W '  (arquivo de resultados não gerado)' }
W ("Testes: {0} aprovados, {1} com falha (esperado: 11 aprovados)" -f $passed, $failed)

W "`n----- Arquivos do projeto depois da demonstração"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Inventory -Tag 'demo-depois' -CompareWith 'demo-antes' -HashesOnly | Out-Null
$cmp = Get-Content (Join-Path $LogDir 'o7-inventory-demo-depois.log') -Encoding UTF8 | Where-Object { $_ -match '^(Comparação|  alterado|  novo|  removido|RESULTADO DA COMPARAÇÃO)' }
foreach ($l in $cmp) { W $l }
$untouched = [bool]($cmp | Where-Object { $_ -match 'NENHUM ARQUIVO MUDOU' })
W ("`nRESULTADO: {0}" -f $(if (($code -eq 0) -and ($passed -eq 11) -and ($failed -eq 0) -and $untouched) { 'APROVADO (11 de 11; nenhum arquivo do projeto alterado)' } else { 'REPROVADO' }))
exit $code
