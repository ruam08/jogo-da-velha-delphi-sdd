# Validação da Entrega O7: regressão completa e integridade, a partir de uma cópia limpa.
#  0. cópia limpa do projeto em %TEMP%\jogo-da-velha-o7-limpo-autorizado, sem executáveis, .dcu, logs nem
#     resultados de teste (o trabalho das O0 a O6 ainda não está em commit, então um "git clone"
#     não teria o código; a cópia limpa é a alternativa, registrada como desvio); tudo o que
#     vem depois roda na cópia, e os logs ficam em logs\ da pasta original;
#  1. ambiente; 2. arquivos preservados: git (Entregas 1 a 5) e SHA-256 de todos os arquivos
#     aprovados até a O6 (código, interface, testes, capturas de referência, scripts e
#     documentos que a O7 não altera);
#  3. compilação do zero (com limite de tempo); 4. independência das units sem Indy;
#  5. EngineCheck (65 casos), três vezes; 6. checagem de tipos dos testes;
#  7. a suíte completa (207 testes) três vezes seguidas: servidor do Playwright (bind padrão),
#     servidor do script com --bind 127.0.0.1 (log sem token, OV-09) e de novo o do Playwright;
#  8. repetições: online-ui duas vezes; testes de endurecimento (O6) e de corpo (O7) duas vezes;
#  9. Ctrl+C: 10 canais; com o faxineiro trabalhando; no modo público com limites;
# 10. sabotagens de todas as entregas online que se aplicam ao servidor e à interface
#     (domínio, hub, faxineiro, origem, limites, corpo) contra o servidor real;
# 11. nenhum processo órfão e portas de teste livres; 12. SHA-256 dos executáveis e dos arquivos.
# Saída em logs\online-o7.log. Windows PowerShell 5.1. Opção -NoCleanCopy: roda na pasta original.
param([switch]$NoCleanCopy)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Source    = Split-Path -Parent $PSScriptRoot
$LogDir    = Join-Path $Source 'logs'
$LogFile   = Join-Path $LogDir 'online-o7.log'
$CopyDir   = Join-Path $env:TEMP 'jogo-da-velha-o7-limpo-autorizado'   # a de 19/10 (sem autorização) fica intocada
$Root      = $Source   # passa a ser a cópia limpa na seção 0

$OldCases = @('M-01','M-02','M-03','M-04','M-05-L1','M-05-L2','M-05-L3','M-05-C1','M-05-C2',
    'M-05-C3','M-05-D1','M-05-D2','M-06','M-07','M-08','M-09','M-10','M-11','M-12',
    'J-01','J-02','J-03','J-04','J-05','SV-01','SV-02','SV-03',
    'SL-01','SL-02','SL-03','SL-04','SL-05','SL-06','SL-07','SL-08','SL-09','SL-10',
    'SL-11','SL-12','MEM-01','SC-01','SC-02','RJ-01','RJ-02','RJ-03','OP-01',
    'OP-02','WS-01','WS-02','WS-03','WS-04','WS-05','WS-06','WS-07','HB-01','HB-02','HB-03','JN-01','JN-02',
    'RL-01','RL-02','RL-03','RL-04','RL-05','OP-03')
$AllCases = $OldCases
$Expected = [ordered]@{ api = 80; chromium = 29; 'online-api' = 31; 'online-ws' = 18; 'online-lifecycle' = 24; 'online-ui' = 25 }
$ExpectedTotal = 207
# Testes de endurecimento (O6, hardening.spec.ts) e o do corpo no limite (O7, body-limit.spec.ts).
$HardTests = 'OV-06a|OV-06b|OV-06c|OV-07|OV-13|OV-14a|OV-14b|OV-15a|OV-15b|OV-16|OV-17|OV-18'
$HardTestCount = 12

# Sob controle do git (último commit): motor, serviço, log, testes antigos e a interface local.
$Preserved = @('server/src/uGameEngine.pas','server/src/uGameService.pas','server/src/uConsoleLog.pas',
    'server/tests/uMiniTest.pas','server/tests/uEngineTests.pas','server/tests/uServiceTests.pas',
    'server/tests/uJsonTests.pas','web/app.js','web/style.css','tests/api','tests/rules','tests/ui','tests/support/api.ts',
    'tests/support/fixtures.ts','tests/support/raw-http.ts','tests/support/sequences.ts','tests/support/ui.ts',
    'tests/package.json','tests/package-lock.json','tests/tsconfig.json','docs/test-plan.md')
# SHA-256 de todos os arquivos aprovados até a O6 que a O7 não altera (inventário de 19/10, 19:33,
# feito antes da autorização e preservado em logs\o7-nao-autorizado-19out\o7-hashes-inicio.txt; os 87
# arquivos das O1 a O6 nele foram conferidos em 20/10 contra as cópias entregues em cada entrega: 0 diferenças), sem README, delivery-log, plano e plano de testes online, a
# configuração e o script da demonstração e os arquivos que não são das entregas).
$ApprovedList = @'
B830A762C5D047BFAC0C5238698EAA8257F14CA6491BADA33AC362E2202F79D3  .gitattributes
8FCB7AF4E8B377C22C753B9D903FCB0BF308848855429899E351745D6F33420D  .gitignore
EF473161A5B52CAE689AC03713D29E97F73EB23A4B35B624C3FC3F8AD426E069  docs/plan.md
1E68D3CF742B82EE01A087C5FACACFDD5D3E9FCAB2C7785A6C98A4FA30F4AB93  docs/screenshots/online-celular-encerrada.png
8534F12C97DD8E5C9B8B7D9CDF2ED0AFFEE52E62FB6B411550FD50D9BAA1E8DF  docs/screenshots/online-celular-jogando.png
8FF74FDF08C461D52DFA8AF7F3A5D594D2AD652408700B46A7C4C91FE2006C18  docs/screenshots/online-desktop-inicio.png
EF4208DB784826AA48E1151C288E4EB5221635D71C55017E8346A4A565EC6CBC  docs/screenshots/online-desktop-jogando-a.png
F63EE2F2D63DD27AC7FBB50E66F6563EF67D8B0585391890747AA910F8CA66B1  docs/screenshots/online-desktop-jogando-b.png
23C603B463F1CCFF68B50E7BAA156D273FC7CE76EC4906BFC39D4A4E04FFF1EC  docs/screenshots/online-desktop-sala-criada.png
8B2E86F19E7562236E31EFFBE6E01489C3D6A2658B4D61542862A82AC9BF7CAF  docs/screenshots/online-desktop-vitoria-a.png
E86A00102B9DFA8A34AA77811F9D7E5C1F44D1A4CDB48EA43DEE44825C151BB7  docs/screenshots/online-desktop-vitoria-b.png
8F340BD8729E1D64B469FDF595BC200DA4C4403DBD2491CB5A7181FD85961E68  docs/screenshots/ui-celular-empate.png
D8882D31A7320C7E0527C9736495CEFC0DE4692A376E98BFB3E422DC386AFFE0  docs/screenshots/ui-celular-vitoria.png
C4544A072EFA5206BFAF5E6B039F250212478794B44164FA15BCDEADAE0BB2DC  docs/screenshots/ui-desktop-jogando.png
76979C9150AE3C00ECFB7402CDD0DA9BA8CCA7E4400906CF45236BABB181EB70  docs/screenshots/ui-desktop-vitoria.png
D47723E3C479BFACC4F90349DD0ED39417B4EE7EBC5460FC7DE1B1060E1C3C02  docs/spec.md
AB848A6FD3058BC29E47AF2C128D27A78EBED84FE1E80672EB633F9199C0CDF8  docs/spec-online.md
5D31B1B7362043465707ED18DAAC4B838A79E753E2817244FFE38A5F6D07B1A9  docs/test-plan.md
876439B0E45F81879F0AFF634394AA952D5ADEA27FCF4A94E5BBFC17C686D1EA  scripts/build.cmd
18EEBA2D2A1B96EE5657772B1E4B4205048CBA252F6C0B15F7EA4CB8AC80CC1A  scripts/compile-dpr.cmd
03C676DFA6D21D27B4010DE5F8FEE12720A71DAB6FC9925B88BD0E12157775E4  scripts/delphi-env.cmd
A91F9F3E9131F102B05985B899E1A76A949B745923B0FA868BED5EC398066CF8  scripts/regression-o4-baseline.cmd
9A5F77423B9F0728F12FA49E3C6C1EF78EF141B474EBC8066D6505485E591D1B  scripts/regression-o5-baseline.cmd
84AB94B8D9005C55FB482FB586D4D624C996957ACEAD47E355B3259D2D6119FA  scripts/regression-o6-baseline.cmd
3AE8AEF39DED0F410D43E620A110AE277AEABB8B57F600808DE84757536240DD  scripts/send-ctrl-c.ps1
1EBC8B93527C5672CAA720DE6637B7E98F22FB2D06A6F8CBE5C378946E431993  scripts/validate-online-o1.cmd
9B260CA8FF218799591DB96E4EBE483971832B704B0EF57209F51802D80B1D21  scripts/validate-online-o1.ps1
AFEDABD19F9C2FA84751BD1F4CE0729674DC2D66A1D17884F27B855AA55208FD  scripts/validate-online-o1-red.cmd
EDD96996928C236EDE75F678D9D77E01BBCF61BEC8996037A651CF4EF4EA4F88  scripts/validate-online-o2.cmd
25121EDC179A16D13BED8200DD58583F308CC55D59466C7BCD2E2BE690B5EA58  scripts/validate-online-o2.ps1
9FD8D508EF3D7AD0399841D9C2952B3EA063B11AA020071B96DD08B520376CC4  scripts/validate-online-o2-red.cmd
FE02DA62467C15273D03AC68D24EDB70661B774289A0A6474656766FB0D1AE0F  scripts/validate-online-o3.cmd
5112C63B3BD2ED343AA6C1BEEA9E566477868C7CE80EF241A62B8F9BB5DFE3A6  scripts/validate-online-o3.ps1
AC688DE1D1B92A7DEB2C69ABF3117AED79E1EE3DC795ABC29FAAB8E8B7DF24CF  scripts/validate-online-o3-red.cmd
3C702B9A867F8D3B89C464B056DF81B6744292FA2518A9ACABD8D8DD19782B5A  scripts/validate-online-o4.cmd
91E145B91A55CAE0A185142DF96142B0DB0EF3DEB69AAE60F571E407A87A03E2  scripts/validate-online-o4.ps1
2126D17C0AADADDF431BA921E7E36CE420592CA962A13B39BB45A19114DCE07B  scripts/validate-online-o4-red.cmd
570144C8F67FAEA610C195EFE5957968B1575E302A084C3D5F42092DBDC25D46  scripts/validate-online-o5.cmd
EBDA448522D6E74D00217F8E9A2AED88783C6E0E08662173BE95468B0CC33948  scripts/validate-online-o5.ps1
45943D871E8D781272D02D181810163DC0FC83C38B67650BC85B84C0C64025E9  scripts/validate-online-o5-red.cmd
AC3890D4A7DD1E009930FCBAA19F6890F8F6AE8CBE7A3F12DAB340938F8C1F6D  scripts/validate-online-o6.cmd
7DBB45C475277A2DCA9026FB775DDBEA7D8A2DDA5D65917DC06448E9F78C2974  scripts/validate-online-o6.ps1
32016EBEB6F6187BF55675E53AD9745BA81E75DBA3DBE13A8F55B710891024E6  scripts/validate-online-o6-red.cmd
FE097271536949B1C918FD0CB8084F3B7193D16F2B8B48AE3AA8AF3A779EB7B4  scripts/validate-step1.cmd
8AA227798719661D232AB7C5112738E3EAFABB3818444EF7E7E262D0A0675312  scripts/validate-step1.ps1
C3E5043E784B7E1ED99251F635EC492DD17E7E49AFE97AA76E042746A3888BE5  scripts/validate-step2.cmd
58D4A8D4A697685BF4A15EF5A35F8DB9313F534F21F257589EF32D1565C620F5  scripts/validate-step2.ps1
57E1BD46A360CE768E5D2D630272E14BBD9C5ED8D2099BA50C05127F51FB416B  scripts/validate-step2-red.cmd
0ECB2ABE0F9C73D5B9E88BCCBB7FABE011EFE9E623D1123ADFFD25094FAB35B8  scripts/validate-step3.cmd
5D6827E3B3A134CFFFC5CA95DD75DCC1BB9DA995B61A7B8C97DA1002A54C9439  scripts/validate-step3.ps1
427090255BDD0E6DABC02CF5B3563B4FB8D4409DECD9FBD69AAD76C02C70944F  scripts/validate-step3-red.cmd
D278C4E1B7314336DE6155BBE80EA5A3144FC488F5ABE2D48C13E66C3B94C960  scripts/validate-step4.cmd
24E490F79B878B790EE814C02651EB56271B64A61389DAC8DB35A8E26E7D894F  scripts/validate-step4.ps1
E0E80AE3DD7D098D8685B6E407179454F8CFF0618D42D0D0037112F5E35C5554  scripts/validate-step5.cmd
1670CBCB449640CA0EE133776604F7499D0BEDD14C7D61902A570ECF5CD97F5B  scripts/validate-step5.ps1
62F57716968C005F4A4D33229433331C72872A1743CE1D45B199299CFECAF60A  scripts/validate-step5-red.cmd
849C23548744414B53F9091FEE53A821E1111A6BD0979628CD87CA9EF8CD4B0E  server/EngineCheck.dpr
87142FE997345C909B797F2940080A19EDC87A046A83721AD84163D7903F11D5  server/src/uClock.pas
F83B6B46F5CD729F66746D2721F94E3B9CE05C75353DC4240976011925081BA5  server/src/uConsoleLog.pas
F68C2E06E13F6505DBCBAFEB9ADE4566723B1EE9800B2B072D95BD697BDC67C6  server/src/uGameEngine.pas
5E5F66BA863ED98189EB1E9A9353906D20AD130F283D31E63F5A44B636CE1AD5  server/src/uGameJson.pas
5B0E16C76802A3B41ED627BCD8BF14AF9BC8845654A051A57AC0664E214AF6A9  server/src/uGameService.pas
F1A31EFC5EC699FD931042F72E5138D5FBEA9AAC9FBDB1C56C397150C192B07C  server/src/uHttpApp.pas
77AA746ECE101DA3BE466023A18A7FC4414C669103AFBCFF1DC3BA9CE36403A2  server/src/uOriginPolicy.pas
FF6F10824551B7E5F80107BF93B43EF64251FBB3DADA38FE7CBE4299EC25C600  server/src/uRateLimiter.pas
224F6F1BFAEC7DD06A61077E55EC841DE174349F231512FA795CFBB0B97ED8AB  server/src/uRequestLimits.pas
77CABC56139576236E47A9ECA8C7C2519039D90681DB066F7E217C8B2385283A  server/src/uRoom.pas
C5C7A3A8C03054B5327AE3014B25322E72C5387E7EF5F483F6EDD72E1311BA4D  server/src/uRoomHttp.pas
B7C5878C9EB42761A3F387493A14079228223580C49C9D80B8D540DD2EAFFBD5  server/src/uRoomHub.pas
0526E604F41D68DE592FA52E95573045A1FC9851084817D3545E8533BE2B78FB  server/src/uRoomJanitor.pas
6B13B1A128A4020BA909DE301A33D72C3A7632F3FD6BB78228E58AB64FD6D8E0  server/src/uRoomJson.pas
803F17485EFCFAF48429E88CB9E229B2A81828C64136E0DA1BA06FD7A3C6AE54  server/src/uRoomRegistry.pas
0323BFDB1586E8FC697DF84AE15422444BEED4BCD72610D0894BB341A11F1F33  server/src/uSecureRandom.pas
F68C0D70BF542A5CCA0FB6BB885C2D290B87F62FFCB389CC4D1D958BD97E9B87  server/src/uServerOptions.pas
CC27AA638BBB639D97A0AA83EEEDD85DFF2BB668D8045BFF3628D35EDDB3E189  server/src/uWebSocket.pas
01E69D847B82B34D7A4C8135CF92AE1BF0B6CFE0ED25933F1947CEC5AF0DB601  server/src/uWsSession.pas
AF86ACDA2B64640AAF6F5E3D9D5AF8DC7E83A2D84FA91863A14D1C669407907D  server/tests/uEngineTests.pas
34F2ACF2B5A5090ACF1BBD24EE4C9DCDE8D5357FB203E360DD0B7359DD2256FF  server/tests/uJsonTests.pas
FE59B773848599FEA5257B073A31BF6D52A9DB5949F4F01BEFCF337ED128F756  server/tests/uLimitTests.pas
528E2B8E8E8CBE6BDD80040AAF4087D02B63C3FA2BD58F50405B696358D4743A  server/tests/uMiniTest.pas
DBA36BA8EC60344C5414B0009BB4AF3EF16A9D1017580E649C34F747D1190280  server/tests/uOptionsTests.pas
C3FCC88689F8A46025771B4B2AD00128A77B2717D16927261FB40FBC421662CD  server/tests/uRoomConcurrencyTests.pas
A4014773C0BBF9A480B2C1DD0E6156645C47CE0886F4D48DFF5DEB8161C833F8  server/tests/uRoomHubTests.pas
A3D3761A94E6C606DDAC4E2603D37F619E0B7BE26116F54FEA8590D338C68E23  server/tests/uRoomJanitorTests.pas
824DC1751170E304F4ACAB0B4F500A84DF5F3827E8C613009F648F8972C02822  server/tests/uRoomJsonTests.pas
48283B3C71D2DC7609E8C7DF2F896615AA320948F97F0547255AAFB2E372CE38  server/tests/uRoomTests.pas
28688B9DF809F7D429B37D187E998E8E2B93B13C32ED0CA1DE109A21A4451111  server/tests/uServiceTests.pas
D69AE30C530590DB52FB5B8DBD6796A812F03A7C1AF409E8223D26C4D568B5AC  server/tests/uWebSocketTests.pas
95BCFB78CE70E1B113B48B057012414720003C84ACF1D58D5B49491C4AFBB465  server/TicTacToeServer.dpr
8A5E83E8771049515C213C21A7BDFD0BB7682AAB8783D280C923D67897593F94  spikes/ws-indy/client/browser-test.cjs
9FF9E8AD8385698289D1A5C49987EFE328F21134B18CEC3C7D1C6DFD793D766D  spikes/ws-indy/client/ws-tests.mjs
9688BEC27625E3232F5BEADFF1A3874CF529E5D3FAF48581314935F9CAE10FF8  spikes/ws-indy/page.html
0FD2617C7FB1B73C80F885FCF953DF9D083F28BC4E2C5A7703E04A0A274D471B  spikes/ws-indy/README.md
DB8982DDC42D87920118471ADFBB76A5CCC25A247DBD076D4B0F74F931D3D30E  spikes/ws-indy/src/uSpikeLog.pas
F8AC553E746E241B7638DA07978CF3A65DDA3B43B1AE9884596AF5D390A8DE3E  spikes/ws-indy/src/uWsCodec.pas
F5A19A32178CA307CF006A442ACF379030CD7D6C0A7AF0A11FABAF278E7666B8  spikes/ws-indy/src/uWsSelfTest.pas
63E1BD8CBD145A970B17375A17B0CC0AFB85A871115B169524DEB2CCCFEFFF71  spikes/ws-indy/src/uWsSpikeServer.pas
0983237D38EE6C8F901AE82F302C24448F79FA7E328745B16D41E71FE9C7483C  spikes/ws-indy/tools/send-ctrl-c.ps1
3B12F705C95CBB819DF017B4B37EDF3DD1AB11F344F0251DEC57C26CF45F4087  spikes/ws-indy/validate-o0.cmd
7730620A1D58285AEA1D0520743C22560EEE6702A39C8551044F63F4ED0A779F  spikes/ws-indy/validate-o0.ps1
4A8EB396F69EB582A0E403921C1B019247197ECA1158F67A20BE376DC12CFB8F  spikes/ws-indy/WsSpike.dpr
EB1458506B99A432A53E8D3F2F8BE4815AA25A2BB7F74993CAF814EC5F002597  tests/api/contract.spec.ts
D37A49BB8B4A8E134AE895B3FF980422DF6817E0A910275DEC64F5F043FDB2DA  tests/api/routes.spec.ts
B43EC17216EDFD2F53940190AE9EDFB9DE62F979E169B958AB5E9018144FEBAB  tests/api/static.spec.ts
A3A3074F6B2C05A150E92E02B3397FADF47F6FBE207713C6E124F9656CAB80DE  tests/api/validation.spec.ts
79BE26F4A61B09CC9FF1DA9308CE71E97A24733BD6F33CE7BD639835A54E8372  tests/online/lifecycle/hardening.spec.ts
F2DF458D841A3A5AD0332A1DA8E9B14BC425639628433DF5B764DA6DDF5F2EF3  tests/online/lifecycle/load.spec.ts
F6F93B2FFC8DB158F07EB96052B1735C85EF186EC56694DE7C48877119873C75  tests/online/lifecycle/origin.spec.ts
DF30308F582D2588406BCF719AE4C588C3B85E2261164BD62EF180B68A1F268B  tests/online/lifecycle/rooms.spec.ts
A793521A7CD726BB72DA545983B3887EC8DE85FA04C25590100CF2D18EC7A6D8  tests/online/lifecycle/ui.spec.ts
14D49275266D677AEC65C1083D86B706CE48D9350F3247A44AFD160E5037B74F  tests/online/room-api/contract.spec.ts
C155D577751EBE8C25FECD578E465FE5A1222F55DDEB4773675DF2544D437B65  tests/online/room-api/errors.spec.ts
CF9C07DC8BB9C7D529980DD3111A76D13D17C11E5EA4BC5C532CE17A8A8E1B71  tests/online/room-api/legacy-auth.spec.ts
C9EC574A755BBDC537019820561E85E1B77D464CD4B8E9999ECCA6F0629B24A7  tests/online/room-api/origin.spec.ts
BC7F23A7BF8D6F687E3955DF8C31DDB4FC573F34A6BF9464B38E8B17430E323C  tests/online/room-api/routes.spec.ts
E5EAAB6F86789E8B7EFC6D23F44E53D08CD1C01C65BAF39129EC2139FC325EC0  tests/online/room-api/static.spec.ts
A74188A5CC57E91D78DE18CE30CFE2B7E0E3AF18EB2720C6D529E2C2F4047057  tests/online/room-rules/concurrency.spec.ts
3235385F25760CCE528DB1B4CC2F62E5C02FE81DD1BD46441363601FE82A14FC  tests/online/room-rules/games.spec.ts
83246670BD6CA2E6154D4D0D834728BBCEB2BE310ED0E5EA13B7975333E981AD  tests/online/room-rules/moves.spec.ts
6AF57E97F98B60F5CA42DC8D1DEEA51E6AE1FD4047D79BDAC8F80A94A8D850F4  tests/online/room-ui/connection.spec.ts
7F17C4EACC9E9B2586B1FB0190E22D7BD35BC5A8B59AE4EBB8B1B0966393EA6C  tests/online/room-ui/create-join.spec.ts
BC17D0B13592B859EF8F6635CA632A288D98014BAD132C26914BC977DDC7777E  tests/online/room-ui/layout.spec.ts
FAF30CFEBE2E843FC4D4E312D8101064D12D7D591DA43E4C4EF75E3519359AA3  tests/online/room-ui/play.spec.ts
747CF64A73817ECF1C7C241FF0095B0EE9B7E837947F1B54B9105B2D01773AB4  tests/online/room-ws/channel.spec.ts
295F79F1F92DDDEDDD3B0485ED7063742CBEB0BA3ED7A735F84AB100F4B74F2D  tests/online/room-ws/sync.spec.ts
923C288DB7FBE1DC77ADCF057901620823244667C3ABFB4187C10404AEAC0D27  tests/online/room-ws/timeouts.spec.ts
BB7D495E29610D53EFE710DA1D062D96D86A84DC016B46D06DDA94F528721E5E  tests/package.json
5DD336A6525B3C7791A4226A65044D58A34B21DF6DCAD79A91B362167C9D28F8  tests/package-lock.json
C2FEEE583F8683ACBCA0B75F05F41081BF3DD734DA7A6668769EDF5D094A1DAE  tests/playwright.config.ts
5FBC621AAC78FD376AEE848EC8A87B25C9767839EBF01B46800F00948B8FEE19  tests/rules/concurrency.spec.ts
8F7A1669FED68427F84F1BD9C204C3669DDDCF5E0C60C6ED06E6F3939A8B56B9  tests/rules/end-and-reset.spec.ts
16782F29EC2A0B139D7623F1BAC8151D9079E329AB27097912DD16E0EC9DB487  tests/rules/turns.spec.ts
6C6309E80C3B133875D3EFB692B6A252EBEB2888FDE5B46AB818807054D79784  tests/rules/wins.spec.ts
2D44FF9A29BEE32E80FFEA235F0FC5857556992120EA773F26A6A52F4E01E12B  tests/support/api.ts
3F00E6EB24782D08004971BD4D028278EE85AB1AAF2C0F112E0EE49BDD1DD8F6  tests/support/fixtures.ts
E2493F7B9509CC0BCD686AD435EF66F69B10DD8A786351F87C361259BE024301  tests/support/online/fixtures.ts
8E6ABF8E8FD393636FF6D7C6F444CCAED2ED9F54E7CB67B10CAD2F15F1FADE41  tests/support/online/hardening.ts
11B78086E85FE453DC0B396766598A9622B6F9379618E51F50DE25F8B5BA090B  tests/support/online/online-ui.ts
4D9CF31EC7CEACE58590A41002179912076B87E1BC538882E3C925080BC58483  tests/support/online/raw-request.ts
DCE560484C95E5D7FF0E52DF8A8F5580A6AB6D7CC849DE763CE58F9C1E8DD678  tests/support/online/rooms.ts
E496220BC9E4770610ECC7CF207C8BD398177E27544D09F1819A8C04DBDE4989  tests/support/online/server-process.ts
DF8D3932CE544E0ED48EA6A06F405DBCA3F23BFAB8241F255D4B4DBDDCA49915  tests/support/online/ui-fixtures.ts
422A440391E94E66961A04AE7FB7FDB872AB3B09F37B9BE2ACB2B9270361161F  tests/support/online/ws-client.ts
4A97AD868735B57660871ECC04FE3B85E30797AE3B0248481FA190412BFCBE76  tests/support/raw-http.ts
BD4403A881EB9E471E21AA05FD238F0DE99EC5E9FEAD24A4C00CCF2FA52D2D71  tests/support/sequences.ts
A59371074C96A19615695F31570C62ABFB5DD09FA0C136A56F8DCDE5183E802D  tests/support/ui.ts
6F60A104315345C445E23F82724B7E9ADF2A4E63A2901C32572A143CBF62541D  tests/tools/capture.cjs
932308A9B8EFA7646F0BA7712A73317FECD8470F02D4ECD2FE0150D1311E547F  tests/tools/capture-online.cjs
7CEC0BA9A5FEF200FE1930966B8DA0473230796DD50457C14AF14405D61C821A  tests/tools/ws-hold.mjs
AA3574288D8354DBFD5F8DBBEE0182ECB358F85CCA6B0799966FDE0B9D52E2D6  tests/tools/ws-hold-origin.mjs
8C9F1E85C51055A0D5AA7BA8BD8DA3380B09880B621A8A55591CE11AF8EF447E  tests/tsconfig.json
8E765ABBD9ADAD97F92FE33D57EB8749A72DA3AB9CF005F52A95EE7F70F01507  tests/ui/accessibility.spec.ts
71B15F09D762818A574B2B308DF631FEAD05DE0C1C83AD583990BE215ED2B8C1  tests/ui/end-and-reset.spec.ts
E855B7C20C64B84E0BFE0DB91EA58E70BC2ABDA41F4EA7173B7691CB8794D398  tests/ui/resilience.spec.ts
4F42536745D1029948B59D6938A3EA3DAC6E967390A178166F46EDDB53974CDC  tests/ui/start-and-turns.spec.ts
9C1641CE6C32EB041A2CF2D64A83DEE61A82B1EBC4B458033F7A4B30A01A0994  tests/ui/wins.spec.ts
25C0A3FFE95C0A7C1753EF62917826393B61EAD1D2D67AEB21831151ACC7F140  web/app.js
0DA583FA30F3109FAD474DCCAAABAE34120B8A7F5860937BAC11E899A4B069F4  web/index.html
FF1E853F8BD9261F3F28ADBE83E9D31EB8DDB04534ACE17788F47B3DECE93BC8  web/online.css
20DEE08122BC6B7E016304227A10962B39F71296AFA92903FEEC0850898F4BA1  web/online.html
9538D675A9281270865C55BFBE248D8297A4A6C3C42018CD65EFA22A0BA5E680  web/online.js
B2B6E4B13239096F7C9AF4DF5C3369ED1253C754B85013548051CBE90D1B0F6C  web/style.css
'@
$Hashes = [ordered]@{}
foreach ($l in ($ApprovedList -split "`r?`n")) { if ($l.Length -gt 66) { $Hashes[$l.Substring(66)] = $l.Substring(0, 64) } }
$NewFiles = @('tests/online/lifecycle/body-limit.spec.ts', 'scripts/validate-online-o7.ps1', 'scripts/validate-online-o7.cmd',
    'scripts/o7-inventory.ps1', 'scripts/o7-inventory.cmd', 'scripts/demo-playwright-headed.ps1',
    'scripts/o7-servidor-rede-local.ps1', 'scripts/o7-servidor-rede-local.cmd')
$TestPorts = @(8765, 8766, 8770, 8771, 8772, 8773, 8774, 8775, 8776, 8777, 8778, 8779, 8783, 8784,
    8785, 8786, 8787, 8788, 8789, 8790, 8791, 8792, 8793, 8794, 8795, 8796, 8797, 8798, 8799, 8800,
    8801, 8802, 8803, 8804, 8805, 8806, 8807, 8809, 8810)

function Set-RootPaths([string]$Dir) {
    $script:Root      = $Dir
    $script:ServerDir = Join-Path $Dir 'server'
    $script:TestsDir  = Join-Path $Dir 'tests'
    $script:WebDir    = Join-Path $Dir 'web'
    $script:EngineExe = Join-Path $script:ServerDir 'bin\EngineCheck.exe'
    $script:ServerExe = Join-Path $script:ServerDir 'bin\TicTacToeServer.exe'
    $script:Compile   = Join-Path $Dir 'scripts\compile-dpr.cmd'
    $script:CtrlC     = Join-Path $Dir 'scripts\send-ctrl-c.ps1'
    $script:ResultsFile = Join-Path $script:TestsDir 'test-results\results.json'
}
Set-RootPaths $Source

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

function Get-MsOfDay($m) { ((([int]$m.Groups[1].Value * 60 + [int]$m.Groups[2].Value) * 60 + [int]$m.Groups[3].Value) * 1000 + [int]$m.Groups[4].Value) }

# Processos de teste deste projeto ainda vivos (servidor, EngineCheck, cliente ws-hold, Playwright),
# na cópia limpa e na pasta original (onde ficam as cópias sabotadas, em logs\sabotage).
function Get-ProjectProcesses {
    $roots = @($Root.ToLowerInvariant(), $Source.ToLowerInvariant())
    @(Get-CimInstance Win32_Process | Where-Object {
        $exe = if ($_.ExecutablePath) { $_.ExecutablePath.ToLowerInvariant() } else { '' }
        $cl = if ($_.CommandLine) { $_.CommandLine.ToLowerInvariant() } else { '' }
        $inProject = $false
        foreach ($r in $roots) { if ($exe.StartsWith($r) -or $cl.Contains($r)) { $inProject = $true } }
        ((($_.Name -eq 'TicTacToeServer.exe') -or ($_.Name -eq 'EngineCheck.exe')) -and $inProject) -or
        (($_.Name -eq 'node.exe') -and ($cl.Contains('ws-hold') -or ($cl.Contains('playwright') -and $inProject)))
    })
}

# Ctrl+C real (send-ctrl-c.ps1) num servidor com 2 x $Rooms canais abertos (tools/ws-hold.mjs ou,
# no modo público, tools/ws-hold-origin.mjs, que manda o Origin configurado).
# Com $Abandoned > 0: cria salas sem ninguém conectado antes e logo antes do Ctrl+C,
# para o faxineiro estar encerrando salas no momento do desligamento.
function Invoke-CtrlC([int]$Port, [string[]]$Extra, [string]$Tag, [int]$Abandoned, [string]$Tool = 'ws-hold.mjs',
    [string]$ToolArgs = '', [int]$Rooms = 5) {
    foreach ($old in @(Get-CimInstance Win32_Process -Filter "Name = 'TicTacToeServer.exe'" | Where-Object { $_.CommandLine -match "--port $Port\b" })) {
        Write-Log "Servidor de execução anterior ainda na porta $Port (PID $($old.ProcessId)); encerrado."
        Stop-Process -Id $old.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
    $busy = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$Port/health" 2>$null
    if ("$busy".Trim() -ne '000') { throw "A porta $Port já está em uso." }
    $downLog = Join-Path $LogDir "server-o7-$Tag.log"
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
    $ready = Join-Path $LogDir "o7-$Tag-ready.txt"; $holdOut = Join-Path $LogDir "o7-$Tag-result.json"; $holdLog = Join-Path $LogDir "o7-$Tag-client.log"
    foreach ($f in @($ready, $holdOut, $holdLog)) { if (Test-Path $f) { Remove-Item $f -Force } }
    $hold = Start-Process -FilePath 'cmd.exe' -ArgumentList "/s /c `"node `"$TestsDir\tools\$Tool`" --port $Port --rooms $Rooms $ToolArgs --ready `"$ready`" --out `"$holdOut`" > `"$holdLog`" 2>&1`"" -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Test-Path $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path $ready)) {
        if (Test-Path $holdLog) { Write-Log (Get-Content $holdLog -Raw) }
        Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
        throw "Os $(2 * $Rooms) canais não abriram em 15 s."
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
        CodesOk = ($codes.Count -eq 2 * $Rooms) -and (@($codes | Where-Object { $_ -ne 1001 }).Count -eq 0)
        PortFree = ("$after".Trim() -eq '000') -and -not (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)
        HoldGone = $hold.HasExited
    }
}


function Invoke-SuiteCheck([string]$Id, [string]$Title, [string]$Tag, $Run) {
    Write-PlaywrightSummary $Run
    $r = Read-Results
    if ($r) { Copy-Item $ResultsFile (Join-Path $LogDir "online-o7-results-$Tag.json") -Force }
    Write-Log ("Resultado: " + (Format-Results $r))
    Write-Annotations
    if ($r -and $r.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($r.Failed -join "`r`n  ")); Write-FailureExcerpt $Run 60 }
    Add-Check $Id $Title (($Run.Code -eq 0) -and (Test-FullSuite $r)) (Format-Results $r)
}

$failed = 1
try {
    Write-Log ("===== Validação da Entrega O7 - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-Log "Pasta do projeto: $Source"

    # ---- 0. Cópia limpa -----------------------------------------------------
    if ($NoCleanCopy) {
        Write-Log "`n===== 0. Cópia limpa: desligada (-NoCleanCopy); tudo roda na pasta original"
    } else {
        Write-Log "`n===== 0. Cópia limpa em $CopyDir"
        foreach ($old in @(Get-ProjectProcesses)) {
            Write-Log "Processo de execução anterior ainda aberto: $($old.Name) PID $($old.ProcessId); encerrado."
            Stop-Process -Id $old.ProcessId -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $CopyDir) { Remove-Item $CopyDir -Recurse -Force }
        $xd = @('logs', 'server\bin', 'server\dcu', 'server\__recovery', 'server\Win32', 'server\Win64', 'tests\test-results', 'tests\playwright-report', 'tests\demo-results',
                'spikes\ws-indy\bin', 'spikes\ws-indy\dcu') | ForEach-Object { "`"$(Join-Path $Source $_)`"" }
        $rc = "`"$Source`" `"$CopyDir`" /E /XD $($xd -join ' ') __history __recovery /XF *.dcu *.exe *.local *.identcache *.stat *.dsk /NFL /NDL /NJH /NP /R:1 /W:1"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $robo = & cmd.exe /c "robocopy $rc 2>&1" | Out-String
        $roboCode = $LASTEXITCODE
        $sw.Stop()
        Write-Log ($robo.Trim())
        $leftovers = @(Get-ChildItem $CopyDir -Recurse -File -Force -Include *.exe, *.dcu | Where-Object { $_.FullName -notlike '*\node_modules\*' })
        $results0 = @('tests\test-results', 'tests\playwright-report', 'logs', 'server\bin', 'server\dcu') | Where-Object { Test-Path (Join-Path $CopyDir $_) }
        $copyCount = @(Get-ChildItem $CopyDir -Recurse -File -Force).Count
        Add-Check 'C-01' 'Cópia limpa criada sem executáveis, .dcu, logs nem resultados de teste (compilação e testes partem do zero)' (
            ($roboCode -lt 8) -and ($leftovers.Count -eq 0) -and (@($results0).Count -eq 0)) (
            "robocopy código $roboCode em $([math]::Round($sw.Elapsed.TotalSeconds, 1)) s; $copyCount arquivos (inclusive .git e tests\node_modules); sobras: " + ((@($leftovers | ForEach-Object { $_.Name }) + @($results0)) -join ', '))
        Set-RootPaths $CopyDir
    }
    Write-Log "Pasta em uso nas seções seguintes: $Root"

    # ---- 1. Ambiente -------------------------------------------------------
    Write-Log "`n===== 1. Ambiente"
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Log ("Windows: {0} (versão {1}, build {2}); PowerShell {3}" -f $os.Caption, $os.Version, $os.BuildNumber, $PSVersionTable.PSVersion)
    Write-Log ("git: " + (& cmd.exe /c "git --version 2>&1" | Out-String).Trim() + " | Node.js: " + (& cmd.exe /c "node --version 2>&1" | Out-String).Trim())

    # ---- 2. Preservados ------------------------------------------------------
    Write-Log "`n===== 2. Arquivos preservados"
    Push-Location $Root
    try {
        & cmd.exe /c "git diff --quiet HEAD -- $($Preserved -join ' ') 2>&1" | Out-Null
        $quietCode = $LASTEXITCODE
        $head = (& cmd.exe /c "git rev-parse --short HEAD 2>&1" | Out-String).Trim()
        $status = (& cmd.exe /c "git status --short --untracked-files=all 2>&1" | Out-String).TrimEnd()
    } finally { Pop-Location }
    Add-Check 'P-01' "Motor, serviço, log, testes antigos, app.js, style.css e plano de testes antigo idênticos ao último commit ($head)" ($quietCode -eq 0) "git diff --quiet: código $quietCode"
    $hashProblems = @()
    foreach ($rel in $Hashes.Keys) {
        $path = Join-Path $Root $rel
        if (-not (Test-Path $path)) { $hashProblems += "$rel ausente"; continue }
        $h = (Get-FileHash -Algorithm SHA256 -Path $path).Hash
        if ($h -ne $Hashes[$rel]) { $hashProblems += "$rel ($h)" }
    }
    Add-Check 'P-02' "Todos os arquivos aprovados até a O6 que a O7 não altera idênticos (SHA-256 de $($Hashes.Count) arquivos: código Delphi, interface, todos os testes e suportes, capturas de referência, scripts e documentos)" ($hashProblems.Count -eq 0) ($hashProblems -join '; ')
    $missingNew = @($NewFiles | Where-Object { -not (Test-Path (Join-Path $Root $_)) })
    # Arquivos do projeto do Delphi (IDE) que já existiam e não pertencem às entregas (inventário da O7).
    $unrelated = @('server/TicTacToeServer.dproj', 'server/TicTacToeServer.res')
    $prodNew = @(($status -split "`r?`n") | Where-Object { $_ -match '^\?\? (server/|web/)' } | ForEach-Object { $_.Substring(3) } | Where-Object { (-not $Hashes.Contains($_)) -and ($unrelated -notcontains $_) })
    Add-Check 'P-03' 'Nenhum arquivo novo de produção (server/, web/) na O7; os arquivos novos da O7 presentes (teste OV-18, scripts)' (($missingNew.Count -eq 0) -and ($prodNew.Count -eq 0)) ("ausentes: " + ($missingNew -join ', ') + "; novos em server/ ou web/ fora dos aprovados: " + ($prodNew -join ', '))
    Write-Log "git status (pasta em uso):`r`n$status"

    # ---- 3. Compilação -----------------------------------------------------
    Write-Log "`n===== 3. Compilação do zero (scripts\build.cmd)"
    foreach ($old in @(Get-ProjectProcesses)) {
        Write-Log "Processo de execução anterior ainda aberto: $($old.Name) PID $($old.ProcessId) ($($old.CommandLine)); encerrado."
        Stop-Process -Id $old.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
    foreach ($exe in @($EngineExe, $ServerExe)) { if (Test-Path $exe) { Remove-Item $exe -Force } }
    $bres = Invoke-CmdWithTimeout "`"$(Join-Path $Root 'scripts\build.cmd')`"" (Join-Path $LogDir 'o7-build.out.log') 300
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
    foreach ($u in @('uWebSocket','uOriginPolicy','uRoomHub','uServerOptions','uRoomHttp','uClock','uSecureRandom','uRoom','uRoomRegistry','uRoomJson','uRoomJanitor','uRateLimiter','uRequestLimits')) {
        $src = Get-Content (Join-Path $ServerDir "src\$u.pas") -Raw -Encoding UTF8
        $src = [regex]::Replace($src, '(?s)\{.*?\}|\(\*.*?\*\)', '')
        $usesText = (([regex]::Matches($src, '(?is)\buses\b(.*?);') | ForEach-Object { $_.Groups[1].Value }) -join ',')
        $used = @($usesText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $deny = if ($u -eq 'uRoomJanitor') { $forbidden } else { '^(Id\w*|System\.Net\..*|Web\..*|uHttpApp|uConsoleLog|uGameService|uWsSession|Vcl\..*|FMX\..*)$' }
        $bad = @($used | Where-Object { $_ -match $deny })
        if ($src -match '(?i)\bWriteln\b|\bLog\s*\(') { $bad += 'escrita de log/console' }
        if ($bad.Count) { $indep += "$u -> $($bad -join ', ')" }
    }
    Add-Check 'I-01' 'Protocolo, origem, hub, opções, rotas de sala, domínio, faxineiro e limites sem Indy, sem servidor e sem log (DTO-21)' ($indep.Count -eq 0) ($indep -join '; ')

    # ---- 5. EngineCheck ----------------------------------------------------
    Write-Log "`n===== 5. EngineCheck.exe (65 casos), três execuções"
    $engineInfo = @(); $engineOk = $true
    foreach ($n in 1..3) {
        $run = Invoke-Engine $EngineExe
        $okIds = Get-CaseIds $run.Output 'OK'; $failIds = Get-CaseIds $run.Output 'FALHOU'
        $seen = @($okIds + $failIds)
        $missing = @($AllCases | Where-Object { $seen -notcontains $_ }); $extra = @($seen | Where-Object { $AllCases -notcontains $_ })
        $engineInfo += ("execução {0}: código {1}, {2} OK, falharam [{3}], ausentes [{4}], a mais [{5}], {6} s" -f $n, $run.Code, $okIds.Count, ($failIds -join ','), ($missing -join ','), ($extra -join ','), $run.Seconds)
        if ($n -eq 1) { Write-Log (($run.Output -split "`r?`n" | Where-Object { $_ -match '^(Casos:|RESULTADO|\[FALHOU\])' }) -join "`r`n") }
        if (($run.Code -ne 0) -or ($run.Output -notmatch 'RESULTADO: APROVADO') -or $failIds.Count -or $missing.Count -or $extra.Count -or ($okIds.Count -ne 65)) { $engineOk = $false; Write-Log $run.Output.TrimEnd() }
    }
    Add-Check 'E-01' 'EngineCheck: 65 de 65 casos em três execuções seguidas (código 0, RESULTADO: APROVADO)' $engineOk ($engineInfo -join ' | ')

    # ---- 6. Tipos ----------------------------------------------------------
    Write-Log "`n===== 6. Checagem de tipos dos testes (tsc --noEmit)"
    if (-not (Test-Path (Join-Path $TestsDir 'node_modules\@playwright\test'))) { throw 'tests\node_modules não tem o @playwright/test.' }
    Write-Log ("Playwright: " + (Invoke-InTests 'npx --no-install playwright --version').Output.Trim())
    $tsc = Invoke-InTests 'npm run typecheck'
    Write-Log $tsc.Output.TrimEnd()
    Add-Check 'T-01' 'TypeScript sem erros (todos os testes, o novo OV-18 e a configuração da demonstração)' ($tsc.Code -eq 0) "Código $($tsc.Code)"

    # ---- 7. Suíte completa, três vezes seguidas ---------------------------
    Write-Log "`n===== 7a. Suíte completa, execução 1: servidor iniciado pelo Playwright (bind padrão 0.0.0.0)"
    $pw1 = Invoke-Playwright 'npx --no-install playwright test'
    Invoke-SuiteCheck 'PW-01' "Suíte completa, execução 1 (bind padrão): $ExpectedTotal aprovados (api 80, chromium 29, online-api 31, online-ws 18, online-lifecycle 24, online-ui 25)" 'run1' $pw1

    Write-Log "`n===== 7b. Suíte completa, execução 2: servidor iniciado pelo script com --bind 127.0.0.1"
    $srv = Start-Server $ServerExe 8765 @('--bind', '127.0.0.1') 'server-o7'
    $pw2 = Invoke-Playwright 'npx --no-install playwright test' @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8765' }
    Stop-Server $srv
    Invoke-SuiteCheck 'PW-02' "Suíte completa, execução 2 (--bind 127.0.0.1): $ExpectedTotal aprovados" 'run2' $pw2
    Test-ServerLog (Join-Path $LogDir 'server-o7.out.log') 'S-01' 'Log do servidor da execução 2'
    $serverLines = @(Get-Content (Join-Path $LogDir 'server-o7.out.log') -Encoding UTF8)
    $statics = @($serverLines | Where-Object { $_ -match 'GET /online\.(html|js|css) -> 200' }).Count
    $refusedUi = @($serverLines | Where-Object { $_ -match 'Origem recusada' } | Where-Object { $_ -match 'de [0-9.]+: "http://(127\.0\.0\.1|localhost):8765"\s*$' })
    Add-Check 'S-02' 'Páginas online servidas pelo servidor real; nenhuma recusa das origens da própria interface' (($statics -gt 0) -and ($refusedUi.Count -eq 0)) ("GET de /online.*: {0}; recusas da origem da interface: {1}" -f $statics, (($refusedUi | Select-Object -First 3) -join ' | '))
    $janitorLine = ($serverLines | Where-Object { $_ -match 'encerradas por abandono após 600 s' } | Select-Object -First 1)
    $closedByJanitor = @($serverLines | Where-Object { $_ -match 'encerrada por abandono' -and $_ -notmatch 'encerradas por abandono após' }).Count
    Add-Check 'S-03' 'Prazos padrão (600 s; varredura a cada 5.000 ms) informados; nenhuma sala encerrada por abandono durante a suíte' ([bool]$janitorLine -and ($closedByJanitor -eq 0)) ("encerradas por abandono: $closedByJanitor")
    $limitsLine = ($serverLines | Where-Object { $_ -match 'Limites: ' } | Select-Object -First 1)
    $localOff = [bool]$limitsLine -and ($limitsLine -match 'corpo até 64 KB; leitura em até 30 s') -and
        ($limitsLine -match 'criação de salas sem limite, consulta/entrada sem limite, abertura de canal sem limite; canais simultâneos por cliente sem limite; mensagens por canal a cada 10 s sem limite')
    $limited = @($serverLines | Where-Object { $_ -match '-> 429|Canal recusado|Conexão recusada' }).Count
    Add-Check 'S-04' 'Modo local: taxas e limites por cliente desligados; nenhuma recusa por limite (429/503) na suíte inteira' ($localOff -and ($limited -eq 0)) ("linha: $limitsLine; recusas por limite: $limited")
    $tokenFiles = @()
    $serverLogs = @(Get-ChildItem (Join-Path $TestsDir 'test-results\servers') -Filter '*.log' -ErrorAction SilentlyContinue) + @(Get-Item (Join-Path $LogDir 'server-o7.out.log'))
    foreach ($f in $serverLogs) { if ((Get-Content $f.FullName -Raw -Encoding UTF8) -match '(?i)\b[0-9a-f]{32}\b|Bearer [0-9a-f]') { $tokenFiles += $f.Name } }
    Add-Check 'S-05' "Nenhum token nos $($serverLogs.Count) logs de servidor da execução 2 (o do script e os dos servidores dedicados; OV-09)" ($tokenFiles.Count -eq 0) ($tokenFiles -join ', ')

    Write-Log "`n===== 7c. Suíte completa, execução 3: servidor iniciado pelo Playwright (bind padrão)"
    $pw3 = Invoke-Playwright 'npx --no-install playwright test'
    Invoke-SuiteCheck 'PW-03' "Suíte completa, execução 3 (bind padrão): $ExpectedTotal aprovados — três execuções seguidas" 'run3' $pw3

    # ---- 8. Repetições ------------------------------------------------------
    Write-Log "`n===== 8. Repetição: online-ui duas vezes; endurecimento e corpo no limite duas vezes"
    $pw4 = Invoke-Playwright 'npx --no-install playwright test --project online-ui --repeat-each 2'
    Write-PlaywrightSummary $pw4
    $res4 = Read-Results
    Write-Log ("Resultado: " + (Format-Results $res4))
    if ($res4 -and $res4.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res4.Failed -join "`r`n  ")); Write-FailureExcerpt $pw4 40 }
    Add-Check 'PW-04' 'Projeto online-ui repetido 2 vezes: 50 de 50' (($pw4.Code -eq 0) -and $res4 -and ($res4.Stats.expected -eq 50) -and ($res4.Stats.unexpected -eq 0) -and ($res4.Stats.flaky -eq 0)) (Format-Results $res4)
    $pw5 = Invoke-Playwright "npx --no-install playwright test --project online-lifecycle --grep `"$HardTests`" --repeat-each 2"
    Write-PlaywrightSummary $pw5
    $res5 = Read-Results
    Write-Log ("Resultado: " + (Format-Results $res5))
    Write-Annotations
    if ($res5 -and $res5.Failed.Count) { Write-Log ("Falharam:`r`n  " + ($res5.Failed -join "`r`n  ")); Write-FailureExcerpt $pw5 40 }
    Add-Check 'PW-05' "Endurecimento (OV-06a a OV-17) e corpo no limite (OV-18), $HardTestCount testes, repetidos 2 vezes: $(2 * $HardTestCount) de $(2 * $HardTestCount)" (($pw5.Code -eq 0) -and $res5 -and ($res5.Stats.expected -eq 2 * $HardTestCount) -and ($res5.Stats.unexpected -eq 0) -and ($res5.Stats.flaky -eq 0)) (Format-Results $res5)

    # ---- 9. Ctrl+C ---------------------------------------------------------
    Write-Log "`n===== 9a. Ctrl+C com 10 canais identificados (porta 8790)"
    $d1 = Invoke-CtrlC 8790 @() 'ctrlc' 0
    Add-Check 'D-01' 'Ctrl+C com 10 canais: todos recebem 1001; o servidor sai com código 0 em até 5 s; porta livre; cliente terminou' ($d1.Exited -and ($d1.SignalCode -eq 0) -and $d1.CodesOk -and ($d1.Log -match 'SAIDA=0') -and ($d1.Ms -le 5000) -and $d1.PortFree -and $d1.HoldGone) ("encerramento em $($d1.Ms) ms; códigos: " + (($d1.Codes | Sort-Object -Unique) -join ', '))
    Write-Log "`n===== 9b. Ctrl+C com o faxineiro trabalhando (porta 8791; prazo 1 s, varredura a cada 20 ms, 2 x 40 salas abandonadas)"
    $d3 = Invoke-CtrlC 8791 @('--room-ttl-seconds', '1', '--remember-seconds', '1', '--sweep-ms', '20') 'ctrlc-faxineiro' 40
    $abandonLines = @(($d3.Log -split "`r?`n") | Where-Object { $_ -match 'Sala \S+ encerrada por abandono' }).Count
    $badLines = @(($d3.Log -split "`r?`n") | Where-Object { $_ -match '-> 5\d\d|ERRO|AVISO|Erro fatal|(?i)\b[0-9a-f]{32}\b' })
    $order = [regex]::Match($d3.Log, '(?s)Encerrando o servidor.*Servidor encerrado').Success
    $afterStop = $false
    $stopIdx = $d3.Log.IndexOf('Servidor encerrado')
    if ($stopIdx -ge 0) { $afterStop = $d3.Log.Substring($stopIdx) -match 'encerrada por abandono' }
    Add-Check 'D-02' 'Ctrl+C com o faxineiro encerrando salas: 1001 nos 10 canais, código 0 em até 5 s, nenhuma sala encerrada depois do desligamento, log sem erro nem token, porta livre' (
        $d3.Exited -and ($d3.SignalCode -eq 0) -and $d3.CodesOk -and ($d3.Log -match 'SAIDA=0') -and ($d3.Ms -le 5000) -and $order -and
        ($d3.Created -eq 80) -and ($abandonLines -ge 40) -and (-not $afterStop) -and ($badLines.Count -eq 0) -and $d3.PortFree -and $d3.HoldGone) (
        "encerramento em $($d3.Ms) ms; salas criadas: $($d3.Created); encerradas por abandono no log: $abandonLines; depois de 'Servidor encerrado': $afterStop; linhas suspeitas: " + (($badLines | Select-Object -First 3) -join ' | '))
    Write-Log "`n===== 9c. Ctrl+C no modo público com os limites ativos (porta 8809; 8 canais com Origin https://jogo.test)"
    $d6 = Invoke-CtrlC 8809 @('--public', '--allowed-origin', 'https://jogo.test') 'ctrlc-publico' 0 'ws-hold-origin.mjs' '--origin https://jogo.test' 4
    $badPublic = @(($d6.Log -split "`r?`n") | Where-Object { $_ -match '-> [45]\d\d|ERRO|AVISO|Erro fatal|(?i)\b[0-9a-f]{32}\b' })
    Add-Check 'D-03' 'Ctrl+C no modo público com limites e 8 canais: 1001 em todos, código 0 em até 5 s, nenhuma recusa, erro ou token no log, porta livre' (
        $d6.Exited -and ($d6.SignalCode -eq 0) -and $d6.CodesOk -and ($d6.Log -match 'SAIDA=0') -and ($d6.Ms -le 5000) -and
        ($d6.Log -match 'Modo --public') -and ($badPublic.Count -eq 0) -and $d6.PortFree -and $d6.HoldGone) (
        "encerramento em $($d6.Ms) ms; linhas suspeitas: " + (($badPublic | Select-Object -First 3) -join ' | '))

    # ---- 10. Sabotagens ---------------------------------------------------
    Write-Log "`n===== 10. Sabotagens (cópias em logs\sabotage\*-o7; o código não é alterado)"
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
        $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o7"
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        $sabWeb = Join-Path $dir 'web'
        New-Item -ItemType Directory -Force -Path $sabWeb | Out-Null
        Copy-Item (Join-Path $WebDir '*') $sabWeb
        $target = Join-Path $sabWeb 'online.js'
        $text = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
        $find = $sb.Find.Replace("`r`n", "`n"); $repl = $sb.Replace.Replace("`r`n", "`n")
        $count = ([regex]::Matches($text, [regex]::Escape($find))).Count
        if ($count -ne 1) { Write-Log "Trecho encontrado $count vez(es) (esperado 1): $find"; Add-Check $sb.Id "$($sb.Desc): sabotagem aplicada" $false ''; continue }
        [System.IO.File]::WriteAllText($target, $text.Replace($find, $repl), (New-Object System.Text.UTF8Encoding($false)))
        $sab = Start-Server $ServerExe 8766 @('--bind', '127.0.0.1') ("server-o7-" + $sb.Id) $sabWeb
        $r = Invoke-Playwright "npx --no-install playwright test --project online-ui --grep `"$($sb.Grep)`"" @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766' }
        Stop-Server $sab
        $sres = Read-Results
        $failedIds = @()
        if ($sres) { foreach ($t in $sres.Failed) { foreach ($m in [regex]::Matches($t, 'OU-\d\d')) { $failedIds += $m.Value } } }
        $failedIds = @($failedIds | Sort-Object -Unique)
        $notCaught = @($sb.MustFail | Where-Object { $failedIds -notcontains $_ })
        Write-Log ("Playwright contra a interface sabotada: código {0}; testes que falharam: {1}; {2}" -f $r.Code, ($failedIds -join ', '), (Format-Results $sres))
        Write-FailureExcerpt $r 12
        Add-Check $sb.Id "$($sb.Desc): falham $($sb.MustFail -join ', ')" (($r.Code -ne 0) -and ($notCaught.Count -eq 0)) ("Não detectados: " + ($notCaught -join ', '))
    }
    $sabotages = @(
            @{ Id = 'SB-07'; Desc = 'Todas as salas compartilham o mesmo TGameEngine'; File = 'uRoom.pas'; Engine = $null;
               Grep = 'OR-10|OR-13|OR-18'; Projects = '--project online-api'; MustFail = @('OR-10', 'OR-13', 'OR-18');
               Edits = @(
                 @{ Find = "{ ---- TRoom ---"; Replace = "var$CR  GSharedEngine: TGameEngine;   { sabotagem SB-07 }$CR$CR{ ---- TRoom ---" },
                 @{ Find = "  FEngine := TGameEngine.Create;"; Replace = "  if GSharedEngine = nil then$CR    GSharedEngine := TGameEngine.Create;$CR  FEngine := GSharedEngine;" },
                 @{ Find = "  FEngine.Free;"; Replace = "  { sabotagem SB-07: o motor compartilhado nao e liberado }" }) },
            @{ Id = 'SB-08'; Desc = 'Room.Play não verifica de quem é a vez'; File = 'uRoom.pas'; Engine = $null;
               Grep = 'OR-02|OR-08|OR-16|OR-17'; Projects = '--project online-api'; MustFail = @('OR-02', 'OR-08', 'OR-16');
               Edits = @(
                 @{ Find = "  if Game.CurrentPlayer <> SeatToCell(Seat) then$CR    Exit(Unchanged(rrNotYourTurn));"; Replace = "  { sabotagem SB-08: a vez nao e verificada }" }) },
            @{ Id = 'SB-10'; Desc = 'TRoom.Play sem seção crítica, com Sleep(50) entre a validação e a gravação'; File = 'uRoom.pas'; Engine = $null;
               Grep = 'OR-16|OR-17'; Projects = '--project online-api'; MustFail = @('OR-16');
               Edits = @(
                 @{ Find = "  FLock.Enter;$CR  try$CR    Result := DoPlay(AToken, APosition);$CR  finally$CR    FLock.Leave;$CR  end;"; Replace = "  Result := DoPlay(AToken, APosition);   { sabotagem SB-10: sem secao critica }" },
                 @{ Find = "  MoveResult := FEngine.Play(APosition);"; Replace = "  Sleep(50);   { sabotagem SB-10 }$CR  MoveResult := FEngine.Play(APosition);" }) },
            @{ Id = 'SB-12'; Desc = 'Qualquer token de 32 caracteres é aceito como o lugar da vez (REST e canal)'; File = 'uRoom.pas'; Engine = @('SL-07');
               Grep = 'OR-06|OW-08'; Projects = '--project online-api --project online-ws'; MustFail = @('OR-06', 'OW-08');
               Edits = @(
                 @{ Find = "  ASeat := seX;$CR  Result := False;$CR  if AToken = '' then$CR    Exit;"; Replace = "  ASeat := seX;$CR  Result := False;$CR  if AToken = '' then$CR    Exit;$CR  if (Length(AToken) = 32) and (AToken <> FSeats[seX].Token) and (AToken <> FSeats[seO].Token) then$CR  begin   { sabotagem SB-12 }$CR    if FEngine.GetSnapshot.CurrentPlayer = ceO then$CR      ASeat := seO$CR    else$CR      ASeat := seX;$CR    Exit(True);$CR  end;" }) },
            @{ Id = 'SB-11'; Desc = 'Hub.Publish não publica nada (a interface deixa de receber as jogadas)'; File = 'uRoomHub.pas'; Engine = @('HB-02', 'HB-03');
               Grep = 'OU-06|OU-08|OW-04|OW-05|OW-06'; Projects = '--project online-ui --project online-ws'; MustFail = @('OU-06', 'OU-08', 'OW-04', 'OW-05', 'OW-06');
               Edits = @(
                 @{ Find = "    for Sub in List do$CR      if Sub.Outbox.EnqueueState(AText, AVersion) then$CR        Inc(Result);"; Replace = "    { sabotagem SB-11: estado nao e publicado }" },
                 @{ Find = "    for Sub in List do$CR    begin$CR      Sub.Outbox.EnqueueTerminal(AText, ACloseCode);$CR      Inc(Result);$CR    end;"; Replace = "    { sabotagem SB-11: encerramento nao e publicado }" }) },
            @{ Id = 'SB-15'; Desc = 'Hub entrega o estado de uma sala a todas as salas'; File = 'uRoomHub.pas'; Engine = @('HB-02', 'HB-03');
               Grep = 'OW-07'; Projects = '--project online-ws'; MustFail = @('OW-07');
               Edits = @(
                 @{ Find = "    if not FRooms.TryGetValue(ACode, List) then$CR      Exit;$CR    for Sub in List do$CR      if Sub.Outbox.EnqueueState(AText, AVersion) then"; Replace = "    for List in FRooms.Values do   { sabotagem SB-15: todas as salas }$CR    for Sub in List do$CR      if Sub.Outbox.EnqueueState(AText, AVersion) then" }) },
            @{ Id = 'SB-13'; Desc = 'O faxineiro roda, mas não varre (nenhuma sala é encerrada por abandono nem esquecida)'; File = 'uRoomJanitor.pas'; Engine = @('JN-01', 'JN-02');
               Grep = 'OV-02|OV-03|OV-11|OV-12|OU-28'; Projects = '--project online-lifecycle'; MustFail = @('OV-02', 'OV-03', 'OV-11', 'OV-12', 'OU-28');
               Edits = @(
                 @{ Find = "      Closed := FRegistry.Sweep(FTtlMs);"; Replace = "      SetLength(Closed, 0);   { sabotagem SB-13: nao varre }" }) },
            @{ Id = 'SB-17'; Desc = 'A sala é encerrada pelo prazo mesmo com alguém conectado'; File = 'uRoom.pas'; Engine = @('JN-01', 'JN-02');
               Grep = 'OV-03|OV-12|OU-28'; Projects = '--project online-lifecycle'; MustFail = @('OV-03', 'OV-12', 'OU-28');
               Edits = @(
                 @{ Find = "  if (not AnyConnectedLocked) and (ANowMs - FLastActivity > ATtlMs) then"; Replace = "  if (ANowMs - FLastActivity > ATtlMs) then   { sabotagem SB-17: ignora conexoes }" }) },
            @{ Id = 'SB-14'; Desc = 'uOriginPolicy aceita qualquer Origin (inclusive no modo público)'; File = 'uOriginPolicy.pas'; Engine = @('WS-07');
               Grep = 'OA-10|OV-05|OV-07|OV-14b'; Projects = '--project online-api --project online-lifecycle'; MustFail = @('OA-10', 'OV-05a', 'OV-05b', 'OV-05c', 'OV-07', 'OV-14b');
               Edits = @(
                 @{ Find = "  if Length(AOrigins) = 0 then$CR    { Sem Origin"; Replace = "  Exit(True);   { sabotagem SB-14 }$CR  if Length(AOrigins) = 0 then$CR    { Sem Origin" }) },
            @{ Id = 'SB-18'; Desc = 'A taxa por cliente nunca limita'; File = 'uRateLimiter.pas'; Engine = @('RL-01');
               Grep = 'OV-06a|OV-06c|OV-14b|OV-17'; Projects = '--project online-lifecycle'; MustFail = @('OV-06a', 'OV-06c', 'OV-14b', 'OV-17');
               Edits = @(
                 @{ Find = "  if FLimit <= 0 then$CR    Exit;$CR  NowMs := FClock.NowMs;"; Replace = "  Exit;   { sabotagem SB-18: a taxa nunca limita }$CR  NowMs := FClock.NowMs;" }) },
            @{ Id = 'SB-19'; Desc = 'Sem cabeçalhos de segurança (nosniff, Referrer-Policy, CSP)'; File = 'uHttpApp.pas'; Engine = @();
               Grep = 'OV-06a|OV-07|OV-13|OV-18'; Projects = '--project online-lifecycle'; MustFail = @('OV-06a', 'OV-07', 'OV-13', 'OV-18');
               Edits = @(
                 @{ Find = "  AResponseInfo.CustomHeaders.Values['X-Content-Type-Options'] := HEADER_NOSNIFF;$CR  AResponseInfo.CustomHeaders.Values['Referrer-Policy'] := HEADER_REFERRER_POLICY;$CR  if AResponseInfo.ContentType.StartsWith('text/html') then"; Replace = "  { sabotagem SB-19: sem cabecalhos de seguranca }$CR  if False then" }) },
            @{ Id = 'SB-20'; Desc = 'Com --public, /api/game* continuam ativas'; File = 'uHttpApp.pas'; Engine = @();
               Grep = 'OV-07|OV-14b'; Projects = '--project online-lifecycle'; MustFail = @('OV-07', 'OV-14b');
               Edits = @(
                 @{ Find = "  else if FOptions.PublicMode and ((APath = '/api/game') or"; Replace = "  else if False and ((APath = '/api/game') or   { sabotagem SB-20 }" }) },
            @{ Id = 'SB-21'; Desc = 'O canal não limita as mensagens'; File = 'uWsSession.pas'; Engine = @();
               Grep = 'OV-15a'; Projects = '--project online-lifecycle'; MustFail = @('OV-15a');
               Edits = @(
                 @{ Find = "              if (CloseSentAt < 0) and not MsgWindow.Hit(NowMs) then"; Replace = "              if False and not MsgWindow.Hit(NowMs) then   { sabotagem SB-21 }" }) },
            @{ Id = 'SB-22'; Desc = 'Sem limite de canais por cliente'; File = 'uRateLimiter.pas'; Engine = @('RL-02');
               Grep = 'OV-15a|OV-17'; Projects = '--project online-lifecycle'; MustFail = @('OV-15a', 'OV-17');
               Edits = @(
                 @{ Find = "    if N >= FLimit then$CR      Exit(False);"; Replace = "    { sabotagem SB-22: canais por cliente sem limite }" }) },
            @{ Id = 'SB-23'; Desc = 'X-Forwarded-For aceito de qualquer conexão, sem --trust-proxy'; File = 'uRequestLimits.pas'; Engine = @('RL-05');
               Grep = 'OV-06c'; Projects = '--project online-lifecycle'; MustFail = @('OV-06c');
               Edits = @(
                 @{ Find = "  if (not ATrustProxy) or (APeerIP <> '127.0.0.1') or (Length(AForwardedFor) = 0) then"; Replace = "  if Length(AForwardedFor) = 0 then   { sabotagem SB-23 }" }) },
            @{ Id = 'SB-24'; Desc = 'Corpo sem teto em memória (o Indy aloca o tamanho declarado)'; File = 'uHttpApp.pas'; Engine = @();
               Grep = 'OV-16'; Projects = '--project online-lifecycle'; MustFail = @('OV-16');
               Edits = @(
                 @{ Find = "  VPostStream := TCappedStream.Create(MAX_REQUEST_BODY_BYTES);"; Replace = "  { sabotagem SB-24: corpo inteiro na memoria }" }) },
            @{ Id = 'SB-25'; Desc = 'Sem prazo de leitura (conexão parada fica presa)'; File = 'uHttpApp.pas'; Engine = @();
               Grep = 'OV-15b|OV-16'; Projects = '--project online-lifecycle'; MustFail = @('OV-15b', 'OV-16');
               Edits = @(
                 @{ Find = "  AContext.Connection.IOHandler.ReadTimeout := FOptions.HttpTimeoutSeconds * 1000;"; Replace = "  { sabotagem SB-25: sem prazo de leitura }" }) },
            @{ Id = 'SB-26'; Desc = 'Teto do corpo com erro de um byte: exatamente 65.536 bytes já recebe 413'; File = 'uHttpApp.pas'; Engine = @();
               Grep = 'OV-18'; Projects = '--project online-lifecycle'; MustFail = @('OV-18');
               Edits = @(
                 @{ Find = "  if BodySizeOf(ARequestInfo) > MAX_REQUEST_BODY_BYTES then"; Replace = "  if BodySizeOf(ARequestInfo) >= MAX_REQUEST_BODY_BYTES then   { sabotagem SB-26 }" }) },
            @{ Id = 'SB-27'; Desc = 'Teto em memória um byte menor: o corpo de 65.536 bytes chega truncado'; File = 'uHttpApp.pas'; Engine = @();
               Grep = 'OV-18'; Projects = '--project online-lifecycle'; MustFail = @('OV-18');
               Edits = @(
                 @{ Find = "  VPostStream := TCappedStream.Create(MAX_REQUEST_BODY_BYTES);"; Replace = "  VPostStream := TCappedStream.Create(MAX_REQUEST_BODY_BYTES - 1);   { sabotagem SB-27 }" }) }
    )
    foreach ($sb in $sabotages) {
        Write-Log ("----- {0}: {1}" -f $sb.Id, $sb.Desc)
        $dir = Join-Path $LogDir "sabotage\$($sb.Id)-o7"
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
        Write-Log ("EngineCheck sabotado: código {0}; casos que falharam: {1}" -f $er.Code, ($ef -join ', '))
        $sabExe = Join-Path $dir 'bin\TicTacToeServer.exe'
        $sab = Start-Server $sabExe 8766 @('--bind', '127.0.0.1') ("server-o7-" + $sb.Id)
        $r = Invoke-Playwright "npx --no-install playwright test $($sb.Projects) --grep `"$($sb.Grep)`"" @{ PW_EXTERNAL_SERVER = '1'; PW_PORT = '8766'; PW_SERVER_EXE = $sabExe }
        Stop-Server $sab
        $sres = Read-Results
        $failedIds = @()
        if ($sres) { foreach ($t in $sres.Failed) { foreach ($m in [regex]::Matches($t, '(OW|OA|OV|OR|OU)-\d\d[a-c]?')) { $failedIds += $m.Value } } }
        $failedIds = @($failedIds | Sort-Object -Unique)
        $notCaught = @($sb.MustFail | Where-Object { $failedIds -notcontains $_ })
        Write-Log ("Playwright contra o servidor sabotado: código {0}; testes que falharam: {1}; {2}" -f $r.Code, ($failedIds -join ', '), (Format-Results $sres))
        Write-FailureExcerpt $r 16
        if ($null -eq $sb.Engine) {
            $engineOk = $true; $engineMissed = @()
            $engineText = "(EngineCheck da cópia não exigido, como na O2: código $($er.Code))"
        } elseif (@($sb.Engine).Count -gt 0) {
            $engineMissed = @($sb.Engine | Where-Object { $ef -notcontains $_ })
            $engineOk = ($er.Code -eq 1) -and ($engineMissed.Count -eq 0)
            $engineText = "e, no EngineCheck, $($sb.Engine -join ', ')"
        } else {
            $engineMissed = @()
            $engineOk = ($er.Code -eq 0)
            $engineText = '(o EngineCheck da cópia passa: só o servidor real detecta)'
        }
        Add-Check $sb.Id "$($sb.Desc): falham $($sb.MustFail -join ', ') $engineText" (($r.Code -ne 0) -and ($notCaught.Count -eq 0) -and $engineOk) ("Não detectados: " + (($notCaught + $engineMissed) -join ', '))
    }

    # ---- 11. Processos órfãos e portas --------------------------------------
    Write-Log "`n===== 11. Processos órfãos e portas de teste"
    Start-Sleep -Seconds 2
    $orphans = @(Get-ProjectProcesses)
    foreach ($o in $orphans) { Write-Log ("Processo ainda aberto: {0} PID {1}: {2}" -f $o.Name, $o.ProcessId, $o.CommandLine) }
    $busyPorts = @()
    foreach ($port in $TestPorts) {
        $c = & curl.exe -s -o NUL -w '%{http_code}' --max-time 1 "http://127.0.0.1:$port/health" 2>$null
        if ("$c".Trim() -ne '000') { $busyPorts += $port }
    }
    Add-Check 'D-04' "Nenhum processo órfão (TicTacToeServer, EngineCheck, ws-hold, Playwright) e as $($TestPorts.Count) portas de teste livres" (($orphans.Count -eq 0) -and ($busyPorts.Count -eq 0)) ("processos: {0}; portas ocupadas: {1}" -f $orphans.Count, ($busyPorts -join ', '))

    # ---- 12. SHA-256 ------------------------------------------------------
    Write-Log "`n===== 12. SHA-256 dos executáveis e dos arquivos da entrega"
    $hashOut = Join-Path $LogDir 'online-o7-hashes.txt'
    $lines = New-Object System.Collections.ArrayList
    foreach ($exe in @($ServerExe, $EngineExe)) {
        $h = (Get-FileHash -Algorithm SHA256 -Path $exe).Hash
        $info = Get-Item $exe
        Write-Log ("{0}  {1} ({2:N0} bytes, compilado em {3:dd/MM HH:mm})" -f $h, $info.Name, $info.Length, $info.LastWriteTime)
        [void]$lines.Add("$h  server/bin/$($info.Name)")
    }
    foreach ($rel in (@($Hashes.Keys) + $NewFiles + @('tests/playwright.demo.config.ts', 'scripts/demo-playwright-headed.cmd') | Sort-Object -Unique)) {
        $p = Join-Path $Root $rel
        if (Test-Path $p) { [void]$lines.Add(((Get-FileHash -Algorithm SHA256 -Path $p).Hash + "  " + $rel)) }
    }
    [System.IO.File]::WriteAllLines($hashOut, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Log ("{0} SHA-256 gravados em {1}" -f $lines.Count, $hashOut)
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
