unit Terminal.Types;

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Types, Terminal.Theme;

type
  TTerminalColorSource = (tcsDefault, tcsAnsi, tcsIndexed, tcsRGB);

  // Атрибуты символа
  TCharAttributes = record
    Bold: Boolean;
    Faint: Boolean;
    Italic: Boolean;
    Underline: Boolean;
    Blink: Boolean;
    Inverse: Boolean;
    Hidden: Boolean;
    Strikethrough: Boolean;
    ForegroundColor: TAlphaColor;
    BackgroundColor: TAlphaColor;
    ForegroundSource: TTerminalColorSource;
    BackgroundSource: TTerminalColorSource;
    ForegroundIndex: Byte;
    BackgroundIndex: Byte;
    procedure Reset(ATheme: TTerminalTheme);
    class function Default(ATheme: TTerminalTheme): TCharAttributes; static;
  end;

  // Символ в терминале
  // Храним STRING, чтобы вмещать суррогатные пары и ZWJ
  TTerminalChar = record
    Char: string;
    Attributes: TCharAttributes;
    Width: Byte;  // 0 = продолжение wide-символа, 1 = обычный, 2 = wide
  end;

  TTerminalCells = array of TTerminalChar;

  // Физическая строка экрана. IsWrapped означает, что следующая строка
  // является продолжением этой же логической строки (soft wrap), а не
  // результатом CR/LF. Без этого метаданных корректный reflow невозможен.
  TTerminalLine = record
    Cells: TTerminalCells;
    IsWrapped: Boolean;
  end;

  TTerminalCursorShape = (tcsBlock, tcsUnderline, tcsBar);

  TTerminalCursor = record
    X: Integer;
    Y: Integer;
    Visible: Boolean;
    Shape: TTerminalCursorShape;
    Blink: Boolean;
  end;

  TMouseTrackingMode = (
    mtm1000_Click,
    mtm1002_Wheel,
    mtm1003_Any,
    mtm1006_SGR
  );
  TMouseTrackingModes = set of TMouseTrackingMode;

  // Функции псевдографики
  function IsBoxDrawingChar(const C: string): Boolean;
  function IsVerticalLine(const C: string): Boolean;
  function IsHorizontalLine(const C: string): Boolean;
  
  // Определение ширины символа (1 или 2 колонки)
  function GetCharDisplayWidth(const Ch: string): Integer;
  
  // Проверка на Zero-Width символы (ZWJ, variation selectors и т.д.)
  function IsZeroWidthChar(const Ch: string): Boolean;

  // Является ли графема настоящим эмодзи (а не, например, CJK-иероглифом).
  // Нужно чтобы отрисовывать эмодзи цветным emoji-шрифтом, а CJK - обычным.
  function IsEmojiChar(const Ch: string): Boolean;

implementation

uses
  System.Math, System.Character;

type
  TCodePointRange = record
    First, Last: Cardinal;
  end;

const
  CWideRanges: array[0..20] of TCodePointRange = (
    (First: $1100; Last: $115F), (First: $11A3; Last: $11A7),
    (First: $11FA; Last: $11FF), (First: $2300; Last: $23FF),
    (First: $2600; Last: $27BF), (First: $2E80; Last: $2EFF),
    (First: $2F00; Last: $2FDF), (First: $3000; Last: $30FF),
    (First: $3100; Last: $33FF), (First: $3400; Last: $4DBF),
    (First: $4E00; Last: $9FFF), (First: $A000; Last: $A4CF),
    (First: $AC00; Last: $D7AF), (First: $F900; Last: $FAFF),
    (First: $FE10; Last: $FE1F), (First: $FE30; Last: $FE4F),
    (First: $FF00; Last: $FF60), (First: $FFE0; Last: $FFE6),
    (First: $1F300; Last: $1FAFF),
    (First: $20000; Last: $2FFFD),
    (First: $30000; Last: $3FFFD));
  CEmojiRanges: array[0..4] of TCodePointRange = (
    (First: $203C; Last: $203C), (First: $2049; Last: $2049),
    (First: $2600; Last: $27BF), (First: $2B00; Last: $2BFF),
    (First: $1F000; Last: $1FAFF));

function InCodePointRanges(Code: Cardinal;
  const Ranges: array of TCodePointRange): Boolean;
var
  L, H, M: Integer;
begin
  L := 0;
  H := High(Ranges);
  while L <= H do
  begin
    M := L + (H - L) div 2;
    if Code < Ranges[M].First then
      H := M - 1
    else if Code > Ranges[M].Last then
      L := M + 1
    else
      Exit(True);
  end;
  Result := False;
end;

{ TCharAttributes }

procedure TCharAttributes.Reset(ATheme: TTerminalTheme);
begin
  Bold := False;
  Faint := False;
  Italic := False;
  Underline := False;
  Blink := False;
  Inverse := False;
  Hidden := False;
  Strikethrough := False;
  ForegroundColor := ATheme.DefaultFG;
  BackgroundColor := ATheme.DefaultBG;
  ForegroundSource := tcsDefault;
  BackgroundSource := tcsDefault;
  ForegroundIndex := 0;
  BackgroundIndex := 0;
end;

class function TCharAttributes.Default(ATheme: TTerminalTheme): TCharAttributes;
begin
  Result.Reset(ATheme);
end;

// --- ОПРЕДЕЛЕНИЕ ШИРИНЫ СИМВОЛА ---

function GetCodePoint(const Ch: string): Cardinal;
begin
  Result := 0;
  if Length(Ch) = 0 then Exit;
  
  // Суррогатная пара (эмодзи, редкие символы > U+FFFF)
  if (Length(Ch) >= 2) and 
     (Ord(Ch[1]) >= $D800) and (Ord(Ch[1]) <= $DBFF) and
     (Ord(Ch[2]) >= $DC00) and (Ord(Ch[2]) <= $DFFF) then
    Result := $10000 + ((Ord(Ch[1]) - $D800) shl 10) + (Ord(Ch[2]) - $DC00)
  else
    Result := Ord(Ch[1]);
end;

function IsZeroWidthChar(const Ch: string): Boolean;
var
  Code: Cardinal;
  Category: TUnicodeCategory;
begin
  if Length(Ch) = 0 then Exit(True);
  
  Code := GetCodePoint(Ch);
  Category := Char.GetUnicodeCategory(UCS4Char(Code));
  
  Result := (Category in [TUnicodeCategory.ucCombiningMark,
    TUnicodeCategory.ucEnclosingMark, TUnicodeCategory.ucNonSpacingMark])
    or
    (Code = $200B) or  // Zero Width Space
    (Code = $200C) or  // Zero Width Non-Joiner
    (Code = $200D) or  // Zero Width Joiner (ZWJ)
    (Code = $2060) or  // Word Joiner
    (Code = $FEFF) or  // BOM / Zero Width No-Break Space
    ((Code >= $FE00) and (Code <= $FE0F)) or  // Variation Selectors
    ((Code >= $E0100) and (Code <= $E01EF));  // Variation Selectors Supplement
end;

function IsEmojiChar(const Ch: string): Boolean;
var
  Code: Cardinal;
  I: Integer;
begin
  if Length(Ch) = 0 then Exit(False);

  // Наличие ZWJ или VS16 в графеме - однозначный признак emoji-последовательности
  for I := 1 to Length(Ch) do
    if (Ord(Ch[I]) = $200D) or (Ord(Ch[I]) = $FE0F) then
      Exit(True);

  Code := GetCodePoint(Ch);

  Result := InCodePointRanges(Code, CEmojiRanges);
end;

function GetCharDisplayWidth(const Ch: string): Integer;
var
  Code: Cardinal;
  I: Integer;
begin
  if Length(Ch) = 0 then Exit(0);

  if Length(Ch) > 1 then
    for I := 1 to Length(Ch) do
      if (Ord(Ch[I]) = $200D) or (Ord(Ch[I]) = $FE0F) then
        Exit(2);
  
  Code := GetCodePoint(Ch);
  
  // Zero-width
  if IsZeroWidthChar(Ch) then Exit(0);
  
  if Char.GetUnicodeCategory(UCS4Char(Code)) = TUnicodeCategory.ucControl then
    Exit(0);

  if InCodePointRanges(Code, CWideRanges) then
    Result := 2
  else
    Result := 1;
end;

// --- ПСЕВДОГРАФИКА ---

function IsBoxDrawingChar(const C: string): Boolean;
var
  Code: Cardinal;
begin
  if Length(C) = 0 then Exit(False);
  Code := GetCodePoint(C);
  Result := (Code >= $2500) and (Code <= $257F);
end;

function IsVerticalLine(const C: string): Boolean;
var
  Code: Cardinal;
begin
  if Length(C) = 0 then Exit(False);
  Code := GetCodePoint(C);
  case Code of
    $2502, $2503, $2551, $2506, $2507, $250A, $250B: Result := True;
  else
    Result := False;
  end;
end;

function IsHorizontalLine(const C: string): Boolean;
var
  Code: Cardinal;
begin
  if Length(C) = 0 then Exit(False);
  Code := GetCodePoint(C);
  case Code of
    $2500, $2501, $2550, $2504, $2505, $2508, $2509, $254C, $254D: Result := True;
  else
    Result := False;
  end;
end;

end.
