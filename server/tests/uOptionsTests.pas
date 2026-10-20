unit uOptionsTests;

{ Casos OP-01 (Entrega O2) e OP-02 (Entrega O3) do docs/test-plan-online.md:
  leitura da linha de comando (uServerOptions), sem iniciar servidor. O OP-01
  continua identico ao aprovado na O2. }

interface

procedure RunOptionsTests;

implementation

uses
  System.SysUtils, uMiniTest, uServerOptions;

const
  WEB = 'C:\jogo\web';

function Parse(const AArgs: array of string; out AOptions: TServerOptions; out AError: string): Boolean;
begin
  Result := ParseServerOptions(AArgs, WEB, AOptions, AError);
end;

procedure ExpectOk(const AArgs: array of string; const AWhat: string; out AOptions: TServerOptions);
var
  Error: string;
begin
  Check(Parse(AArgs, AOptions, Error), AWhat + ': deveria ser aceito; erro: ' + Error);
end;

procedure ExpectRejected(const AArgs: array of string; const AWhat: string);
var
  Options: TServerOptions;
  Error: string;
  Ok: Boolean;
begin
  Ok := Parse(AArgs, Options, Error);
  Check(not Ok, AWhat + ': deveria ser recusado');
  if not Ok then
  begin
    Check(Error <> '', AWhat + ': mensagem de erro vazia');
    { Em erro, as opcoes voltam com os padroes (nada pela metade). }
    CheckEqualsStr(DEFAULT_BIND, Options.BindIP, AWhat + ': bind depois do erro');
    CheckEqualsInt(DEFAULT_PORT, Options.Port, AWhat + ': porta depois do erro');
  end;
end;

procedure OP01_Options;
var
  O: TServerOptions;
begin
  { Sem argumentos: padroes da secao 11.4 do plano. }
  ExpectOk([], 'sem argumentos', O);
  CheckEqualsInt(8765, O.Port, 'porta padrao');
  CheckEqualsStr(WEB, O.WebRoot, 'pasta padrao');
  CheckEqualsStr('0.0.0.0', O.BindIP, 'bind padrao');
  Check(not O.BindExplicit, 'bind padrao nao e explicito');
  Check(not O.PublicMode, 'modo publico desligado');
  CheckEqualsInt(600, O.RoomTtlSeconds, 'room-ttl-seconds padrao');
  CheckEqualsInt(3600, O.RememberSeconds, 'remember-seconds padrao');
  CheckEqualsInt(5000, O.SweepMs, 'sweep-ms padrao');
  CheckEqualsInt(500, O.MaxRooms, 'max-rooms padrao');
  CheckEqualsInt(256, O.MaxConnections, 'max-connections padrao');

  ExpectOk(['--bind', '127.0.0.1'], '--bind 127.0.0.1', O);
  CheckEqualsStr('127.0.0.1', O.BindIP, '--bind 127.0.0.1');
  Check(O.BindExplicit, '--bind informado');

  ExpectOk(['--public'], '--public', O);
  CheckEqualsStr('127.0.0.1', O.BindIP, '--public sem --bind');
  Check(O.PublicMode, '--public liga o modo publico');

  ExpectOk(['--public', '--bind', '0.0.0.0'], '--public --bind 0.0.0.0', O);
  CheckEqualsStr('0.0.0.0', O.BindIP, '--public --bind 0.0.0.0');
  ExpectOk(['--bind', '0.0.0.0', '--public'], '--bind 0.0.0.0 --public', O);
  CheckEqualsStr('0.0.0.0', O.BindIP, '--bind antes de --public');

  ExpectOk(['--bind', '192.168.0.10'], '--bind IP da rede local', O);
  CheckEqualsStr('192.168.0.10', O.BindIP, '--bind 192.168.0.10');

  ExpectOk(['--PORT', '9000', '--www', 'D:\outra\web', '--room-ttl-seconds', '30',
    '--remember-seconds', '0', '--sweep-ms', '100', '--max-rooms', '3',
    '--max-connections', '64'], 'todas as opcoes', O);
  CheckEqualsInt(9000, O.Port, '--port (nome sem distincao de maiusculas)');
  CheckEqualsStr('D:\outra\web', O.WebRoot, '--www');
  CheckEqualsInt(30, O.RoomTtlSeconds, '--room-ttl-seconds');
  CheckEqualsInt(0, O.RememberSeconds, '--remember-seconds 0');
  CheckEqualsInt(100, O.SweepMs, '--sweep-ms');
  CheckEqualsInt(3, O.MaxRooms, '--max-rooms');
  CheckEqualsInt(64, O.MaxConnections, '--max-connections');
  CheckEqualsStr('0.0.0.0', O.BindIP, 'bind continua o padrao');

  ExpectOk(['--port', '1'], 'porta 1', O);
  ExpectOk(['--port', '65535'], 'porta 65535', O);
  ExpectOk(['--port', '8000', '--port', '8001'], 'opcao repetida', O);
  CheckEqualsInt(8001, O.Port, 'opcao repetida vale a ultima');

  { Valores invalidos. }
  ExpectRejected(['--port', '0'], 'porta 0');
  ExpectRejected(['--port', '65536'], 'porta 65536');
  ExpectRejected(['--port', 'abc'], 'porta texto');
  ExpectRejected(['--port', '-1'], 'porta negativa');
  ExpectRejected(['--port', '+80'], 'porta com sinal');
  ExpectRejected(['--port'], 'porta sem valor');
  ExpectRejected(['--port', '--public'], 'porta seguida de outra opcao');
  ExpectRejected(['--room-ttl-seconds', '-5'], 'TTL negativo');
  ExpectRejected(['--room-ttl-seconds', '0'], 'TTL zero');
  ExpectRejected(['--remember-seconds', '-1'], 'lembranca negativa');
  ExpectRejected(['--sweep-ms', '5'], 'sweep-ms abaixo de 10');
  ExpectRejected(['--max-rooms', '0'], 'max-rooms zero');
  ExpectRejected(['--max-connections', '0'], 'max-connections zero');
  ExpectRejected(['--max-rooms', '99999999999'], 'max-rooms grande demais');
  ExpectRejected(['--bind'], 'bind sem valor');
  ExpectRejected(['--bind', 'localhost'], 'bind com nome');
  ExpectRejected(['--bind', '256.0.0.1'], 'bind com octeto 256');
  ExpectRejected(['--bind', '127.0.0'], 'bind com 3 octetos');
  ExpectRejected(['--bind', '127.0.0.1.5'], 'bind com 5 octetos');
  ExpectRejected(['--bind', '127.0.0.01'], 'bind com zero a esquerda');
  ExpectRejected(['--bind', ' 127.0.0.1'], 'bind com espaco');
  ExpectRejected(['--bind', '::1'], 'bind IPv6');
  ExpectRejected(['--bind', '127..0.1'], 'bind com octeto vazio');
  ExpectRejected(['--www'], 'www sem valor');
  ExpectRejected(['--bnd', '127.0.0.1'], 'opcao desconhecida');
  ExpectRejected(['127.0.0.1'], 'valor solto');

  Check(IsValidIPv4('0.0.0.0') and IsValidIPv4('255.255.255.255') and IsValidIPv4('10.0.0.1'),
    'IsValidIPv4 aceita enderecos validos');
end;

{ OP-02 (Entrega O3): opcoes do canal e da politica de origem (secao 7.7). }
procedure ExpectInvalidCombination(const AArgs: array of string; const AWhat: string);
var
  O: TServerOptions;
  Error: string;
begin
  Check(Parse(AArgs, O, Error), AWhat + ': a leitura deveria aceitar; erro: ' + Error);
  Check(not ValidateServerOptions(O, Error), AWhat + ': a validacao deveria recusar');
  Check(Error <> '', AWhat + ': mensagem de erro vazia');
end;

procedure OP02_ChannelOptions;
var
  O: TServerOptions;
  Error: string;
begin
  ExpectOk([], 'sem argumentos', O);
  CheckEqualsInt(5, O.WsHelloSeconds, 'ws-hello-seconds padrao');
  CheckEqualsInt(60, O.WsIdleSeconds, 'ws-idle-seconds padrao');
  CheckEqualsInt(0, Length(O.AllowedOrigins), 'nenhuma --allowed-origin padrao');
  Check(ValidateServerOptions(O, Error), 'padroes validos: ' + Error);

  ExpectOk(['--allowed-origin', 'http://desktop-ruan:8765,HTTP://Exemplo.TEST',
    '--allowed-origin', 'https://jogo.test:8443', '--ws-hello-seconds', '2', '--ws-idle-seconds', '3'],
    '--allowed-origin repetida e com virgula; --ws-*', O);
  CheckEqualsInt(3, Length(O.AllowedOrigins), 'tres origens configuradas');
  if Length(O.AllowedOrigins) = 3 then
  begin
    CheckEqualsStr('http://desktop-ruan:8765', O.AllowedOrigins[0], 'origem 1');
    CheckEqualsStr('http://exemplo.test:80', O.AllowedOrigins[1], 'origem 2 normalizada');
    CheckEqualsStr('https://jogo.test:8443', O.AllowedOrigins[2], 'origem 3');
  end;
  CheckEqualsInt(2, O.WsHelloSeconds, '--ws-hello-seconds');
  CheckEqualsInt(3, O.WsIdleSeconds, '--ws-idle-seconds');
  Check(ValidateServerOptions(O, Error), 'modo local aceita origem http configurada: ' + Error);

  { Modo publico: pelo menos uma origem, todas https (DTO-17). }
  ExpectOk(['--public', '--allowed-origin', 'https://jogo.exemplo.com.br'], '--public com https', O);
  CheckEqualsStr('127.0.0.1', O.BindIP, '--public sem --bind');
  Check((Length(O.AllowedOrigins) = 1) and (O.AllowedOrigins[0] = 'https://jogo.exemplo.com.br:443'),
    '--allowed-origin na forma canonica (porta 443 explicita)');
  Check(ValidateServerOptions(O, Error), '--public com https valido: ' + Error);
  ExpectInvalidCombination(['--public'], '--public sem --allowed-origin');
  ExpectInvalidCombination(['--public', '--allowed-origin', 'http://jogo.test'], '--public com origem http');
  ExpectInvalidCombination(['--public', '--allowed-origin', 'https://jogo.test,http://outro.test'],
    '--public com uma origem http entre outras https');

  ExpectRejected(['--allowed-origin'], '--allowed-origin sem valor');
  ExpectRejected(['--allowed-origin', 'http://jogo.test/'], '--allowed-origin com caminho');
  ExpectRejected(['--allowed-origin', 'jogo.test'], '--allowed-origin sem esquema');
  ExpectRejected(['--allowed-origin', 'ftp://jogo.test'], '--allowed-origin ftp');
  ExpectRejected(['--allowed-origin', 'http://jogo.test:0'], '--allowed-origin porta 0');
  ExpectRejected(['--allowed-origin', 'null'], '--allowed-origin null');
  ExpectRejected(['--ws-hello-seconds', '0'], 'ws-hello-seconds 0');
  ExpectRejected(['--ws-idle-seconds', '1'], 'ws-idle-seconds 1');
end;

procedure RunOptionsTests;
begin
  RunCase('OP-01', 'Opcoes da linha de comando: padroes, --bind, --public e valores invalidos', OP01_Options);
  RunCase('OP-02', 'Opcoes do canal e da politica de origem: --allowed-origin, --ws-*, modo publico', OP02_ChannelOptions);
end;

end.
