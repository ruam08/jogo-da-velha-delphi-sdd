unit uSecureRandom;

{ Gerador aleatorio criptograficamente seguro e formatos de token e de codigo
  de sala (docs/plan-online.md, DTO-07 e DTO-08).
  - TSystemRandom usa BCryptGenRandom do Windows (bcrypt.dll, Vista+).
  - IRandomSource pode ser substituido nos testes por uma sequencia fixa.
  Sem dependencia de Indy, HTTP ou JSON. }

interface

uses
  System.SysUtils;

const
  { 31 simbolos, sem 0, 1, I, L e O (spec-online 5.1). }
  ROOM_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  ROOM_CODE_LENGTH = 6;
  TOKEN_BYTES = 16;              { 128 bits }
  TOKEN_LENGTH = 2 * TOKEN_BYTES; { 32 caracteres hexadecimais minusculos }

type
  ERandomFailure = class(Exception);

  IRandomSource = interface
    ['{0F7D9E21-5A3B-4C88-A1D6-2E94B7C3F015}']
    { Preenche todo o ABuffer com bytes aleatorios. }
    procedure Fill(var ABuffer: TBytes);
  end;

  TSystemRandom = class(TInterfacedObject, IRandomSource)
  public
    procedure Fill(var ABuffer: TBytes);
  end;

{ 32 caracteres 0-9a-f a partir de 16 bytes aleatorios. }
function NewToken(const ARandom: IRandomSource): string;
{ 6 caracteres de ROOM_CODE_ALPHABET, com distribuicao uniforme
  (bytes >= 248 sao descartados: 248 = 8 x 31). }
function NewRoomCode(const ARandom: IRandomSource): string;
function IsValidRoomCode(const ACode: string): Boolean;
{ Tira espacos das pontas e passa para maiusculas (RNO-03). }
function NormalizeRoomCode(const ACode: string): string;
function IsValidTokenFormat(const AToken: string): Boolean;

implementation

uses
  Winapi.Windows;

const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;

function BCryptGenRandom(hAlgorithm: Pointer; pbBuffer: PByte; cbBuffer: ULONG;
  dwFlags: ULONG): LongInt; stdcall; external 'bcrypt.dll' name 'BCryptGenRandom';

{ TSystemRandom }

procedure TSystemRandom.Fill(var ABuffer: TBytes);
var
  Status: LongInt;
begin
  if Length(ABuffer) = 0 then
    Exit;
  Status := BCryptGenRandom(nil, @ABuffer[0], ULONG(Length(ABuffer)),
    BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  if Status <> 0 then
    raise ERandomFailure.CreateFmt('BCryptGenRandom falhou (status %d)', [Status]);
end;

{ Funcoes }

function NewToken(const ARandom: IRandomSource): string;
const
  HEX: string = '0123456789abcdef';
var
  Raw: TBytes;
  I: Integer;
begin
  SetLength(Raw, TOKEN_BYTES);
  ARandom.Fill(Raw);
  SetLength(Result, TOKEN_LENGTH);
  for I := 0 to TOKEN_BYTES - 1 do
  begin
    Result[2 * I + 1] := HEX[(Raw[I] shr 4) + 1];
    Result[2 * I + 2] := HEX[(Raw[I] and $0F) + 1];
  end;
end;

function NewRoomCode(const ARandom: IRandomSource): string;
var
  Raw: TBytes;
  I, Filled: Integer;
begin
  Result := '';
  Filled := 0;
  SetLength(Raw, 16);
  while Filled < ROOM_CODE_LENGTH do
  begin
    ARandom.Fill(Raw);
    for I := 0 to High(Raw) do
      if (Raw[I] < 248) and (Filled < ROOM_CODE_LENGTH) then
      begin
        Result := Result + ROOM_CODE_ALPHABET[(Raw[I] mod 31) + 1];
        Inc(Filled);
      end;
  end;
end;

function IsValidRoomCode(const ACode: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(ACode) <> ROOM_CODE_LENGTH then
    Exit;
  for I := 1 to Length(ACode) do
    if Pos(ACode[I], ROOM_CODE_ALPHABET) = 0 then
      Exit;
  Result := True;
end;

function NormalizeRoomCode(const ACode: string): string;
begin
  Result := UpperCase(Trim(ACode));
end;

function IsValidTokenFormat(const AToken: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Length(AToken) <> TOKEN_LENGTH then
    Exit;
  for I := 1 to Length(AToken) do
    if not CharInSet(AToken[I], ['0'..'9', 'a'..'f']) then
      Exit;
  Result := True;
end;

end.
