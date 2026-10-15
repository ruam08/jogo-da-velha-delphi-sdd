unit uHttpApp;

(* Servidor HTTP do jogo, baseado no TIdHTTPServer do Indy 10 que acompanha
  o Delphi 10.1 Berlin. Contrato: docs/plan.md, seção 3.

  Esta unit só traduz HTTP <-> serviço:
  - regras e estado ficam em uGameEngine / uGameService;
  - JSON fica em uGameJson.

  Rotas:
    GET|HEAD /health            -> 200 {"status":"ok"}
    GET|HEAD /api/game          -> 200 estado
    POST     /api/game/moves    -> 200 estado | 400 | 409
    POST     /api/game/reset    -> 200 estado inicial
    GET|HEAD /, /index.html, /style.css, /app.js -> arquivos da pasta --www
    método errado em rota conhecida -> 405 com Allow
    qualquer outra rota         -> 404 JSON (DT-21) *)

interface

uses
  System.SysUtils, System.Classes,
  IdContext, IdCustomHTTPServer, IdHTTPServer,
  uGameService;

type
  TGameHttpServer = class
  private
    FServer: TIdHTTPServer;
    FService: TGameService;
    FPort: Word;
    FWebRoot: string;
    procedure HandleCommand(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure Route(const AMethod, APath: string;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleHealth(const AMethod: string; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleGetState(const AMethod: string; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleMove(const AMethod: string; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleReset(const AMethod: string; AResponseInfo: TIdHTTPResponseInfo);
    procedure HandleStatic(const AMethod, AFileName, AContentType: string;
      AResponseInfo: TIdHTTPResponseInfo);
  public
    { AWebRoot: pasta com index.html, style.css e app.js. }
    constructor Create(APort: Word; const AWebRoot: string);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Port: Word read FPort;
    property WebRoot: string read FWebRoot;
  end;

implementation

uses
  System.IOUtils, IdGlobal, IdSocketHandle, uConsoleLog, uGameEngine, uGameJson;

const
  ALLOW_GET_HEAD = 'GET, HEAD';
  ALLOW_POST = 'POST';

{ ---- Montagem de respostas ---------------------------------------------- }

{ Grava o corpo como bytes em ContentStream.
  Usar ContentText deixaria a codificação a cargo do Indy, que pode trocar
  acentos por "?" (RNF-08, DT-08). O Indy libera o ContentStream sozinho e
  não envia o corpo em respostas a HEAD. }
procedure WriteBytes(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer;
  const AContentType, ACacheControl: string; const ABytes: TBytes);
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    if Length(ABytes) > 0 then
      Stream.WriteBuffer(ABytes[0], Length(ABytes));
    Stream.Position := 0;
  except
    Stream.Free;
    raise;
  end;
  AResponseInfo.ResponseNo := AStatus;
  AResponseInfo.ContentType := AContentType;
  AResponseInfo.CharSet := 'utf-8';
  AResponseInfo.CustomHeaders.Values['Cache-Control'] := ACacheControl;
  AResponseInfo.ContentStream := Stream;
  AResponseInfo.ContentLength := Stream.Size;
end;

procedure WriteJson(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer;
  const AJson: string);
begin
  WriteBytes(AResponseInfo, AStatus, 'application/json', 'no-store',
    TEncoding.UTF8.GetBytes(AJson));
end;

{ Lista fixa de arquivos estáticos (DT-04): nada fora dela é servido, o que
  dispensa qualquer tratamento de caminhos como "/../". }
function FindStaticFile(const APath: string; out AFileName, AContentType: string): Boolean;
begin
  Result := True;
  if (APath = '/') or (APath = '/index.html') then
  begin
    AFileName := 'index.html';
    AContentType := 'text/html';
  end
  else if APath = '/style.css' then
  begin
    AFileName := 'style.css';
    AContentType := 'text/css';
  end
  else if APath = '/app.js' then
  begin
    AFileName := 'app.js';
    AContentType := 'text/javascript';
  end
  else
    Result := False;
end;

procedure WriteError(AResponseInfo: TIdHTTPResponseInfo; AStatus: Integer;
  const ACode, AMessage: string);
begin
  WriteJson(AResponseInfo, AStatus, ErrorToJson(ACode, AMessage));
end;

procedure WriteState(AResponseInfo: TIdHTTPResponseInfo; const AState: TGameSnapshot);
begin
  WriteJson(AResponseInfo, 200, SnapshotToJson(AState));
end;

procedure WriteMethodNotAllowed(AResponseInfo: TIdHTTPResponseInfo;
  const AAllow: string);
begin
  WriteError(AResponseInfo, 405, ERR_METHOD_NOT_ALLOWED, MSG_METHOD_NOT_ALLOWED);
  AResponseInfo.CustomHeaders.Values['Allow'] := AAllow;
end;

{ Lê o corpo da requisição como bytes. PostStream é nil quando não há corpo. }
function ReadBody(ARequestInfo: TIdHTTPRequestInfo): TBytes;
var
  Stream: TStream;
begin
  Result := nil;
  Stream := ARequestInfo.PostStream;
  if (Stream = nil) or (Stream.Size = 0) then
    Exit;
  Stream.Position := 0;
  SetLength(Result, Stream.Size);
  Stream.ReadBuffer(Result[0], Length(Result));
end;

{ ---- TGameHttpServer ----------------------------------------------------- }

constructor TGameHttpServer.Create(APort: Word; const AWebRoot: string);
var
  Binding: TIdSocketHandle;
begin
  inherited Create;
  FPort := APort;
  FWebRoot := AWebRoot;
  FService := TGameService.Create;
  FServer := TIdHTTPServer.Create(nil);
  FServer.DefaultPort := APort;
  { Escuta somente em 127.0.0.1 (RNF-04). Sem um Binding explícito o Indy
    escutaria em todas as interfaces. }
  FServer.Bindings.Clear;
  Binding := FServer.Bindings.Add;
  Binding.IP := '127.0.0.1';
  Binding.Port := APort;
  Binding.IPVersion := Id_IPv4;
  FServer.KeepAlive := False;
  FServer.ServerSoftware := 'JogoDaVelha';
  { GET, POST e HEAD chegam em OnCommandGet; PUT, DELETE e os demais
    métodos chegam em OnCommandOther. Os dois vão para o mesmo roteador. }
  FServer.OnCommandGet := HandleCommand;
  FServer.OnCommandOther := HandleCommand;
end;

destructor TGameHttpServer.Destroy;
begin
  Stop;
  FServer.Free;
  FService.Free;
  inherited;
end;

procedure TGameHttpServer.Start;
begin
  FServer.Active := True;
end;

procedure TGameHttpServer.Stop;
begin
  { Deve ser chamado pela thread principal, nunca de dentro de um evento
    do Indy, para não travar à espera da própria thread. }
  if FServer.Active then
    FServer.Active := False;
end;

procedure TGameHttpServer.HandleCommand(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Method, Path: string;
begin
  Method := UpperCase(ARequestInfo.Command);
  Path := ARequestInfo.Document;
  try
    Route(Method, Path, ARequestInfo, AResponseInfo);
  except
    on E: Exception do
    begin
      Log('ERRO em %s %s: %s: %s', [Method, Path, E.ClassName, E.Message]);
      AResponseInfo.CustomHeaders.Clear;
      WriteError(AResponseInfo, 500, ERR_INTERNAL, MSG_INTERNAL);
    end;
  end;
  Log('%s %s -> %d', [Method, Path, AResponseInfo.ResponseNo]);
end;

procedure TGameHttpServer.Route(const AMethod, APath: string;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  FileName, ContentType: string;
begin
  if APath = '/health' then
    HandleHealth(AMethod, AResponseInfo)
  else if APath = '/api/game' then
    HandleGetState(AMethod, AResponseInfo)
  else if APath = '/api/game/moves' then
    HandleMove(AMethod, ARequestInfo, AResponseInfo)
  else if APath = '/api/game/reset' then
    HandleReset(AMethod, AResponseInfo)
  else if FindStaticFile(APath, FileName, ContentType) then
    HandleStatic(AMethod, FileName, ContentType, AResponseInfo)
  else
    WriteError(AResponseInfo, 404, ERR_ROUTE_NOT_FOUND, MSG_ROUTE_NOT_FOUND);
end;

procedure TGameHttpServer.HandleHealth(const AMethod: string;
  AResponseInfo: TIdHTTPResponseInfo);
begin
  if (AMethod <> 'GET') and (AMethod <> 'HEAD') then
    WriteMethodNotAllowed(AResponseInfo, ALLOW_GET_HEAD)
  else
    WriteJson(AResponseInfo, 200, '{"status":"ok"}');
end;

procedure TGameHttpServer.HandleGetState(const AMethod: string;
  AResponseInfo: TIdHTTPResponseInfo);
begin
  if (AMethod <> 'GET') and (AMethod <> 'HEAD') then
    WriteMethodNotAllowed(AResponseInfo, ALLOW_GET_HEAD)
  else
    WriteState(AResponseInfo, FService.GetState);
end;

procedure TGameHttpServer.HandleMove(const AMethod: string;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Position: Integer;
  Outcome: TPlayOutcome;
begin
  if AMethod <> 'POST' then
  begin
    WriteMethodNotAllowed(AResponseInfo, ALLOW_POST);
    Exit;
  end;

  { Ordem de validação da RN-15: corpo -> posição inteira -> (no motor)
    intervalo -> partida em andamento -> célula vazia. }
  case ParseMoveBody(ReadBody(ARequestInfo), Position) of
    mbInvalidBody:
      begin
        WriteError(AResponseInfo, 400, ERR_INVALID_BODY, MSG_INVALID_BODY);
        Exit;
      end;
    mbInvalidPosition:
      begin
        WriteError(AResponseInfo, 400, ERR_INVALID_POSITION, MSG_INVALID_POSITION);
        Exit;
      end;
  end;

  Outcome := FService.Play(Position);
  case Outcome.MoveResult of
    mrAccepted:
      WriteState(AResponseInfo, Outcome.State);
    mrInvalidPosition:
      WriteError(AResponseInfo, 400, ERR_INVALID_POSITION, MSG_INVALID_POSITION);
    mrGameOver:
      WriteError(AResponseInfo, 409, ERR_GAME_OVER, MSG_GAME_OVER);
    mrCellOccupied:
      WriteError(AResponseInfo, 409, ERR_CELL_OCCUPIED, MSG_CELL_OCCUPIED);
  end;
end;

procedure TGameHttpServer.HandleReset(const AMethod: string;
  AResponseInfo: TIdHTTPResponseInfo);
begin
  if AMethod <> 'POST' then
    WriteMethodNotAllowed(AResponseInfo, ALLOW_POST)
  else
    { O corpo, se existir, é ignorado (plano 3.3). }
    WriteState(AResponseInfo, FService.Reset);
end;

procedure TGameHttpServer.HandleStatic(const AMethod, AFileName,
  AContentType: string; AResponseInfo: TIdHTTPResponseInfo);
var
  FullPath: string;
begin
  if (AMethod <> 'GET') and (AMethod <> 'HEAD') then
  begin
    WriteMethodNotAllowed(AResponseInfo, ALLOW_GET_HEAD);
    Exit;
  end;
  { Lido do disco a cada requisição: editar a interface não exige recompilar. }
  FullPath := TPath.Combine(FWebRoot, AFileName);
  if not TFile.Exists(FullPath) then
  begin
    Log('AVISO: arquivo estático ausente: %s', [FullPath]);
    WriteError(AResponseInfo, 404, ERR_ROUTE_NOT_FOUND, MSG_ROUTE_NOT_FOUND);
    Exit;
  end;
  { no-cache: o navegador revalida e sempre usa a versão atual. }
  WriteBytes(AResponseInfo, 200, AContentType, 'no-cache', TFile.ReadAllBytes(FullPath));
end;

end.
