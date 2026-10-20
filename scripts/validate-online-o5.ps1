# Validação da Entrega O5 (ciclo de vida das salas: faxineiro, abandono, lembrança, desligamento).
#  1. ambiente; 2. arquivos preservados: git, SHA-256 das entregas O1 a O4 e, em uHttpApp.pas e
#     nos dois .dpr, só as mudanças da O5 (desfeitas, o arquivo volta a ser o aprovado);
#  3. compilação; 4. independência das units sem Indy (inclui uRoomJanitor);
#  5. EngineCheck (59 casos: os 57 anteriores + JN-01 e JN-02), três vezes;
#  6. checagem de tipos dos testes Playwright;
#  7. suíte completa com o servidor do Playwright (bind padrão);
#  8. suíte completa com o servidor do script (--bind 127.0.0.1) e o log dele verificado;
#  9. repetição: online-ui duas vezes; testes de ciclo de vida da O5 três vezes;
# 10. Ctrl+C com 10 canais (D-01, D-02, regressão) e Ctrl+C com o faxineiro trabalhando
#     (D-03: prazo de 1 s, varredura a cada 20 ms, salas sendo encerradas);
# 11. sabotagens: SB-09 e SB-16 (online.js), SB-11 (hub), SB-13 (faxineiro não varre) e
#     SB-17 (encerra sala com alguém conectado) contra o servidor real;
# 12. nenhum processo órfão (servidor, EngineCheck, cliente ws-hold) e portas de teste livres.
# Com -RedPhase: só 1 a 7, com o faxineiro em esqueleto (não varre) e uHttpApp.pas da O4.
# Saída em logs\online-o5.log (ou logs\online-o5-red.log). Windows PowerShell 5.1.
param([switch]$RedPhase)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root      = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$LogFile   = Join-Path $LogDir $(if ($RedPhase) { 'online-o5-red.log' } else { 'online-o5.log' })
$ServerDir = Join-Path $Root 'server'
$TestsDir  = Join-Path $Root 'tests'
$WebDir    = Join-Path $Root 'web'
$EngineExe = Join-Path $ServerDir 'bin\EngineCheck.exe'
$ServerExe = Join-Path $ServerDir 'bin\TicTacToeServer.exe'
$Compile   = Join-Path $Root 'scripts\compile-dpr.cmd'
$CtrlC     = Join-Path $Root 'scripts\send-ctrl-c.ps1'
$ResultsFile = Join-Path $TestsDir 'test-results\results.json'

$OldCases = @('M-01','M-02','M-03','M-04','M-05-L1','M-05-L2','M-05-L3','M-05-C1','M-05-C2',
    'M-05-C3','M-05-D1','M-05-D2','M-06','M-07','M-08','M-09','M-10','M-11','M-12',
    'J-01','J-02','J-03','J-04','J-05','SV-01','SV-02','SV-03',
    'SL-01','SL-02','SL-03','SL-04','SL-05','SL-06','SL-07','SL-08','SL-09','SL-10',
    'SL-11','SL-12','MEM-01','SC-01','SC-02','RJ-01','RJ-02','RJ-03','OP-01',
    'OP-02','WS-01','WS-02','WS-03','WS-04','WS-05','WS-06','WS-07','HB-01','HB-02','HB-03')
$NewCases = @('JN-01','JN-02')
$AllCases = $OldCases + $NewCases
$Expected = [ordered]@{ api = 80; chromium = 29; 'online-api' = 31; 'online-ws' = 18; 'online-lifecycle' = 12; 'online-ui' = 25 }
$ExpectedTotal = 195
# Testes Playwright novos da O5 (tests/online/lifecycle/rooms.spec.ts).
$NewTests = 'OV-01|OV-02|OV-03|OV-11|OV-12|OU-28'

# Sob controle do git (último commit): motor, serviço, log, testes antigos e a interface local.
$Preserved = @('server/src/uGameEngine.pas','server/src/uGameService.pas','server/src/uConsoleLog.pas',
    'server/tests/uMiniTest.pas','server/tests/uEngineTests.pas','server/tests/uServiceTests.pas',
    'server/tests/uJsonTests.pas','web/app.js','web/style.css','tests/api','tests/rules','tests/ui','tests/support/api.ts',
    'tests/support/fixtures.ts','tests/support/raw-http.ts','tests/support/sequences.ts','tests/support/ui.ts',
    'tests/package.json','tests/package-lock.json','tests/tsconfig.json','docs/test-plan.md')
# Arquivos das entregas O1 a O4 que a O5 não altera: SHA-256 aprovados.
$Hashes = [ordered]@{
    'server/src/uClock.pas'                   = '87142FE997345C909B797F2940080A19EDC87A046A83721AD84163D7903F11D5'
    'server/src/uSecureRandom.pas'            = '0323BFDB1586E8FC697DF84AE15422444BEED4BCD72610D0894BB341A11F1F33'
    'server/src/uRoom.pas'                    = '77CABC56139576236E47A9ECA8C7C2519039D90681DB066F7E217C8B2385283A'
    'server/src/uRoomRegistry.pas'            = '803F17485EFCFAF48429E88CB9E229B2A81828C64136E0DA1BA06FD7A3C6AE54'
    'server/src/uRoomJson.pas'                = '6B13B1A128A4020BA909DE301A33D72C3A7632F3FD6BB78228E58AB64FD6D8E0'
    'server/src/uGameJson.pas'                = '5E5F66BA863ED98189EB1E9A9353906D20AD130F283D31E63F5A44B636CE1AD5'
    'server/tests/uRoomTests.pas'             = '48283B3C71D2DC7609E8C7DF2F896615AA320948F97F0547255AAFB2E372CE38'
    'server/tests/uRoomConcurrencyTests.pas'  = 'C3FCC88689F8A46025771B4B2AD00128A77B2717D16927261FB40FBC421662CD'
    'server/tests/uRoomJsonTests.pas'         = '824DC1751170E304F4ACAB0B4F500A84DF5F3827E8C613009F648F8972C02822'
    'tests/online/room-api/contract.spec.ts'  = '14D49275266D677AEC65C1083D86B706CE48D9350F3247A44AFD160E5037B74F'
    'tests/online/room-api/errors.spec.ts'    = 'C155D577751EBE8C25FECD578E465FE5A1222F55DDEB4773675DF2544D437B65'
    'tests/online/room-api/routes.spec.ts'    = 'BC7F23A7BF8D6F687E3955DF8C31DDB4FC573F34A6BF9464B38E8B17430E323C'
    'tests/online/room-rules/concurrency.spec.ts' = 'A74188A5CC57E91D78DE18CE30CFE2B7E0E3AF18EB2720C6D529E2C2F4047057'
    'tests/online/room-rules/games.spec.ts'   = '3235385F25760CCE528DB1B4CC2F62E5C02FE81DD1BD46441363601FE82A14FC'
    'tests/online/room-rules/moves.spec.ts'   = '83246670BD6CA2E6154D4D0D834728BBCEB2BE310ED0E5EA13B7975333E981AD'
    'docs/spec.md'                            = 'D47723E3C479BFACC4F90349DD0ED39417B4EE7EBC5460FC7DE1B1060E1C3C02'
    'docs/plan.md'                            = 'EF473161A5B52CAE689AC03713D29E97F73EB23A4B35B624C3FC3F8AD426E069'
    'server/src/uWebSocket.pas'               = 'CC27AA638BBB639D97A0AA83EEEDD85DFF2BB668D8045BFF3628D35EDDB3E189'
    'server/src/uOriginPolicy.pas'            = '77AA746ECE101DA3BE466023A18A7FC4414C669103AFBCFF1DC3BA9CE36403A2'
    'server/src/uRoomHub.pas'                 = 'B7C5878C9EB42761A3F387493A14079228223580C49C9D80B8D540DD2EAFFBD5'
    'server/src/uWsSession.pas'               = '599DB613A085BA07AC9307E84FD86EFD9C7F96C0D21EFA6446E9FFAB91F3A10A'
    'server/src/uRoomHttp.pas'                = 'C5C7A3A8C03054B5327AE3014B25322E72C5387E7EF5F483F6EDD72E1311BA4D'
    'server/src/uServerOptions.pas'           = 'B52C50E20BDF558559757BE1321BE8DC040F6BB97755866CFBB8E95F8D374ECC'
    'server/tests/uWebSocketTests.pas'        = 'D69AE30C530590DB52FB5B8DBD6796A812F03A7C1AF409E8223D26C4D568B5AC'
    'server/tests/uRoomHubTests.pas'          = 'A4014773C0BBF9A480B2C1DD0E6156645C47CE0886F4D48DFF5DEB8161C833F8'
    'server/tests/uOptionsTests.pas'          = 'DBA36BA8EC60344C5414B0009BB4AF3EF16A9D1017580E649C34F747D1190280'
    'tests/online/room-ws/channel.spec.ts'    = '747CF64A73817ECF1C7C241FF0095B0EE9B7E837947F1B54B9105B2D01773AB4'
    'tests/online/room-ws/sync.spec.ts'       = '295F79F1F92DDDEDDD3B0485ED7063742CBEB0BA3ED7A735F84AB100F4B74F2D'
    'tests/online/room-ws/timeouts.spec.ts'   = '923C288DB7FBE1DC77ADCF057901620823244667C3ABFB4187C10404AEAC0D27'
    'tests/online/lifecycle/load.spec.ts'     = 'F2DF458D841A3A5AD0332A1DA8E9B14BC425639628433DF5B764DA6DDF5F2EF3'
    'tests/online/lifecycle/origin.spec.ts'   = 'F6F93B2FFC8DB158F07EB96052B1735C85EF186EC56694DE7C48877119873C75'
    'tests/online/room-api/origin.spec.ts'    = 'C9EC574A755BBDC537019820561E85E1B77D464CD4B8E9999ECCA6F0629B24A7'
    'tests/online/room-api/legacy-auth.spec.ts' = 'CF9C07DC8BB9C7D529980DD3111A76D13D17C11E5EA4BC5C532CE17A8A8E1B71'
    'tests/support/online/fixtures.ts'        = 'E2493F7B9509CC0BCD686AD435EF66F69B10DD8A786351F87C361259BE024301'
    'tests/support/online/rooms.ts'           = 'DCE560484C95E5D7FF0E52DF8A8F5580A6AB6D7CC849DE763CE58F9C1E8DD678'
    'tests/support/online/server-process.ts'  = 'E496220BC9E4770610ECC7CF207C8BD398177E27544D09F1819A8C04DBDE4989'
    'tests/support/online/ws-client.ts'       = '422A440391E94E66961A04AE7FB7FDB872AB3B09F37B9BE2ACB2B9270361161F'
    'tests/support/online/raw-request.ts'     = '4D9CF31EC7CEACE58590A41002179912076B87E1BC538882E3C925080BC58483'
    'tests/tools/ws-hold.mjs'                 = '7CEC0BA9A5FEF200FE1930966B8DA0473230796DD50457C14AF14405D61C821A'
    'scripts/validate-online-o3.ps1'          = '5112C63B3BD2ED343AA6C1BEEA9E566477868C7CE80EF241A62B8F9BB5DFE3A6'
    'scripts/send-ctrl-c.ps1'                 = '3AE8AEF39DED0F410D43E620A110AE277AEABB8B57F600808DE84757536240DD'
    'web/online.html'                            = '20DEE08122BC6B7E016304227A10962B39F71296AFA92903FEEC0850898F4BA1'
    'web/online.css'                             = 'FF1E853F8BD9261F3F28ADBE83E9D31EB8DDB04534ACE17788F47B3DECE93BC8'
    'web/online.js'                              = '9538D675A9281270865C55BFBE248D8297A4A6C3C42018CD65EFA22A0BA5E680'
    'web/index.html'                             = '0DA583FA30F3109FAD474DCCAAABAE34120B8A7F5860937BAC11E899A4B069F4'
    'tests/support/online/online-ui.ts'          = '11B78086E85FE453DC0B396766598A9622B6F9379618E51F50DE25F8B5BA090B'
    'tests/support/online/ui-fixtures.ts'        = 'DF8D3932CE544E0ED48EA6A06F405DBCA3F23BFAB8241F255D4B4DBDDCA49915'
    'tests/online/room-ui/create-join.spec.ts'   = '7F17C4EACC9E9B2586B1FB0190E22D7BD35BC5A8B59AE4EBB8B1B0966393EA6C'
    'tests/online/room-ui/play.spec.ts'          = 'FAF30CFEBE2E843FC4D4E312D8101064D12D7D591DA43E4C4EF75E3519359AA3'
    'tests/online/room-ui/connection.spec.ts'    = '6AF57E97F98B60F5CA42DC8D1DEEA51E6AE1FD4047D79BDAC8F80A94A8D850F4'
    'tests/online/room-ui/layout.spec.ts'        = 'BC17D0B13592B859EF8F6635CA632A288D98014BAD132C26914BC977DDC7777E'
    'tests/online/lifecycle/ui.spec.ts'          = 'A793521A7CD726BB72DA545983B3887EC8DE85FA04C25590100CF2D18EC7A6D8'
    'tests/online/room-api/static.spec.ts'       = 'E5EAAB6F86789E8B7EFC6D23F44E53D08CD1C01C65BAF39129EC2139FC325EC0'
    'tests/playwright.config.ts'                 = 'C2FEEE583F8683ACBCA0B75F05F41081BF3DD734DA7A6668769EDF5D094A1DAE'
    'tests/tools/capture-online.cjs'             = '932308A9B8EFA7646F0BA7712A73317FECD8470F02D4ECD2FE0150D1311E547F'
    'scripts/validate-online-o4.ps1'             = '91E145B91A55CAE0A185142DF96142B0DB0EF3DEB69AAE60F571E407A87A03E2'
}
# Arquivos que a O5 altera. Cada par é (trecho da O5, trecho aprovado), em UTF-8 base64:
# desfeitas as mudanças da O5, o arquivo tem de voltar a ser exatamente o aprovado
# (uHttpApp.pas da O4; os .dpr da O3). Na fase vermelha, uHttpApp.pas ainda é o da O4.
$Reverts = [ordered]@{
    'server/src/uHttpApp.pas' = @{ Approved = '0574C5FEA0721D8AC17A2A6236F5A5D2D2C5451C56A4AD3C11D7F6D9350DA49B'; Hunks = @(
        @('ICAgIG9yaWdlbSBlbSB1T3JpZ2luUG9saWN5LCBzZXNzw6NvIGVtIHVXc1Nlc3Npb24sIG5vdGlmaWNhw6fDtWVzIGVtIHVSb29tSHViLg0KDQogIC0gY2ljbG8gZGUgdmlkYSAoTzUpOiBvIGZheGluZWlybyAodVJvb21KYW5pdG9yKSBlbmNlcnJhIGFzIHNhbGFzDQogICAgYWJhbmRvbmFkYXMgZSBlc3F1ZWNlIGFzIGxlbWJyYWRhczsgY29tZcOnYSBlbSBTdGFydCBlIHBhcmEgZW0gU3RvcC4NCg==', 'ICAgIG9yaWdlbSBlbSB1T3JpZ2luUG9saWN5LCBzZXNzw6NvIGVtIHVXc1Nlc3Npb24sIG5vdGlmaWNhw6fDtWVzIGVtIHVSb29tSHViLg0K'),
        @('ICBJZENvbnRleHQsIElkQ3VzdG9tSFRUUFNlcnZlciwgSWRIVFRQU2VydmVyLA0KICB1R2FtZVNlcnZpY2UsIHVTZXJ2ZXJPcHRpb25zLCB1Um9vbSwgdVJvb21SZWdpc3RyeSwgdVJvb21IdWIsIHVPcmlnaW5Qb2xpY3ksIHVSb29tSmFuaXRvcjsNCg==', 'ICBJZENvbnRleHQsIElkQ3VzdG9tSFRUUFNlcnZlciwgSWRIVFRQU2VydmVyLA0KICB1R2FtZVNlcnZpY2UsIHVTZXJ2ZXJPcHRpb25zLCB1Um9vbVJlZ2lzdHJ5LCB1Um9vbUh1YiwgdU9yaWdpblBvbGljeTsNCg=='),
        @('ICAgIEZIdWI6IFRSb29tSHViOw0KICAgIEZKYW5pdG9yOiBUUm9vbUphbml0b3I7DQo=', 'ICAgIEZIdWI6IFRSb29tSHViOw0K'),
        @('ICAgIEZXZWJSb290OiBzdHJpbmc7DQogICAgeyBTYWxhcyBlbmNlcnJhZGFzIHBvciBhYmFuZG9ubyBwZWxvIGZheGluZWlybyAodGhyZWFkIGRvIGZheGluZWlybykuIH0NCiAgICBwcm9jZWR1cmUgUm9vbXNBYmFuZG9uZWQoY29uc3QgQUNsb3NlZDogVEFycmF5PFRSb29tU25hcHNob3Q+KTsNCg==', 'ICAgIEZXZWJSb290OiBzdHJpbmc7DQo='),
        @('ICAgIHByb2NlZHVyZSBTdGFydDsNCiAgICB7IFNlw6fDo28gMTEuMzogYXZpc2Egb3MgY2FuYWlzIChmZWNoYW1lbnRvIDEwMDEpLCBlc3BlcmEgYXTDqSAxLDUgcyBwb3IgZWxlcywNCiAgICAgIHBhcmEgbyBJbmR5IGUgZGVwb2lzIG8gZmF4aW5laXJvLiB9DQo=', 'ICAgIHByb2NlZHVyZSBTdGFydDsNCiAgICB7IEF2aXNhIG9zIGNhbmFpcyAoZmVjaGFtZW50byAxMDAxKSwgZXNwZXJhIGF0w6kgMSw1IHMgcG9yIGVsZXMgZSBwYXJhIG8gSW5keS4gfQ0K'),
        @('ICBGSHViIDo9IFRSb29tSHViLkNyZWF0ZTsNCiAgeyBGYXhpbmVpcm8gKHNlw6fDo28gMTEuMiwgTzUpOiBjb21lw6dhIGVtIFN0YXJ0IGUgcGFyYSBlbSBTdG9wLiB9DQogIEZKYW5pdG9yIDo9IFRSb29tSmFuaXRvci5DcmVhdGUoRlJlZ2lzdHJ5LCBJbnQ2NChBT3B0aW9ucy5Sb29tVHRsU2Vjb25kcykgKiAxMDAwLA0KICAgIENhcmRpbmFsKEFPcHRpb25zLlN3ZWVwTXMpLCBSb29tc0FiYW5kb25lZCwNCiAgICBwcm9jZWR1cmUoY29uc3QgQU1lc3NhZ2U6IHN0cmluZykNCiAgICBiZWdpbg0KICAgICAgTG9nKCdFUlJPIG5vIGZheGluZWlybzogJXMnLCBbQU1lc3NhZ2VdKTsNCiAgICBlbmQpOw0K', 'ICBGSHViIDo9IFRSb29tSHViLkNyZWF0ZTsNCg=='),
        @('ICBGU2VydmVyLkZyZWU7DQogIHsgTyBmYXhpbmVpcm8gasOhIHBhcm91IGVtIFN0b3A7IMOpIGxpYmVyYWRvIGFudGVzIGRvIGh1YiBlIGRvIHJlZ2lzdHJvIHF1ZSB1c2EuIH0NCiAgRkphbml0b3IuRnJlZTsNCg==', 'ICBGU2VydmVyLkZyZWU7DQo='),
        @('ICBGU2VydmVyLkFjdGl2ZSA6PSBUcnVlOw0KICBGSmFuaXRvci5TdGFydDsNCmVuZDsNCg0KcHJvY2VkdXJlIFRHYW1lSHR0cFNlcnZlci5Sb29tc0FiYW5kb25lZChjb25zdCBBQ2xvc2VkOiBUQXJyYXk8VFJvb21TbmFwc2hvdD4pOw0KdmFyDQogIENsb3NlZDogVFJvb21TbmFwc2hvdDsNCmJlZ2luDQogIHsgTm9ybWFsbWVudGUgbmluZ3XDqW0gZXN0w6EgaW5zY3JpdG8gKGEgc2FsYSBzw7Mgw6kgZW5jZXJyYWRhIHNlbSBjb25leMO1ZXMpOw0KICAgIGEgcHVibGljYcOnw6NvIGNvYnJlIG8gY2FzbyBkZSB1bWEgaW5zY3Jpw6fDo28gYWluZGEgbsOjbyByZW1vdmlkYS4gfQ0KICBmb3IgQ2xvc2VkIGluIEFDbG9zZWQgZG8NCiAgYmVnaW4NCiAgICBMb2coJ1NhbGEgJXMgZW5jZXJyYWRhIHBvciBhYmFuZG9ubycsIFtDbG9zZWQuQ29kZV0pOw0KICAgIEZIdWIuUHVibGlzaFRlcm1pbmFsKENsb3NlZC5Db2RlLCBSb29tQ2xvc2VkRXZlbnRKc29uKENsb3NlZCksIDQ0MTApOw0KICBlbmQ7DQo=', 'ICBGU2VydmVyLkFjdGl2ZSA6PSBUcnVlOw0K'),
        @('ICBlbmQ7DQogIHsgRGVwb2lzIGRvIEluZHk6IG5lbmh1bWEgcmVxdWlzacOnw6NvIG91IGNhbmFsIHVzYSBtYWlzIGFzIHNhbGFzLiBFc3BlcmEgYQ0KICAgIHZhcnJlZHVyYSBlbSBhbmRhbWVudG8gdGVybWluYXI7IGRlcG9pcyBkaXNzbyBuYWRhIG1haXMgcHVibGljYSBubyBodWIuIH0NCiAgRkphbml0b3IuU3RvcDsNCg==', 'ICBlbmQ7DQo=')
    ) }
    'server/TicTacToeServer.dpr' = @{ Approved = '87721360CB37093C401FC181971F07F9873812F66E9A67FCBF935F2B4A1A83E3'; Hunks = @(
        @('ICB1V3NTZXNzaW9uIGluICdzcmNcdVdzU2Vzc2lvbi5wYXMnLA0KICB1Um9vbUphbml0b3IgaW4gJ3NyY1x1Um9vbUphbml0b3IucGFzJywNCg==', 'ICB1V3NTZXNzaW9uIGluICdzcmNcdVdzU2Vzc2lvbi5wYXMnLA0K'),
        @('ICAgICAgICAgIFtQb3J0LCBPcHRpb25zLldzSGVsbG9TZWNvbmRzLCBPcHRpb25zLldzSWRsZVNlY29uZHNdKTsNCiAgICAgICAgTG9nKCdTYWxhczogZW5jZXJyYWRhcyBwb3IgYWJhbmRvbm8gYXDDs3MgJWQgcyBzZW0gbmluZ3XDqW0gY29uZWN0YWRvICh2YXJyZWR1cmEgYSBjYWRhICVkIG1zKTsgJyArDQogICAgICAgICAgJ2xlbWJyYWRhcyBwb3IgJWQgcyBkZXBvaXMgZGUgZW5jZXJyYWRhcycsDQogICAgICAgICAgW09wdGlvbnMuUm9vbVR0bFNlY29uZHMsIE9wdGlvbnMuU3dlZXBNcywgT3B0aW9ucy5SZW1lbWJlclNlY29uZHNdKTsNCg==', 'ICAgICAgICAgIFtQb3J0LCBPcHRpb25zLldzSGVsbG9TZWNvbmRzLCBPcHRpb25zLldzSWRsZVNlY29uZHNdKTsNCg==')
    ) }
    'server/EngineCheck.dpr' = @{ Approved = 'D6F0D3B2848E4CD9D28929B4D4F96D18C7D8D278CA8D513A627759C716064F16'; Hunks = @(
        @('ICAtIEhCOiBodWIgZSBjYWl4YXMgZGUgc2HDrWRhICh1Um9vbUh1YikNCiAgLSBKTjogZmF4aW5laXJvIGRhcyBzYWxhcyAodVJvb21KYW5pdG9yKQ0K', 'ICAtIEhCOiBodWIgZSBjYWl4YXMgZGUgc2HDrWRhICh1Um9vbUh1YikNCg=='),
        @('ICB1U2VydmVyT3B0aW9ucyBpbiAnc3JjXHVTZXJ2ZXJPcHRpb25zLnBhcycsDQogIHVSb29tSmFuaXRvciBpbiAnc3JjXHVSb29tSmFuaXRvci5wYXMnLA0K', 'ICB1U2VydmVyT3B0aW9ucyBpbiAnc3JjXHVTZXJ2ZXJPcHRpb25zLnBhcycsDQo='),
        @('ICB1V2ViU29ja2V0VGVzdHMgaW4gJ3Rlc3RzXHVXZWJTb2NrZXRUZXN0cy5wYXMnLA0KICB1Um9vbUh1YlRlc3RzIGluICd0ZXN0c1x1Um9vbUh1YlRlc3RzLnBhcycsDQogIHVSb29tSmFuaXRvclRlc3RzIGluICd0ZXN0c1x1Um9vbUphbml0b3JUZXN0cy5wYXMnOw0K', 'ICB1V2ViU29ja2V0VGVzdHMgaW4gJ3Rlc3RzXHVXZWJTb2NrZXRUZXN0cy5wYXMnLA0KICB1Um9vbUh1YlRlc3RzIGluICd0ZXN0c1x1Um9vbUh1YlRlc3RzLnBhcyc7DQo='),
        @('ICAgIFJ1blJvb21IdWJUZXN0czsNCiAgICBSdW5Sb29tSmFuaXRvclRlc3RzOw0K', 'ICAgIFJ1blJvb21IdWJUZXN0czsNCg==')
    ) }
}
$NewPascal = @('server/src/uRoomJanitor.pas', 'server/tests/uRoomJanitorTests.pas', 'server/src/uHttpApp.pas',
    'server/TicTacToeServer.dpr', 'server/EngineCheck.dpr')
$TestPorts = @(8765, 8766, 8770, 8771, 8772, 8773, 8774, 8775, 8776, 8777, 8778, 8779, 8783, 8784,
    8785, 8786, 8787, 8788, 8789, 8790, 8791, 8792)

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Content -Path $LogFile -Value '' -Encoding UTF8
$Results = New-Object System.Collections.ArrayList
$Servers = New-Object System.Collections.ArrayList

function Write-Log([string]$Text) {
    Add-Content -Path $LogFile -Value $Text -Encoding UTF8
    Write-Host $Text
}

function Add-Check([string]$Id, [string]$Description, [bool]$Ok, [string]$Detail) {
    $status = if ($Ok) { 'PASSOU' } else { 'FALHOU' }
    [void]$Results.Add([pscustomobject]@{ Id = $Id; Status = $status; Description = $Description })
    Write-Log ("[{0}] {1} - {2}" -f $status, $Id, $Description)
    if ($Detail) { Write-Log ("         " + $Detail) }
}

# Comando de compilação com limite de tempo: se o dcc32 travar (como na primeira fase
# vermelha da O5), ele é encerrado e o passo falha, em vez de a validação parar para sempre.
function Invoke-CmdWithTimeout([string]$CommandLine, [string]$OutFile, [int]$Seconds) {
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"$CommandLine > `"$OutFile`" 2>&1`"" -WindowStyle Hidden -PassThru
    $done = $p.WaitForExit($Seconds * 1000)
    if (-not $done) {
        foreach ($c in @(Get-CimInstance Win32_Process -Filter "Name = 'dcc32.exe'")) { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue }
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
    }
    $out = if (Test-Path $OutFile) { Get-Content $OutFile -Raw -Encoding Default } else { '' }
    if (-not $done) { $out += "`r`nTEMPO ESGOTADO: o compilador não terminou em $Seconds s e foi encerrado." }
    [pscustomobject]@{ Code = $(if ($done) { $p.ExitCode } else { 124 }); Output = $out; TimedOut = (-not $done) }
}

function Invoke-Compile([string]$Dir, [string]$Dpr) {
    Invoke-CmdWithTimeout "`"$Compile`" `"$Dir`" $Dpr" (Join-Path $Dir "compile-$Dpr.log") 180
}

function Invoke-Engine([string]$Exe) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $out = & $Exe 2>&1 | Out-String
    $code = $LASTEXITCODE
    $sw.Stop()
    [pscustomobject]@{ Code = $code; Output = $out; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
}

function Get-CaseIds([string]$Output, [string]$Tag) {
    $ids = @()
    foreach ($m in [regex]::Matches($Output, "(?m)^\[$Tag\]\s+(\S+)")) { $ids += $m.Groups[1].Value }
    return ,$ids
}

function Invoke-InTests([string]$CommandLine) {
    Write-Log "> cd tests && $CommandLine"
    Push-Location $TestsDir
    try {
        $out = & cmd.exe /c "$CommandLine 2>&1" | Out-String
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    [pscustomobject]@{ Code = $code; Output = $out }
}

function Invoke-Playwright([string]$CommandLine, [hashtable]$Env = @{}) {
    if (Test-Path $ResultsFile) { Remove-Item $ResultsFile -Force }
    foreach ($k in $Env.Keys) { Set-Item -Path "Env:$k" -Value $Env[$k] }
    try { return Invoke-InTests $CommandLine }
    finally { foreach ($k in $Env.Keys) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue } }
}

function Read-Results {
    if (-not (Test-Path $ResultsFile)) { return $null }
    $json = Get-Content $ResultsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $byProject = @{}
    $failedTitles = New-Object System.Collections.ArrayList
    $walk = $null
    $walk = {
        param($suite)
        foreach ($spec in @($suite.specs)) {
            foreach ($t in @($spec.tests)) {
                $p = $t.projectName
                if (-not $byProject.ContainsKey($p)) { $byProject[$p] = @{ ok = 0; fail = 0 } }
                $ok = $true
                foreach ($r in @($t.results)) { if ($r.status -ne 'passed') { $ok = $false } }
                if ($t.status -eq 'expected' -and $ok) { $byProject[$p].ok++ } else { $byProject[$p].fail++; [void]$failedTitles.Add("[$p] $($spec.title)") }
            }
        }
        foreach ($child in @($suite.suites)) { if ($child) { & $walk $child } }
    }
    foreach ($s in @($json.suites)) { & $walk $s }
    [pscustomobject]@{ Stats = $json.stats; ByProject = $byProject; Failed = $failedTitles }
}

function Format-Results($r) {
    if (-not $r) { return 'results.json não foi gerado' }
    $parts = @()
    foreach ($k in ($r.ByProject.Keys | Sort-Object)) { $parts += ("{0}: {1} ok, {2} falha(s)" -f $k, $r.ByProject[$k].ok, $r.ByProject[$k].fail) }
    ("aprovados {0}; falharam {1}; instáveis {2}; pulados {3}; {4}; duração {5} s" -f $r.Stats.expected, $r.Stats.unexpected, $r.Stats.flaky, $r.Stats.skipped, ($parts -join '; '), [math]::Round($r.Stats.duration / 1000, 1))
}

function Test-FullSuite($r) {
    if ($null -eq $r) { return $false }
    if (($r.Stats.expected -ne $ExpectedTotal) -or ($r.Stats.unexpected -ne 0) -or ($r.Stats.flaky -ne 0) -or ($r.Stats.skipped -ne 0)) { return $false }
    foreach ($k in $Expected.Keys) { if (-not $r.ByProject[$k] -or $r.ByProject[$k].ok -ne $Expected[$k]) { return $false } }
    return $true
}

function Write-PlaywrightSummary($run) {
    $clean = $run.Output -replace '\x1b\[[0-9;]*m', ''
    Write-Log ((($clean -split "`r?`n") | Where-Object { $_ -match '^\s+\d+ (passed|failed|flaky|skipped|did not run)' }) -join "`r`n")
}

function Write-FailureExcerpt($run, [int]$Max = 30) {
    $clean = $run.Output -replace '\x1b\[[0-9;]*m', ''
    $why = @(($clean -split "`r?`n") | Where-Object { $_ -match '^\s+(Error:|Expected|Received|\+|-)\s' -or $_ -match '^\s+\d+\) \[' } | Select-Object -First $Max)
    foreach ($w in $why) { Write-Log ("    " + $w.TrimEnd()) }
}

function Start-Server([string]$Exe, [int]$Port, [string[]]$Extra, [string]$Name, [string]$Www = $WebDir) {
    $busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($busy) { throw "A porta $Port já está em uso (processo $($busy[0].OwningProcess))." }
    $procArgs = @('--port', "$Port", '--www', "`"$Www`"") + $Extra
    $p = Start-Process -FilePath $Exe -ArgumentList $procArgs -RedirectStandardOutput (Join-Path $LogDir "$Name.out.log") -RedirectStandardError (Join-Path $LogDir "$Name.err.log") -PassThru -WindowStyle Hidden
    [void]$Servers.Add($p)
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
        if ("$code".Trim() -eq '200') { return $p }
        if ($p.HasExited) { throw "Servidor $Name terminou com código $($p.ExitCode)." }
        Start-Sleep -Milliseconds 250
    }
    throw "Servidor $Name não respondeu em 10 s."
}

function Stop-Server($Proc) {
    if ($Proc -and -not $Proc.HasExited) { Stop-Process -Id $Proc.Id -Force; $Proc.WaitForExit(5000) | Out-Null }
}

function Test-ServerLog([string]$Path, [string]$Id, [string]$What) {
    $lines = @(Get-Content $Path -Encoding UTF8)
    $bad = @($lines | Where-Object { $_ -match '-> 5\d\d|ERRO em|ERRO inesperado|AVISO|Erro fatal' })
    $tokens = @($lines | Where-Object { $_ -match '(?i)\b[0-9a-f]{32}\b|Bearer|Authorization' })
    $opened = @($lines | Where-Object { $_ -match 'WS \d+ aberta' }).Count
    $closed = @($lines | Where-Object { $_ -match 'WS \d+ fechada' }).Count
    $origins = ($lines | Where-Object { $_ -match 'Origens permitidas' } | Select-Object -First 1)
    Write-Log ("{0}: {1} linhas; canais abertos {2}, fechados {3}; {4}" -f $What, $lines.Count, $opened, $closed, $origins)
    Add-Check $Id "$What sem 5xx, exceções ou avisos; nenhum token; todo canal aberto foi fechado" (($bad.Count -eq 0) -and ($tokens.Count -eq 0) -and ($opened -eq $closed) -and ($opened -gt 0) -and $origins) ((@($bad + $tokens) | Select-Object -First 3) -join ' | ')
}


function Write-Annotations {
    if (-not (Test-Path $ResultsFile)) { return }
    $json = Get-Content $ResultsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $walk = $null
    $walk = {
        param($suite)
        foreach ($spec in @($suite.specs)) {
            foreach ($t in @($spec.tests)) {
                $seen = @{}
                foreach ($a in @($t.annotations) + @($t.results | ForEach-Object { $_.annotations })) {
                    if ($a -and $a.type -and -not $seen.ContainsKey("$($a.type)|$($a.description)")) {
                        $seen["$($a.type)|$($a.description)"] = 1
                        Write-Log ("  anotação [{0}] {1}: {2}" -f ($spec.title -split ' ')[0], $a.type, $a.description)
                    }
                }
            }
        }
        foreach ($child in @($suite.suites)) { if ($child) { & $walk $child } }
    }
    foreach ($s in @($json.suites)) { & $walk $s }
}


function Get-Sha256Bytes([byte[]]$Bytes) {
    [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($Bytes)).Replace('-', '')
}

function Get-B64Text([string]$B64) { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B64)) }

# Desfaz as mudanças da O5 num arquivo; devolve quantos trechos foram encontrados e o SHA-256 resultante.
function Test-Revert([string]$Rel, $Spec) {
    $path = Join-Path $Root $Rel
    $text = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false)))
    $found = 0
    foreach ($h in $Spec.Hunks) {
        $new = Get-B64Text $h[0]; $old = Get-B64Text $h[1]
        $count = ([regex]::Matches($text, [regex]::Escape($new))).Count
        if ($count -eq 1) { $text = $text.Replace($new, $old); $found++ }
    }
    # ReadAllText descarta o BOM; ele volta ao calcular o SHA-256 (os aprovados têm BOM).
    $hash = Get-Sha256Bytes ([byte[]](@(0xEF, 0xBB, 0xBF) + (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)))
    [pscustomobject]@{ Found = $found; Total = @($Spec.Hunks).Count; Hash = $hash; Ok = ($hash -eq $Spec.Approved) }
}

function Get-MsOfDay($m) { ((([int]$m.Groups[1].Value * 60 + [int]$m.Groups[2].Value) * 60 + [int]$m.Groups[3].Value) * 1000 + [int]$m.Groups[4].Value) }

# Processos de teste deste projeto ainda vivos (servidor, EngineCheck, cliente ws-hold, Playwright).
function Get-ProjectProcesses {
    $rootLower = $Root.ToLowerInvariant()
    @(Get-CimInstance Win32_Process | Where-Object {
        $exe = if ($_.ExecutablePath) { $_.ExecutablePath.ToLowerInvariant() } else { '' }
        $cl = if ($_.CommandLine) { $_.CommandLine.ToLowerInvariant() } else { '' }
        ((($_.Name -eq 'TicTacToeServer.exe') -or ($_.Name -eq 'EngineCheck.exe')) -and $exe.StartsWith($rootLower)) -or
        (($_.Name -eq 'node.exe') -and ($cl.Contains('ws-hold.mjs') -or ($cl.Contains('playwright') -and $cl.Contains($rootLower))))
    })
}

# Ctrl+C real (send-ctrl-c.ps1) num servidor com 10 canais abertos (tools/ws-hold.mjs).
# Com $Abandoned > 0: cria salas sem ninguém conectado antes e logo antes do Ctrl+C,
# para o faxineiro estar encerrando salas no momento do desligamento.
function Invoke-CtrlC([int]$Port, [string[]]$Extra, [string]$Tag, [int]$Abandoned) {
    foreach ($old in @(Get-CimInstance Win32_Process -Filter "Name = 'TicTacToeServer.exe'" | Where-Object { $_.CommandLine -match "--port $Port\b" })) {
        Write-Log "Servidor de execução anterior ainda na porta $Port (PID $($old.ProcessId)); encerrado."
        Stop-Process -Id $old.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
    $busy = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
    if ("$busy".Trim() -ne '000') { throw "A porta $Port já está em uso." }
    $downLog = Join-Path $LogDir "server-o5-$Tag.log"
    if (Test-Path $downLog) { Remove-Item $downLog -Force }
    $line = "/v:on /s /c `"`"$ServerExe`" --port $Port --bind 127.0.0.1 --www `"$WebDir`" $($Extra -join ' ') > `"$downLog`" 2>&1 & echo SAIDA=!ERRORLEVEL! >> `"$downLog`"`""
    $cmd = Start-Process -FilePath 'cmd.exe' -ArgumentList $line -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds(15)
    $up = $false
    while ((Get-Date) -lt $deadline -and -not $up) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
        if ("$code".Trim() -eq '200') { $up = $true } else { Start-Sleep -Milliseconds 200 }
    }
    $serverPid = $null
    $srv = @(Get-CimInstance Win32_Process -Filter "Name = 'TicTacToeServer.exe'" | Where-Object { $_.ParentProcessId -eq $cmd.Id })
    if ($srv.Count -eq 1) { $serverPid = $srv[0].ProcessId }
    if (-not $up -or -not $serverPid) {
        foreach ($s in $srv) { Stop-Process -Id $s.ProcessId -Force -ErrorAction SilentlyContinue }
        throw "Servidor da porta $Port não subiu (health: $up; processos filhos: $($srv.Count))."
    }
    Write-Log "Servidor da porta $Port no ar (PID $serverPid; $($Extra -join ' '))."
    $created = 0
    $createRooms = {
        param([int]$N)
        $ok = 0
        for ($i = 0; $i -lt $N; $i++) {
            $c = & curl.exe -s -o NUL -w '%{http_code}' --max-time 2 -X POST "http://127.0.0.1:$Port/api/rooms" 2>$null
            if ("$c".Trim() -eq '201') { $ok++ }
        }
        $ok
    }
    if ($Abandoned -gt 0) { $created += & $createRooms $Abandoned }
    $ready = Join-Path $LogDir "o5-$Tag-ready.txt"; $holdOut = Join-Path $LogDir "o5-$Tag-result.json"; $holdLog = Join-Path $LogDir "o5-$Tag-client.log"
    foreach ($f in @($ready, $holdOut, $holdLog)) { if (Test-Path $f) { Remove-Item $f -Force } }
    $hold = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"node `"$TestsDir\tools\ws-hold.mjs`" --port $Port --rooms 5 --ready `"$ready`" --out `"$holdOut`" > `"$holdLog`" 2>&1`"" -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Test-Path $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path $ready)) {
        if (Test-Path $holdLog) { Write-Log (Get-Content $holdLog -Raw) }
        Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
        throw 'Os 10 canais não abriram em 15 s.'
    }
    if ($Abandoned -gt 0) {
        # As primeiras salas já passaram do prazo de 1 s; as últimas são criadas agora,
        # para vencerem durante o desligamento.
        Start-Sleep -Milliseconds 1200
        $created += & $createRooms $Abandoned
    }
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$CtrlC`" -ProcessId $serverPid" -WindowStyle Hidden -PassThru -Wait
    Write-Log "send-ctrl-c.ps1 terminou com código $($p.ExitCode) (0 = Ctrl+C enviado)"
    $exited = $cmd.WaitForExit(10000)
    if (-not $exited) { Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue; $cmd.WaitForExit(5000) | Out-Null }
    $hold.WaitForExit(25000) | Out-Null
    if (Test-Path $holdLog) { Write-Log (Get-Content $holdLog -Raw -Encoding UTF8).TrimEnd() }
    $log = if (Test-Path $downLog) { Get-Content $downLog -Raw -Encoding UTF8 } else { '' }
    Write-Log ("Log do servidor (trecho final):`r`n" + ((($log -split "`r?`n") | Select-Object -Last 16) -join "`r`n"))
    $codes = @()
    if (Test-Path $holdOut) { $codes = @((Get-Content $holdOut -Raw | ConvertFrom-Json).fechamentos | ForEach-Object { $_.codigo }) }
    $t1 = [regex]::Match($log, '(?m)^(\d\d):(\d\d):(\d\d)\.(\d\d\d)\s+Encerrando o servidor')
    $t2 = [regex]::Match($log, '(?m)^(\d\d):(\d\d):(\d\d)\.(\d\d\d)\s+Servidor encerrado')
    $ms = 999999
    if ($t1.Success -and $t2.Success) { $ms = (Get-MsOfDay $t2) - (Get-MsOfDay $t1) }
    $after = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
    [pscustomobject]@{
        Exited = $exited; SignalCode = $p.ExitCode; Codes = $codes; Log = $log; Ms = $ms; Created = $created
        CodesOk = ($codes.Count -eq 10) -and (@($codes | Where-Object { $_ -ne 1001 }).Count -eq 0)
        PortFree = ("$after".Trim() -eq '000') -and -not (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)
        HoldGone = $hold.HasExited
    }
}

$failed = 1
try {
    Write-Log ("===== Validação da Entrega O5 - {0}{1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($RedPhase) { ' (FASE VERMELHA: faxineiro em esqueleto, que não varre, e uHttpApp.pas da O4)' } else { '' }))
    Write-Log "Pasta do projeto: $Root"

    # ---- 1. Ambiente -------------------------------------------------------
    Write-Log "`n===== 1. Ambiente"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2}); PowerShell {3}" -f $os.Caption, $os.Version, $os.BuildNumber, $PSVersionTable.PSVersion)
    Write-Log ("git: " + (& cmd.exe /c "git --version 2>&1" | Out-String).Trim() + " | Node.js: " + (& cmd.exe /c "node --version 2>&1" | Out-String).Trim())

    # ---- 2. Preservados e formato -----------------------------------------
    Write-Log "`n===== 2. Arquivos preservados e formato"
    Push-Location $Root
    try {
        & cmd.exe /c "git diff --quiet HEAD -- $($Preserved -join ' ') 2>&1" | Out-Null
        $quietCode = $LASTEXITCODE
        $cfgDiff = @(& cmd.exe /c "git diff -U0 HEAD -- tests/playwright.config.ts 2>&1" | Where-Object { ($_ -match '^[+-]') -and ($_ -notmatch '^(\+\+\+|---) ') })
        $status = (& cmd.exe /c "git status --short --untracked-files=all -- server scripts docs web tests 2>&1" | Out-String).TrimEnd()
    } finally { Pop-Location }
    Add-Check 'P-01' 'Motor, serviço, log, testes antigos (EngineCheck e Playwright), app.js, style.css e plano de testes antigo idênticos ao último commit' ($quietCode -eq 0) "git diff --quiet: código $quietCode"
    $hashProblems = @()
    foreach ($rel in $Hashes.Keys) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $hashProblems += "$rel ausente"; continue }
        $h = (Get-FileHash -Algorithm SHA256 -Path $path).Hash
        if ($h -ne $Hashes[$rel]) { $hashProblems += "$rel ($h)" }
    }
    Add-Check 'P-02' "Arquivos das O1 a O4 não alterados pela O5 idênticos aos aprovados (SHA-256 de $($Hashes.Count) arquivos, inclusive a interface online e os testes da O4)" ($hashProblems.Count -eq 0) ($hashProblems -join '; ')
    $revertProblems = @(); $revertInfo = @()
    foreach ($rel in $Reverts.Keys) {
        $r = Test-Revert $rel $Reverts[$rel]
        $want = if ($RedPhase -and $rel -eq 'server/src/uHttpApp.pas') { 0 } else { $r.Total }
        $revertInfo += ("{0}: {1} de {2} trechos da O5" -f $rel, $r.Found, $r.Total)
        if (-not $r.Ok -or $r.Found -ne $want) { $revertProblems += ("{0}: trechos {1} (esperado {2}); SHA-256 desfeito {3}" -f $rel, $r.Found, $want, $r.Hash) }
    }
    Write-Log ("Mudanças da O5 encontradas: " + ($revertInfo -join '; '))
    Add-Check 'P-03' 'uHttpApp.pas (O4), TicTacToeServer.dpr e EngineCheck.dpr (O3): desfeitas as mudanças da O5, idênticos aos aprovados (nada mais mudou)' ($revertProblems.Count -eq 0) ($revertProblems -join ' | ')
    Write-Log ("Diferenças de tests/playwright.config.ts em relação ao commit:`r`n    " + ($cfgDiff -join "`r`n    "))
    $removed = @($cfgDiff | Where-Object { $_ -like '-*' })
    Add-Check 'P-04' 'playwright.config.ts: só acréscimos em relação ao commit (e igual ao aprovado na O4, P-02)' ($removed.Count -eq 0) ("linhas removidas: {0}" -f $removed.Count)
    Write-Log "git status:`r`n$status"
    $fmt = @()
    foreach ($rel in $NewPascal) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $fmt += "$rel ausente"; continue }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
        $lfOnly = ([regex]::Matches([System.Text.Encoding]::UTF8.GetString($bytes), '(?<!\r)\n')).Count
        if (-not $bom -or $lfOnly) { $fmt += "$rel (BOM: $bom; LF sem CR: $lfOnly)" }
    }
    Add-Check 'P-05' 'Arquivos Pascal novos ou alterados na O5 em UTF-8 com BOM e CRLF (DT-17)' ($fmt.Count -eq 0) ($fmt -join '; ')

    # ---- 3. Compilação -----------------------------------------------------
    Write-Log "`n===== 3. Compilação (scripts\build.cmd)"
    foreach ($old in @(Get-ProjectProcesses)) {
        Write-Log "Processo de execução anterior ainda aberto: $($old.Name) PID $($old.ProcessId) ($($old.CommandLine)); encerrado."
        Stop-Process -Id $old.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
    foreach ($exe in @($EngineExe, $ServerExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $bres = Invoke-CmdWithTimeout "`"$(Join-Path $Root 'scripts\build.cmd')`"" (Join-Path $LogDir 'o5-build.out.log') 300
    $build = $bres.Output
    $buildCode = $bres.Code
    Write-Log $build.TrimEnd()
    $warnings = @([regex]::Matches($build, '(?m)^.*\bWarning: W\d+.*$') | ForEach-Object { $_.Value.Trim() })
    $hints    = @([regex]::Matches($build, '(?m)^.*\bHint: H\d+.*$') | ForEach-Object { $_.Value.Trim() })
    Add-Check 'B-01' 'Servidor e EngineCheck compilados pelo Delphi 10.1 Berlin (31.0) sem erros' (($buildCode -eq 0) -and ($build -match 'compiler version 31\.0') -and (Test-Path $EngineExe) -and (Test-Path $ServerExe)) "Código $buildCode"
    Add-Check 'B-02' 'Nenhum warning nem hint do compilador' (($warnings.Count + $hints.Count) -eq 0) ("Warnings: {0}; hints: {1}; {2}" -f $warnings.Count, $hints.Count, (($warnings + $hints) -join ' | '))
    if (-not (Test-Path $EngineExe) -or -not (Test-Path $ServerExe)) { throw 'Executáveis não gerados.' }

    # ---- 4. Independência --------------------------------------------------
    Write-Log "`n===== 4. Independência das units sem Indy"
    $forbidden = '^(Id\w*|System\.Net\..*|Web\..*|uHttpApp|uConsoleLog|uGameService|uWsSession|uRoomHub|uRoomJson|Vcl\..*|FMX\..*)$'
    $indep = @()
    foreach ($u in @('uWebSocket','uOriginPolicy','uRoomHub','uServerOptions','uRoomHttp','uClock','uSecureRandom','uRoom','uRoomRegistry','uRoomJson','uRoomJanitor')) {
        $src = Get-Content (Join-Path $ServerDir "src\$u.pas") -Raw -Encoding UTF8
        $src = [regex]::Replace($src, '(?s)\{.*?\}|\(\*.*?\*\)', '')
        $usesText = (([regex]::Matches($src, '(?is)\buses\b(.*?);') | ForEach-Object { $_.Groups[1].Value }) -join ',')
        $used = @($usesText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        # uRoomHub e uRoomJson são permitidos onde já eram usados (rotas de sala, hub); o faxineiro não usa nenhum dos dois.
        $deny = if ($u -eq 'uRoomJanitor') { $forbidden } else { '^(Id\w*|System\.Net\..*|Web\..*|uHttpApp|uConsoleLog|uGameService|uWsSession|Vcl\..*|FMX\..*)$' }
        $bad = @($used | Where-Object { $_ -match $deny })
        if ($src -match '(?i)\bWriteln\b|\bLog\s*\(') { $bad += 'escrita de log/console' }
        if ($bad.Count) { $indep += "$u -> $($bad -join ', ')" }
    }
    Add-Check 'I-01' 'Protocolo, origem, hub, opções, rotas de sala, domínio e faxineiro sem Indy, sem servidor e sem log (DTO-21); o faxineiro só usa o domínio (uRoom, uRoomRegistry)' ($indep.Count -eq 0) ($indep -join '; ')

    # ---- 5. EngineCheck ----------------------------------------------------
    Write-Log "`n===== 5. EngineCheck.exe (59 casos: 57 anteriores + JN-01 e JN-02)"
    $run = Invoke-Engine $EngineExe
    Write-Log (($run.Output -split "`r?`n" | Where-Object { $_ -match '^(Casos:|RESULTADO|\[FALHOU\]|\[OK\]\s+JN-|\s+JN-|.*faxineiro)' }) -join "`r`n")
    Write-Log "Código de saída do EngineCheck: $($run.Code); duração $($run.Seconds) s"
    $okIds = Get-CaseIds $run.Output 'OK'
    $failIds = Get-CaseIds $run.Output 'FALHOU'
    $seen = @($okIds + $failIds)
    $missing = @($AllCases | Where-Object { $seen -notcontains $_ })
    $extra = @($seen | Where-Object { $AllCases -notcontains $_ })
    $caseInfo = ("OK: {0}; falharam: {1}; ausentes: {2}; a mais: {3}" -f $okIds.Count, ($failIds -join ','), ($missing -join ','), ($extra -join ','))
    if ($RedPhase) {
        $oldOk = @($OldCases | Where-Object { $okIds -contains $_ }).Count
        $newFail = @($NewCases | Where-Object { $failIds -contains $_ }).Count
        Add-Check 'R-02' 'Fase vermelha: EngineCheck com os 57 casos anteriores aprovados e JN-01 e JN-02 falhando (faxineiro não varre)' (($run.Code -eq 1) -and ($oldOk -eq 57) -and ($newFail -eq 2) -and ($missing.Count -eq 0) -and ($extra.Count -eq 0)) $caseInfo
    } else {
        Add-Check 'E-01' 'EngineCheck sai com código 0 e diz RESULTADO: APROVADO' (($run.Code -eq 0) -and ($run.Output -match 'RESULTADO: APROVADO')) "Código $($run.Code)"
        Add-Check 'E-02' '59 casos executados e aprovados (57 anteriores + JN-01, JN-02)' (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($failIds.Count -eq 0) -and ($okIds.Count -eq 59)) $caseInfo
        $repeatOk = $true; $repeatInfo = @()
        foreach ($n in 2..3) {
            $rr = Invoke-Engine $EngineExe
            $rf = Get-CaseIds $rr.Output 'FALHOU'; $ro = Get-CaseIds $rr.Output 'OK'
            $repeatInfo += ("execução {0}: código {1}, {2} OK, falharam [{3}], {4} s" -f $n, $rr.Code, $ro.Count, ($rf -join ','), $rr.Seconds)
            if (($rr.Code -ne 0) -or ($rf.Count -gt 0) -or ($ro.Count -ne 59)) { $repeatOk = $false; Write-Log $rr.Output.TrimEnd() }
        }
        Add-Check 'E-03' 'EngineCheck aprovado em mais duas execuções seguidas (59/59 em cada)' $repeatOk ($repeatInfo -join ' | ')
    }

    # ---- 6. Tipos ----------------------------------------------------------
    Write-Log "`n===== 6. Checagem de tipos dos testes (tsc --noEmit)"
    if (-not (Test-Path (Join-Path $TestsDir 'node_modules\@playwright\test'))) { throw 'tests\node_modules não tem o @playwright/test (rode npm ci da Entrega 5).' }
    Write-Log ("Playwright: " + (Invoke-InTests 'npx --no-install playwright --version').Output.Trim())
    $tsc = Invoke-InTests 'npm run typecheck'
    Write-Log $tsc.Output.TrimEnd()
    Add-Check 'T-01' 'TypeScript sem erros (suíte antiga e testes novos)' ($tsc.Code -eq 0) "Código $($tsc.Code)"

    # ---- 7. Suíte completa, servidor do Playwright -------------------------
    Write-Log "`n===== 7. Suíte completa, servidor iniciado pelo Playwright (bind padrão 0.0.0.0)"
    $pw = Invoke-Playwright 'npx --no-install playwright test'
    Write-PlaywrightSummary $pw
    $res = Read-Results
    if ($res) { Copy-Item $ResultsFile (Join-Path $LogDir "online-o5$(if ($RedPhase) { '-red' })-results-run1.json") -Force }
    Write-Log ("Resultado: " + (Format-Results $res))
    Write-Annotations
    if ($res -and $res.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res.Failed -join "`r`n  ")); Write-FailureExcerpt $pw 60 }
    if ($RedPhase) {
        $lc = $res.ByProject['online-lifecycle']
        $redFailed = @()
        if ($res) { foreach ($t in $res.Failed) { foreach ($m in [regex]::Matches($t, '(OV|OU)-\d\d')) { $redFailed += $m.Value } } }
        $redFailed = @($redFailed | Sort-Object -Unique)
        $okRed = $res -and ($res.ByProject['api'].ok -eq 80) -and ($res.ByProject['chromium'].ok -eq 29) -and ($res.ByProject['online-api'].ok -eq 31) -and
            ($res.ByProject['online-ws'].ok -eq 18) -and ($res.ByProject['online-ui'].ok -eq 25) -and ($lc.ok -eq 7) -and ($lc.fail -eq 5) -and
            (($redFailed -join ',') -eq 'OU-28,OV-02,OV-03,OV-11,OV-12')
        Add-Check 'R-01' 'Fase vermelha: os 189 testes anteriores e o OV-01 (reinício) aprovados; falham os 5 que dependem do faxineiro (OV-02, OV-03, OV-11, OV-12, OU-28)' ([bool]$okRed) ((Format-Results $res) + "; falharam: " + ($redFailed -join ', '))
    } else {
        Add-Check 'PW-01' "Suíte completa, execução 1 (bind padrão): $ExpectedTotal aprovados (api 80, chromium 29, online-api 31, online-ws 18, online-lifecycle 12, online-ui 25)" (($pw.Code -eq 0) -and (Test-FullSuite $res)) (Format-Results $res)

        # ---- 8. Suíte completa, servidor do script --------------------------
        Write-Log "`n===== 8. Suíte completa de novo, servidor iniciado pelo script com --bind 127.0.0.1"
        $srv = Start-Server $ServerExe 8765 @('--bind', '127.0.0.1') 'server-o5'
        $pw2 = Invoke-Playwright 'npx --no-install playwright test' @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8765' }
        Stop-Server $srv
        Write-PlaywrightSummary $pw2
        $res2 = Read-Results
        if ($res2) { Copy-Item $ResultsFile (Join-Path $LogDir 'online-o5-results-run2.json') -Force }
        Write-Log ("Resultado: " + (Format-Results $res2))
        Write-Annotations
        if ($res2 -and $res2.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res2.Failed -join "`r`n  ")); Write-FailureExcerpt $pw2 60 }
        Add-Check 'PW-02' "Suíte completa, execução 2 (--bind 127.0.0.1): $ExpectedTotal aprovados" (($pw2.Code -eq 0) -and (Test-FullSuite $res2)) (Format-Results $res2)
        Test-ServerLog (Join-Path $LogDir 'server-o5.out.log') 'S-01' 'Log do servidor da execução 2'
        $serverLines = @(Get-Content (Join-Path $LogDir 'server-o5.out.log') -Encoding UTF8)
        $statics = @($serverLines | Where-Object { $_ -match 'GET /online\.(html|js|css) -> 200' }).Count
        $refusedAll = @($serverLines | Where-Object { $_ -match 'Origem recusada' })
        $refusedUi = @($refusedAll | Where-Object { $_ -match 'de [0-9.]+: "http://(127\.0\.0\.1|localhost):8765"\s*$' })
        $janitorLine = ($serverLines | Where-Object { $_ -match 'encerradas por abandono após 600 s' } | Select-Object -First 1)
        $closedByJanitor = @($serverLines | Where-Object { $_ -match 'encerrada por abandono' -and $_ -notmatch 'encerradas por abandono após' }).Count
        Write-Log ("Recusas de origem no log: {0}; linha do faxineiro: {1}; salas encerradas por abandono: {2}" -f $refusedAll.Count, $janitorLine, $closedByJanitor)
        Add-Check 'S-02' 'Páginas online servidas pelo servidor real; nenhuma recusa das origens da própria interface' (($statics -gt 0) -and ($refusedUi.Count -eq 0)) ("GET de /online.*: {0}; recusas da origem da interface: {1}" -f $statics, (($refusedUi | Select-Object -First 3) -join ' | '))
        # Prazo padrão (600 s): numa suíte de poucos minutos nenhuma sala pode ser encerrada por abandono.
        Add-Check 'S-03' 'Servidor com os prazos padrão (600 s; varredura a cada 5.000 ms) informados no início; nenhuma sala encerrada por abandono durante a suíte' ([bool]$janitorLine -and ($closedByJanitor -eq 0)) ("encerradas por abandono: $closedByJanitor")

        # ---- 9. Repetições ------------------------------------------------------
        Write-Log "`n===== 9. Repetição: online-ui duas vezes; ciclo de vida da O5 três vezes"
        $pw3 = Invoke-Playwright 'npx --no-install playwright test --project online-ui --repeat-each 2'
        Write-PlaywrightSummary $pw3
        $res3 = Read-Results
        Write-Log ("Resultado: " + (Format-Results $res3))
        if ($res3 -and $res3.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res3.Failed -join "`r`n  ")); Write-FailureExcerpt $pw3 40 }
        Add-Check 'PW-03' 'Projeto online-ui repetido 2 vezes: 50 de 50' (($pw3.Code -eq 0) -and $res3 -and ($res3.Stats.expected -eq 50) -and ($res3.Stats.unexpected -eq 0) -and ($res3.Stats.flaky -eq 0)) (Format-Results $res3)
        $pw4 = Invoke-Playwright "npx --no-install playwright test --project online-lifecycle --grep `"$NewTests`" --repeat-each 3"
        Write-PlaywrightSummary $pw4
        $res4 = Read-Results
        Write-Log ("Resultado: " + (Format-Results $res4))
        Write-Annotations
        if ($res4 -and $res4.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res4.Failed -join "`r`n  ")); Write-FailureExcerpt $pw4 40 }
        Add-Check 'PW-04' 'Testes de ciclo de vida da O5 (OV-01, OV-02, OV-03, OV-11, OV-12, OU-28) repetidos 3 vezes: 18 de 18' (($pw4.Code -eq 0) -and $res4 -and ($res4.Stats.expected -eq 18) -and ($res4.Stats.unexpected -eq 0) -and ($res4.Stats.flaky -eq 0)) (Format-Results $res4)

        # ---- 10. Ctrl+C ---------------------------------------------------------
        Write-Log "`n===== 10a. Ctrl+C com 10 canais identificados, prazos padrão (porta 8790; regressão da O3/O4)"
        $d1 = Invoke-CtrlC 8790 @() 'ctrlc' 0
        Add-Check 'D-01' 'Ctrl+C com 10 canais: todos recebem 1001; o servidor sai com código 0 em até 5 s' ($d1.Exited -and ($d1.SignalCode -eq 0) -and $d1.CodesOk -and ($d1.Log -match 'SAIDA=0') -and ($d1.Ms -le 5000)) ("encerramento em $($d1.Ms) ms; códigos: " + (($d1.Codes | Sort-Object -Unique) -join ', '))
        Add-Check 'D-02' 'Depois do Ctrl+C a porta fica livre e o cliente ws-hold terminou' ($d1.PortFree -and $d1.HoldGone) ''

        Write-Log "`n===== 10b. Ctrl+C com o faxineiro trabalhando (porta 8791; prazo 1 s, varredura a cada 20 ms, 2 x 40 salas abandonadas)"
        $d3 = Invoke-CtrlC 8791 @('--room-ttl-seconds', '1', '--remember-seconds', '1', '--sweep-ms', '20') 'ctrlc-faxineiro' 40
        $abandonLines = @(($d3.Log -split "`r?`n") | Where-Object { $_ -match 'Sala \S+ encerrada por abandono' }).Count
        $badLines = @(($d3.Log -split "`r?`n") | Where-Object { $_ -match '-> 5\d\d|ERRO|AVISO|Erro fatal|(?i)\b[0-9a-f]{32}\b' })
        $order = [regex]::Match($d3.Log, '(?s)Encerrando o servidor.*Servidor encerrado').Success
        $afterStop = $false
        $stopIdx = $d3.Log.IndexOf('Servidor encerrado')
        if ($stopIdx -ge 0) { $afterStop = $d3.Log.Substring($stopIdx) -match 'encerrada por abandono' }
        Add-Check 'D-03' 'Ctrl+C com o faxineiro encerrando salas: 10 canais recebem 1001, saída com código 0 em até 5 s, salas encerradas por abandono antes do desligamento e nenhuma depois, log sem erro nem token' (
            $d3.Exited -and ($d3.SignalCode -eq 0) -and $d3.CodesOk -and ($d3.Log -match 'SAIDA=0') -and ($d3.Ms -le 5000) -and $order -and
            ($d3.Created -eq 80) -and ($abandonLines -ge 40) -and (-not $afterStop) -and ($badLines.Count -eq 0)) (
            "encerramento em $($d3.Ms) ms; códigos: " + (($d3.Codes | Sort-Object -Unique) -join ', ') + "; salas criadas: $($d3.Created); encerradas por abandono no log: $abandonLines; depois de 'Servidor encerrado': $afterStop; linhas suspeitas: " + (($badLines | Select-Object -First 3) -join ' | '))
        Add-Check 'D-04' 'Depois do segundo Ctrl+C a porta 8791 fica livre e o cliente ws-hold terminou' ($d3.PortFree -and $d3.HoldGone) ''

        # ---- 11. Sabotagens ---------------------------------------------------
        Write-Log "`n===== 11. Sabotagens (cópias em logs\sabotage; o código original não é alterado)"
        $CR = "`r`n"
        $webSabotages = @(
            @{ Id = 'SB-09'; Desc = 'online.js desenha o símbolo na célula clicada antes da resposta do servidor';
               Grep = 'OU-09'; MustFail = @('OU-09');
               Find = "      return request('POST', roomPath(code) + '/moves', token, { posicao: index }).then(handleRoomResponse);";
               Replace = "      cells[index].textContent = seat;   /* sabotagem SB-09 */$CR      return request('POST', roomPath(code) + '/moves', token, { posicao: index }).then(handleRoomResponse);" },
            @{ Id = 'SB-16'; Desc = 'online.js coloca o token na URL da página';
               Grep = 'OU-01|OU-03|OU-17'; MustFail = @('OU-01', 'OU-03', 'OU-17');
               Find = "    window.history.replaceState(null, '', pagePath(code));$CR    clearError();";
               Replace = "    window.history.replaceState(null, '', pagePath(code) + '&t=' + token);   /* sabotagem SB-16 */$CR    clearError();" }
        )
        foreach ($sb in $webSabotages) {
            Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
            $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o5"
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            $sabWeb = Join-Path $dir 'web'
            New-Item -ItemType Directory -Force -Path $sabWeb | Out-Null
            Copy-Item (Join-Path $WebDir '*') $sabWeb
            $target = Join-Path $sabWeb 'online.js'
            $text = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
            $text = $text.Replace("`r`n", "`n")
            $find = $sb.Find.Replace("`r`n", "`n"); $repl = $sb.Replace.Replace("`r`n", "`n")
            $count = ([regex]::Matches($text, [regex]::Escape($find))).Count
            if ($count -ne 1) { Write-Log "Trecho encontrado $count vez(es) (esperado 1): $find"; Add-Check $sb.Id "$($sb.Desc): sabotagem aplicada" $false ''; continue }
            [System.IO.File]::WriteAllText($target, $text.Replace($find, $repl), (New-Object System.Text.UTF8Encoding($false)))
            $sab = Start-Server $ServerExe 8766 @('--bind', '127.0.0.1') ("server-o5-" + $sb.Id) $sabWeb
            $r = Invoke-Playwright "npx --no-install playwright test --project online-ui --grep `"$($sb.Grep)`"" @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766' }
            Stop-Server $sab
            $sres = Read-Results
            $failedIds = @()
            if ($sres) { foreach ($t in $sres.Failed) { foreach ($m in [regex]::Matches($t, 'OU-\d\d')) { $failedIds += $m.Value } } }
            $failedIds = @($failedIds | Sort-Object -Unique)
            $notCaught = @($sb.MustFail | Where-Object { $failedIds -notcontains $_ })
            Write-Log ("Playwright contra a interface sabotada: código {0}; testes que falharam: {1}; {2}" -f $r.Code, ($failedIds -join ', '), (Format-Results $sres))
            Write-FailureExcerpt $r 16
            Add-Check $sb.Id "$($sb.Desc): falham $($sb.MustFail -join ', ')" (($r.Code -ne 0) -and ($notCaught.Count -eq 0)) ("Não detectados: " + ($notCaught -join ', '))
        }
        # Servidor: cópia sabotada do código Delphi (mesmo procedimento da O3 e da O4).
        $sabotages = @(
            @{ Id = 'SB-11'; Desc = 'Hub.Publish não publica nada (a interface deixa de receber as jogadas)'; File = 'uRoomHub.pas'; Engine = @('HB-02', 'HB-03');
               Grep = 'OU-06|OU-08|OW-04|OW-05|OW-06'; Projects = '--project online-ui --project online-ws'; MustFail = @('OU-06', 'OU-08', 'OW-04', 'OW-05', 'OW-06');
               Edits = @(
                 @{ Find = "    for Sub in List do$CR      if Sub.Outbox.EnqueueState(AText, AVersion) then$CR        Inc(Result);"; Replace = '    { sabotagem SB-11: estado nao e publicado }' },
                 @{ Find = "    for Sub in List do$CR    begin$CR      Sub.Outbox.EnqueueTerminal(AText, ACloseCode);$CR      Inc(Result);$CR    end;"; Replace = '    { sabotagem SB-11: encerramento nao e publicado }' }) },
            @{ Id = 'SB-13'; Desc = 'O faxineiro roda, mas não varre (nenhuma sala é encerrada por abandono nem esquecida)'; File = 'uRoomJanitor.pas'; Engine = @('JN-01', 'JN-02');
               Grep = 'OV-02|OV-03|OV-11|OV-12|OU-28'; Projects = '--project online-lifecycle'; MustFail = @('OV-02', 'OV-03', 'OV-11', 'OV-12', 'OU-28');
               Edits = @(
                 @{ Find = "      Closed := FRegistry.Sweep(FTtlMs);"; Replace = "      SetLength(Closed, 0);   { sabotagem SB-13: nao varre }" }) },
            @{ Id = 'SB-17'; Desc = 'A sala é encerrada pelo prazo mesmo com alguém conectado'; File = 'uRoom.pas'; Engine = @('JN-01', 'JN-02');
               Grep = 'OV-03|OV-12|OU-28'; Projects = '--project online-lifecycle'; MustFail = @('OV-03', 'OV-12', 'OU-28');
               Edits = @(
                 @{ Find = "  if (not AnyConnectedLocked) and (ANowMs - FLastActivity > ATtlMs) then"; Replace = "  if (ANowMs - FLastActivity > ATtlMs) then   { sabotagem SB-17: ignora conexoes }" }) }
        )
        foreach ($sb in $sabotages) {
            Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
            $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o5"
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'src'), (Join-Path $dir 'tests') | Out-Null
            Copy-Item (Join-Path $ServerDir 'TicTacToeServer.dpr') $dir
            Copy-Item (Join-Path $ServerDir 'EngineCheck.dpr') $dir
            Copy-Item (Join-Path $ServerDir 'src\*.pas') (Join-Path $dir 'src')
            Copy-Item (Join-Path $ServerDir 'tests\*.pas') (Join-Path $dir 'tests')
            $target = Join-Path $dir "src\$($sb.File)"
            $text = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
            $applied = $true
            foreach ($e in $sb.Edits) {
                $count = ([regex]::Matches($text, [regex]::Escape($e.Find))).Count
                if ($count -ne 1) { $applied = $false; Write-Log "Trecho encontrado $count vez(es) (esperado 1): $($e.Find)"; break }
                $text = $text.Replace($e.Find, $e.Replace)
            }
            if (-not $applied) { Add-Check $sb.Id "$($sb.Desc): sabotagem aplicada" $false ''; continue }
            [System.IO.File]::WriteAllText($target, $text, (New-Object System.Text.UTF8Encoding($true)))
            $c1 = Invoke-Compile $dir 'TicTacToeServer.dpr'
            $c2 = Invoke-Compile $dir 'EngineCheck.dpr'
            if (($c1.Code -ne 0) -or ($c2.Code -ne 0)) { Write-Log ($c1.Output + $c2.Output).TrimEnd(); Add-Check $sb.Id "$($sb.Desc): cópia sabotada compila" $false ''; continue }
            $er = Invoke-Engine (Join-Path $dir 'bin\EngineCheck.exe')
            $ef = Get-CaseIds $er.Output 'FALHOU'
            $engineMissed = @($sb.Engine | Where-Object { $ef -notcontains $_ })
            Write-Log ("EngineCheck sabotado: código {0}; casos que falharam: {1}" -f $er.Code, ($ef -join ', '))
            $sabExe = Join-Path $dir 'bin\TicTacToeServer.exe'
            $sab = Start-Server $sabExe 8766 @('--bind', '127.0.0.1') ("server-o5-" + $sb.Id)
            $r = Invoke-Playwright "npx --no-install playwright test $($sb.Projects) --grep `"$($sb.Grep)`"" @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766'; PW_SERVER_EXE = $sabExe }
            Stop-Server $sab
            $sres = Read-Results
            $failedIds = @()
            if ($sres) { foreach ($t in $sres.Failed) { foreach ($m in [regex]::Matches($t, '(OW|OA|OV|OR|OU)-\d\d[a-c]?')) { $failedIds += $m.Value } } }
            $failedIds = @($failedIds | Sort-Object -Unique)
            $notCaught = @($sb.MustFail | Where-Object { $failedIds -notcontains $_ })
            Write-Log ("Playwright contra o servidor sabotado: código {0}; testes que falharam: {1}; {2}" -f $r.Code, ($failedIds -join ', '), (Format-Results $sres))
            Write-FailureExcerpt $r 24
            Add-Check $sb.Id "$($sb.Desc): falham $($sb.MustFail -join ', ') e, no EngineCheck, $($sb.Engine -join ', ')" (($r.Code -ne 0) -and ($notCaught.Count -eq 0) -and ($er.Code -eq 1) -and ($engineMissed.Count -eq 0)) ("Não detectados: " + (($notCaught + $engineMissed) -join ', '))
        }

        # ---- 12. Processos órfãos e portas --------------------------------------
        Write-Log "`n===== 12. Processos órfãos e portas de teste"
        Start-Sleep -Seconds 2
        $orphans = @(Get-ProjectProcesses)
        foreach ($o in $orphans) { Write-Log ("Processo ainda aberto: {0} PID {1}: {2}" -f $o.Name, $o.ProcessId, $o.CommandLine) }
        $busyPorts = @()
        foreach ($port in $TestPorts) {
            $c = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$port/health" 2>$null
            if ("$c".Trim() -ne '000') { $busyPorts += $port }
        }
        Add-Check 'D-05' "Nenhum processo órfão (TicTacToeServer, EngineCheck, ws-hold, Playwright) e as $($TestPorts.Count) portas de teste livres" (($orphans.Count -eq 0) -and ($busyPorts.Count -eq 0)) ("processos: {0}; portas ocupadas: {1}" -f $orphans.Count, ($busyPorts -join ', '))
    }
}
catch {
    Write-Log ("ERRO NA VALIDAÇÃO: " + $_.Exception.Message)
    [void]$Results.Add([pscustomobject]@{ Id = 'X'; Status = 'FALHOU'; Description = $_.Exception.Message })
}
finally {
    foreach ($s in $Servers) { Stop-Server $s }
    $failed = @($Results | Where-Object { $_.Status -ne 'PASSOU' }).Count
    Write-Log "`n===== Resumo"
    foreach ($item in $Results) { Write-Log ("{0,-7} {1,-7} {2}" -f $item.Status, $item.Id, $item.Description) }
    Write-Log ("Total: {0} verificações, {1} falha(s)." -f $Results.Count, $failed)
    Write-Log ("Resultado final: " + $(if ($failed -eq 0 -and $Results.Count -gt 0) { 'APROVADO' } else { 'REPROVADO' }))
    Write-Log ("Log completo: " + $LogFile)
}
if ($failed -eq 0) { exit 0 } else { exit 1 }
