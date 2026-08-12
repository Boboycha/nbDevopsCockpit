unit nbTextDocument;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections;

const
  NB_TEXT_DOCUMENT_MAX_BYTES = 5 * 1024 * 1024;

type
  TnbTextEncoding = (teUTF8);
  TnbLineEnding = (leLF, leCRLF);
  TnbTextDocumentChange = (dcContent, dcState, dcMetadata);
  TnbTextDocumentChanges = set of TnbTextDocumentChange;
  TnbTextDocumentChangedEvent = procedure(Sender: TObject;
    AChanges: TnbTextDocumentChanges) of object;

  EnbTextDocumentError = class(Exception);

  TnbTextDocument = class(TComponent)
  private
    FText: string;
    FCleanText: string;
    FIdentity: string;
    FLanguageId: string;
    FEncoding: TnbTextEncoding;
    FHasBOM: Boolean;
    FLineEnding: TnbLineEnding;
    FReadOnly: Boolean;
    FObservers: TList<TnbTextDocumentChangedEvent>;
    function GetModified: Boolean;
    procedure SetText(const AValue: string);
    procedure SetIdentity(const AValue: string);
    procedure SetLanguageId(const AValue: string);
    procedure SetReadOnly(AValue: Boolean);
    procedure SetHasBOM(AValue: Boolean);
    procedure SetLineEnding(AValue: TnbLineEnding);
    procedure Notify(AChanges: TnbTextDocumentChanges);
    class function NormalizeLineEndings(const AText: string): string; static;
    class function SameEvent(const A, B: TnbTextDocumentChangedEvent): Boolean; static;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure NewDocument(const AIdentity: string = '');
    procedure LoadText(const AText: string; AHasBOM: Boolean = False;
      ALineEnding: TnbLineEnding = leLF);
    procedure LoadBytes(const ABytes: TBytes);
    function Encode: TBytes;
    procedure MarkClean;
    procedure Subscribe(const AObserver: TnbTextDocumentChangedEvent);
    procedure Unsubscribe(const AObserver: TnbTextDocumentChangedEvent);
    property Modified: Boolean read GetModified;
  published
    property Text: string read FText write SetText;
    property Identity: string read FIdentity write SetIdentity;
    property LanguageId: string read FLanguageId write SetLanguageId;
    property Encoding: TnbTextEncoding read FEncoding;
    property HasBOM: Boolean read FHasBOM write SetHasBOM default False;
    property LineEnding: TnbLineEnding read FLineEnding write SetLineEnding default leLF;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
  end;

implementation

const
  UTF8_BOM: array[0..2] of Byte = ($EF, $BB, $BF);

constructor TnbTextDocument.Create(AOwner: TComponent);
begin
  inherited;
  FObservers := TList<TnbTextDocumentChangedEvent>.Create;
  FEncoding := teUTF8;
  FLineEnding := leLF;
end;

destructor TnbTextDocument.Destroy;
begin
  FObservers.Free;
  inherited;
end;

class function TnbTextDocument.NormalizeLineEndings(
  const AText: string): string;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10);
end;

class function TnbTextDocument.SameEvent(const A,
  B: TnbTextDocumentChangedEvent): Boolean;
begin
  Result := (TMethod(A).Code = TMethod(B).Code) and
    (TMethod(A).Data = TMethod(B).Data);
end;

procedure TnbTextDocument.Notify(AChanges: TnbTextDocumentChanges);
var
  Observer: TnbTextDocumentChangedEvent;
begin
  for Observer in FObservers.ToArray do
    if Assigned(Observer) then
      Observer(Self, AChanges);
end;

procedure TnbTextDocument.Subscribe(
  const AObserver: TnbTextDocumentChangedEvent);
var
  Observer: TnbTextDocumentChangedEvent;
begin
  if not Assigned(AObserver) then
    Exit;
  for Observer in FObservers do
    if SameEvent(Observer, AObserver) then
      Exit;
  FObservers.Add(AObserver);
end;

procedure TnbTextDocument.Unsubscribe(
  const AObserver: TnbTextDocumentChangedEvent);
var
  I: Integer;
begin
  for I := FObservers.Count - 1 downto 0 do
    if SameEvent(FObservers[I], AObserver) then
      FObservers.Delete(I);
end;

function TnbTextDocument.GetModified: Boolean;
begin
  Result := FText <> FCleanText;
end;

procedure TnbTextDocument.SetText(const AValue: string);
var
  WasModified: Boolean;
  NewText: string;
begin
  if FReadOnly then
    Exit;
  NewText := NormalizeLineEndings(AValue);
  if FText = NewText then
    Exit;
  WasModified := Modified;
  FText := NewText;
  if WasModified <> Modified then
    Notify([dcContent, dcState])
  else
    Notify([dcContent]);
end;

procedure TnbTextDocument.SetIdentity(const AValue: string);
begin
  if FIdentity = AValue then
    Exit;
  FIdentity := AValue;
  Notify([dcMetadata]);
end;

procedure TnbTextDocument.SetLanguageId(const AValue: string);
var
  Value: string;
begin
  Value := LowerCase(Trim(AValue));
  if FLanguageId = Value then
    Exit;
  FLanguageId := Value;
  Notify([dcMetadata]);
end;

procedure TnbTextDocument.SetReadOnly(AValue: Boolean);
begin
  if FReadOnly = AValue then
    Exit;
  FReadOnly := AValue;
  Notify([dcState]);
end;

procedure TnbTextDocument.SetHasBOM(AValue: Boolean);
begin
  if FHasBOM = AValue then
    Exit;
  FHasBOM := AValue;
  Notify([dcMetadata]);
end;

procedure TnbTextDocument.SetLineEnding(AValue: TnbLineEnding);
begin
  if FLineEnding = AValue then
    Exit;
  FLineEnding := AValue;
  Notify([dcMetadata]);
end;

procedure TnbTextDocument.NewDocument(const AIdentity: string);
begin
  FIdentity := AIdentity;
  FText := '';
  FCleanText := '';
  FLanguageId := '';
  FEncoding := teUTF8;
  FHasBOM := False;
  FLineEnding := leLF;
  FReadOnly := False;
  Notify([dcContent, dcState, dcMetadata]);
end;

procedure TnbTextDocument.LoadText(const AText: string; AHasBOM: Boolean;
  ALineEnding: TnbLineEnding);
begin
  FText := NormalizeLineEndings(AText);
  FCleanText := FText;
  FEncoding := teUTF8;
  FHasBOM := AHasBOM;
  FLineEnding := ALineEnding;
  Notify([dcContent, dcState, dcMetadata]);
end;

procedure TnbTextDocument.LoadBytes(const ABytes: TBytes);
var
  Data: TBytes;
  Offset, I: Integer;
  UTF8: TUTF8Encoding;
  Value: string;
  DetectedEnding: TnbLineEnding;
  HasBOM: Boolean;
begin
  if Length(ABytes) > NB_TEXT_DOCUMENT_MAX_BYTES then
    raise EnbTextDocumentError.CreateFmt(
      'Text document exceeds the %d byte limit.',
      [NB_TEXT_DOCUMENT_MAX_BYTES]);

  HasBOM := (Length(ABytes) >= 3) and (ABytes[0] = UTF8_BOM[0]) and
    (ABytes[1] = UTF8_BOM[1]) and (ABytes[2] = UTF8_BOM[2]);
  if HasBOM then
    Offset := 3
  else
    Offset := 0;

  SetLength(Data, Length(ABytes) - Offset);
  if Length(Data) > 0 then
    Move(ABytes[Offset], Data[0], Length(Data));

  for I := 0 to High(Data) do
    if Data[I] = 0 then
      raise EnbTextDocumentError.Create('The file contains NUL bytes.');

  DetectedEnding := leLF;
  for I := 0 to Length(Data) - 2 do
    if (Data[I] = 13) and (Data[I + 1] = 10) then
    begin
      DetectedEnding := leCRLF;
      Break;
    end;

  UTF8 := TUTF8Encoding.Create(False);
  try
    if (Length(Data) > 0) and
      not UTF8.IsBufferValid(@Data[0], Length(Data)) then
      raise EnbTextDocumentError.Create('The file is not valid UTF-8.');
    try
      Value := UTF8.GetString(Data);
    except
      on E: EEncodingError do
        raise EnbTextDocumentError.Create('The file is not valid UTF-8.');
    end;
  finally
    UTF8.Free;
  end;
  LoadText(Value, HasBOM, DetectedEnding);
end;

function TnbTextDocument.Encode: TBytes;
var
  Value: string;
  Data: TBytes;
  Offset: Integer;
  UTF8: TUTF8Encoding;
begin
  Value := FText;
  if FLineEnding = leCRLF then
    Value := Value.Replace(#10, #13#10);

  UTF8 := TUTF8Encoding.Create(False);
  try
    Data := UTF8.GetBytes(Value);
  finally
    UTF8.Free;
  end;

  if FHasBOM then
  begin
    SetLength(Result, Length(Data) + 3);
    Result[0] := UTF8_BOM[0];
    Result[1] := UTF8_BOM[1];
    Result[2] := UTF8_BOM[2];
    Offset := 3;
  end
  else
  begin
    SetLength(Result, Length(Data));
    Offset := 0;
  end;
  if Length(Data) > 0 then
    Move(Data[0], Result[Offset], Length(Data));
end;

procedure TnbTextDocument.MarkClean;
begin
  if not Modified then
    Exit;
  FCleanText := FText;
  Notify([dcState]);
end;

end.