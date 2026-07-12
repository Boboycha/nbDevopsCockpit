unit Terminal.AnsiParser;

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.UIConsts,
  System.Generics.Collections, System.Math, System.Character,
  Terminal.Types,
  Terminal.Theme;

type
  TAnsiParserCommand = (apcNone, apcPrintChar, apcCursorUp, apcCursorDown,
    apcCursorForward, apcCursorBack, apcCursorNextLine, apcCursorPrevLine,
    apcCursorHorizontalAbs, apcCursorPosition, apcVerticalPositionAbs,
    apcVerticalPositionRel, apcHorizPositionAbs, apcHorizPositionRel,
    apcCursorBackwardTab, apcEraseDisplay, apcEraseLine, apcEraseChar,
    apcScrollUp, apcScrollDown, apcInsertLine, apcDeleteLine, apcInsertChar,
    apcDeleteChar, apcRepeatChar, apcSetGraphicsMode, apcSetMode, apcResetMode,
    apcSetPrivateMode, apcResetPrivateMode, apcSetScrollingRegion,
    apcSoftTerminalReset, apcSetCursorStyle, apcSaveCursorPosition,
    apcRestoreCursorPosition, apcDeviceAttributes, apcDeviceStatusReport,
    apcTabClear, apcReverseIndex);

  TAnsiCommand = record
    Command: TAnsiParserCommand;
    Params: TArray<Integer>;
    Char: string;
    Attributes: TCharAttributes;
  end;

  TCharacterSet = (csASCII, csLineDrawing);

  TAnsiParser = class
  private
    FState: (psNormal, psEscape, psCSI, psOSC, psCharsetG0, psCharsetG1);
    FParamBuffer: string;
    FIntermediateBuffer: string;
    FCurrentAttributes: TCharAttributes;
    FTheme: TTerminalTheme;

    FG0: TCharacterSet;
    FG1: TCharacterSet;
    FUseG1: Boolean;

    procedure ParseSGR(const Params: TArray<Integer>);
    procedure ParseCSIParams(FinalChar: WideChar;
      out Params: TArray<Integer>; out IsPrivateMode: Boolean);
    procedure InitCommand(out Cmd: TAnsiCommand);
    procedure SetIndexedColor(IsForeground: Boolean; Index: Integer);
    procedure SetRGBColor(IsForeground: Boolean; R, G, B: Integer);
    function GetColor256(Index: Integer): TAlphaColor;
    function GetColorRGB(R, G, B: Integer): TAlphaColor;
    function MapChar(Ch: WideChar): string;

    // Хелпер для извлечения полного символа (графемы)
    function GetNextGrapheme(const Input: string; var Index: Integer): string;

  public
    constructor Create(ATheme: TTerminalTheme);
    function Parse(const Input: string;
      out Commands: TArray<TAnsiCommand>): Boolean;
    procedure SetTheme(ATheme: TTerminalTheme);
    property CurrentAttributes: TCharAttributes read FCurrentAttributes
      write FCurrentAttributes;
    procedure Reset;
  end;

implementation

const
  CLineDrawingMap: array[0..31] of WideChar = (
    #$00A0, #$25C6, #$2592, #$2409, #$240C, #$240D, #$240A, #$00B0,
    #$00B1, #$2424, #$240B, #$2518, #$2510, #$250C, #$2514, #$253C,
    #$23BA, #$23BB, #$2500, #$23BC, #$23BD, #$251C, #$2524, #$2534,
    #$252C, #$2502, #$2264, #$2265, #$03C0, #$2260, #$00A3, #$00B7);
  CXtermColorLevels: array[0..5] of Byte = (0, 95, 135, 175, 215, 255);

{ TAnsiParser }

constructor TAnsiParser.Create(ATheme: TTerminalTheme);
begin
  inherited Create;
  FState := psNormal;
  FParamBuffer := '';
  FIntermediateBuffer := '';
  FTheme := ATheme;
  FCurrentAttributes := TCharAttributes.Default(FTheme);
  FG0 := csASCII;
  FG1 := csLineDrawing;
  FUseG1 := False;
end;

procedure TAnsiParser.SetTheme(ATheme: TTerminalTheme);
begin
  FTheme := ATheme;
  FCurrentAttributes.Reset(FTheme);
end;

function TAnsiParser.MapChar(Ch: WideChar): string;
var
  CurrentSet: TCharacterSet;
begin
  if FUseG1 then
    CurrentSet := FG1
  else
    CurrentSet := FG0;
  if CurrentSet = csASCII then
    Exit(string(Ch));

  if InRange(Ord(Ch), $5F, $7E) then
    Result := CLineDrawingMap[Ord(Ch) - $5F]
  else
    Result := string(Ch);
end;

function TAnsiParser.GetColor256(Index: Integer): TAlphaColor;
var
  R, G, B: Byte;
begin
  if (Index >= 0) and (Index <= 15) then
    Result := FTheme.AnsiColors[Index]
  else if (Index >= 16) and (Index <= 231) then
  begin
    Index := Index - 16;
    R := CXtermColorLevels[(Index div 36) mod 6];
    G := CXtermColorLevels[(Index div 6) mod 6];
    B := CXtermColorLevels[Index mod 6];
    Result := MakeColor(R, G, B);
  end
  else if (Index >= 232) and (Index <= 255) then
  begin
    R := 8 + (Index - 232) * 10;
    Result := MakeColor(R, R, R);
  end
  else
    Result := FTheme.DefaultFG;
end;

function TAnsiParser.GetColorRGB(R, G, B: Integer): TAlphaColor;
begin
  Result := MakeColor(EnsureRange(R, 0, 255), EnsureRange(G, 0, 255),
    EnsureRange(B, 0, 255));
end;

procedure TAnsiParser.InitCommand(out Cmd: TAnsiCommand);
begin
  Cmd := Default(TAnsiCommand);
  Cmd.Attributes := FCurrentAttributes;
end;

procedure TAnsiParser.SetIndexedColor(IsForeground: Boolean; Index: Integer);
var
  Source: TTerminalColorSource;
begin
  if InRange(Index, 0, 15) then
    Source := tcsAnsi
  else
    Source := tcsIndexed;

  if IsForeground then
  begin
    FCurrentAttributes.ForegroundColor := GetColor256(Index);
    FCurrentAttributes.ForegroundSource := Source;
    FCurrentAttributes.ForegroundIndex := Index;
  end
  else
  begin
    FCurrentAttributes.BackgroundColor := GetColor256(Index);
    FCurrentAttributes.BackgroundSource := Source;
    FCurrentAttributes.BackgroundIndex := Index;
  end;
end;

procedure TAnsiParser.SetRGBColor(IsForeground: Boolean; R, G, B: Integer);
begin
  if IsForeground then
  begin
    FCurrentAttributes.ForegroundColor := GetColorRGB(R, G, B);
    FCurrentAttributes.ForegroundSource := tcsRGB;
  end
  else
  begin
    FCurrentAttributes.BackgroundColor := GetColorRGB(R, G, B);
    FCurrentAttributes.BackgroundSource := tcsRGB;
  end;
end;

procedure TAnsiParser.ParseCSIParams(FinalChar: WideChar;
  out Params: TArray<Integer>; out IsPrivateMode: Boolean);
var
  I, ParamIndex, Value, DefaultValue, ParamCount: Integer;
  HasDigits, ValueIsValid: Boolean;
begin
  IsPrivateMode := (FParamBuffer <> '') and (FParamBuffer[1] = '?');
  I := Ord(IsPrivateMode) + 1;

  if I > Length(FParamBuffer) then
  begin
    SetLength(Params, 0);
    Exit;
  end;

  ParamCount := 1;
  for ParamIndex := I to Length(FParamBuffer) do
    if FParamBuffer[ParamIndex] = ';' then
      Inc(ParamCount);
  SetLength(Params, ParamCount);

  DefaultValue := 1;
  if FinalChar = 'm' then
    DefaultValue := 0;
  ParamIndex := 0;
  Value := 0;
  HasDigits := False;
  ValueIsValid := True;
  while I <= Length(FParamBuffer) do
  begin
    if FParamBuffer[I] = ';' then
    begin
      if HasDigits and ValueIsValid then
        Params[ParamIndex] := Value
      else if HasDigits then
        Params[ParamIndex] := 1
      else
        Params[ParamIndex] := DefaultValue;
      Inc(ParamIndex);
      Value := 0;
      HasDigits := False;
      ValueIsValid := True;
    end
    else if CharInSet(FParamBuffer[I], ['0'..'9']) then
    begin
      HasDigits := True;
      if Value <= (MaxInt - (Ord(FParamBuffer[I]) - Ord('0'))) div 10 then
        Value := Value * 10 + Ord(FParamBuffer[I]) - Ord('0')
      else
        ValueIsValid := False;
    end;
    Inc(I);
  end;
  if HasDigits and ValueIsValid then
    Params[ParamIndex] := Value
  else if HasDigits then
    Params[ParamIndex] := 1
  else
    Params[ParamIndex] := DefaultValue;
end;

procedure TAnsiParser.ParseSGR(const Params: TArray<Integer>);
var
  I, Param: Integer;
begin
  if Length(Params) = 0 then
  begin
    FCurrentAttributes.Reset(FTheme);
    Exit;
  end;
  I := 0;
  while I < Length(Params) do
  begin
    Param := Params[I];
    case Param of
      0:
        FCurrentAttributes.Reset(FTheme);
      1:
        FCurrentAttributes.Bold := True;
      2:
        FCurrentAttributes.Faint := True;
      3:
        FCurrentAttributes.Italic := True;
      4:
        FCurrentAttributes.Underline := True;
      5:
        FCurrentAttributes.Blink := True;
      7:
        FCurrentAttributes.Inverse := True;
      8:
        FCurrentAttributes.Hidden := True;
      9:
        FCurrentAttributes.Strikethrough := True;
      10:
        FG0 := csASCII;
      11, 12:
        FG0 := csLineDrawing;
      22:
        begin
          FCurrentAttributes.Bold := False;
          FCurrentAttributes.Faint := False;
        end;
      23:
        FCurrentAttributes.Italic := False;
      24:
        FCurrentAttributes.Underline := False;
      25:
        FCurrentAttributes.Blink := False;
      27:
        FCurrentAttributes.Inverse := False;
      28:
        FCurrentAttributes.Hidden := False;
      29:
        FCurrentAttributes.Strikethrough := False;
      30 .. 37:
        begin
          FCurrentAttributes.ForegroundColor := FTheme.AnsiColors[Param - 30];
          FCurrentAttributes.ForegroundSource := tcsAnsi;
          FCurrentAttributes.ForegroundIndex := Param - 30;
        end;
      39:
        begin
          FCurrentAttributes.ForegroundColor := FTheme.DefaultFG;
          FCurrentAttributes.ForegroundSource := tcsDefault;
        end;
      40 .. 47:
        begin
          FCurrentAttributes.BackgroundColor := FTheme.AnsiColors[Param - 40];
          FCurrentAttributes.BackgroundSource := tcsAnsi;
          FCurrentAttributes.BackgroundIndex := Param - 40;
        end;
      49:
        begin
          FCurrentAttributes.BackgroundColor := FTheme.DefaultBG;
          FCurrentAttributes.BackgroundSource := tcsDefault;
        end;
      90 .. 97:
        begin
          FCurrentAttributes.ForegroundIndex := Param - 90 + 8;
          FCurrentAttributes.ForegroundColor :=
            FTheme.AnsiColors[FCurrentAttributes.ForegroundIndex];
          FCurrentAttributes.ForegroundSource := tcsAnsi;
        end;
      100 .. 107:
        begin
          FCurrentAttributes.BackgroundIndex := Param - 100 + 8;
          FCurrentAttributes.BackgroundColor :=
            FTheme.AnsiColors[FCurrentAttributes.BackgroundIndex];
          FCurrentAttributes.BackgroundSource := tcsAnsi;
        end;
      38, 48:
        if I + 1 < Length(Params) then
        begin
          Inc(I);
          case Params[I] of
            5:
              if I + 1 < Length(Params) then
              begin
                Inc(I);
                SetIndexedColor(Param = 38, Params[I]);
              end;
            2:
              if I + 3 < Length(Params) then
              begin
                SetRGBColor(Param = 38, Params[I + 1], Params[I + 2],
                  Params[I + 3]);
                Inc(I, 3);
              end;
          end;
        end;
    end;
    Inc(I);
  end;
end;

procedure TAnsiParser.Reset;
begin
  FState := psNormal;
  FCurrentAttributes.Reset(FTheme);
  FParamBuffer := '';
  FIntermediateBuffer := '';
end;

// ЖАДНЫЙ ПАРСЕР ДЛЯ ZWJ (Чтобы семья была одним символом)
function TAnsiParser.GetNextGrapheme(const Input: string;
  var Index: Integer): string;
var
  Ch, NextCh: Char;
begin
  Result := '';
  if Index > Length(Input) then
    Exit;

  Ch := Input[Index];
  Result := Result + Ch;
  Inc(Index);

  if Ch.IsHighSurrogate and (Index <= Length(Input)) then
  begin
    NextCh := Input[Index];
    if NextCh.IsLowSurrogate then
    begin
      Result := Result + NextCh;
      Inc(Index);
    end;
  end;

  while Index <= Length(Input) do
  begin
    Ch := Input[Index];
    // ZWJ или VS16
    if (Ch = #$200D) or (Ch = #$FE0F) or (Ch = #$FE0E) then
    begin
      Result := Result + Ch;
      Inc(Index);
      // Если был ZWJ, пытаемся забрать следующий символ
      if (Ch = #$200D) and (Index <= Length(Input)) then
      begin
        Ch := Input[Index];
        Result := Result + Ch;
        Inc(Index);
        if Ch.IsHighSurrogate and (Index <= Length(Input)) and
          Input[Index].IsLowSurrogate then
        begin
          Result := Result + Input[Index];
          Inc(Index);
        end;
      end;
      Continue;
    end;
    Break;
  end;
end;

function TAnsiParser.Parse(const Input: string;
  out Commands: TArray<TAnsiCommand>): Boolean;
var
  I: Integer;
  Ch: WideChar;
  Cmd: TAnsiCommand;
  CmdList: TList<TAnsiCommand>;
  Params: TArray<Integer>;
  IsPrivateMode: Boolean;
  FullChar: string;
begin
  Result := True;
  CmdList := TList<TAnsiCommand>.Create;
  try
    I := 1;
    while I <= Length(Input) do
    begin
      if FState = psNormal then
        FullChar := GetNextGrapheme(Input, I)
      else
      begin
        FullChar := Input[I];
        Inc(I);
      end;

      Ch := FullChar[1];

      case FState of
        psNormal:
          begin
            if (Length(FullChar) = 1) and (Ch = #27) then
            begin
              FState := psEscape;
              FParamBuffer := '';
              FIntermediateBuffer := '';
            end
            else if (Length(FullChar) = 1) and (Ch = #14) then
              FUseG1 := True
            else if (Length(FullChar) = 1) and (Ch = #15) then
              FUseG1 := False
            else
            begin
              Cmd.Command := apcPrintChar;
              if Length(FullChar) > 1 then
                Cmd.Char := FullChar
              else
                Cmd.Char := MapChar(Ch);
              Cmd.Attributes := FCurrentAttributes;
              SetLength(Cmd.Params, 0);
              CmdList.Add(Cmd);
            end;
          end;
        psEscape:
          begin
            case Ch of
              '[': FState := psCSI;
              ']': FState := psOSC;
              '(': FState := psCharsetG0;
              ')': FState := psCharsetG1;
              '7', '8', 'M':
                begin
                  InitCommand(Cmd);
                  case Ch of
                    '7': Cmd.Command := apcSaveCursorPosition;
                    '8': Cmd.Command := apcRestoreCursorPosition;
                    'M': Cmd.Command := apcReverseIndex;
                  end;
                  CmdList.Add(Cmd);
                  FState := psNormal;
                end;
            else
              FState := psNormal;
            end;
          end;
        psCharsetG0:
          begin
            case Ch of
              '0':
                FG0 := csLineDrawing;
              'B':
                FG0 := csASCII;
            end;
            FState := psNormal;
          end;
        psCharsetG1:
          begin
            case Ch of
              '0':
                FG1 := csLineDrawing;
              'B':
                FG1 := csASCII;
            end;
            FState := psNormal;
          end;
        psCSI:
          begin
            if CharInSet(Ch, ['0' .. '9', ';', '?']) then
              FParamBuffer := FParamBuffer + Ch
            else if CharInSet(Ch, [#$20 .. #$2F]) then
              FIntermediateBuffer := FIntermediateBuffer + Ch
            else
            begin
              InitCommand(Cmd);
              ParseCSIParams(Ch, Params, IsPrivateMode);
              if (Ch = 'm') and (Length(Params) = 0) and not IsPrivateMode then
              begin
                SetLength(Params, 1);
                Params[0] := 0;
              end;
              if CharInSet(Ch, ['J', 'K']) and (FParamBuffer = '') then
              begin
                SetLength(Params, 1);
                Params[0] := 0;
              end;
              if CharInSet(Ch, ['H', 'f']) and (FParamBuffer = '') then
              begin
                SetLength(Params, 2);
                Params[0] := 1;
                Params[1] := 1;
              end;
              Cmd.Params := Params;
              case Ch of
                'A':
                  Cmd.Command := apcCursorUp;
                'B':
                  Cmd.Command := apcCursorDown;
                'C':
                  Cmd.Command := apcCursorForward;
                'D':
                  Cmd.Command := apcCursorBack;
                'E':
                  Cmd.Command := apcCursorNextLine;
                'F':
                  Cmd.Command := apcCursorPrevLine;
                'G':
                  Cmd.Command := apcCursorHorizontalAbs;
                'H', 'f':
                  Cmd.Command := apcCursorPosition;
                'd':
                  Cmd.Command := apcVerticalPositionAbs;
                'e':
                  Cmd.Command := apcVerticalPositionRel;
                '`':
                  Cmd.Command := apcHorizPositionAbs;
                'a':
                  Cmd.Command := apcHorizPositionRel;
                'Z':
                  Cmd.Command := apcCursorBackwardTab;
                'J':
                  Cmd.Command := apcEraseDisplay;
                'K':
                  Cmd.Command := apcEraseLine;
                'X':
                  Cmd.Command := apcEraseChar;
                'S':
                  Cmd.Command := apcScrollUp;
                'T':
                  Cmd.Command := apcScrollDown;
                'L':
                  Cmd.Command := apcInsertLine;
                'M':
                  Cmd.Command := apcDeleteLine;
                '@':
                  Cmd.Command := apcInsertChar;
                'P':
                  Cmd.Command := apcDeleteChar;
                'b':
                  Cmd.Command := apcRepeatChar;
                'h':
                  if IsPrivateMode then
                    Cmd.Command := apcSetPrivateMode
                  else
                    Cmd.Command := apcSetMode;
                'l':
                  if IsPrivateMode then
                    Cmd.Command := apcResetPrivateMode
                  else
                    Cmd.Command := apcResetMode;
                'r':
                  Cmd.Command := apcSetScrollingRegion;
                'p':
                  if FIntermediateBuffer = '!' then
                    Cmd.Command := apcSoftTerminalReset;
                'q':
                  if FIntermediateBuffer = ' ' then
                    Cmd.Command := apcSetCursorStyle;
                's':
                  Cmd.Command := apcSaveCursorPosition;
                'u':
                  Cmd.Command := apcRestoreCursorPosition;
                'c':
                  Cmd.Command := apcDeviceAttributes;
                'n':
                  Cmd.Command := apcDeviceStatusReport;
                'g':
                  Cmd.Command := apcTabClear;
                'm':
                  begin
                    Cmd.Command := apcSetGraphicsMode;
                    ParseSGR(Params);
                    Cmd.Attributes := FCurrentAttributes;
                  end;
              end;
              if Cmd.Command <> apcNone then
                CmdList.Add(Cmd);
              FState := psNormal;
              FParamBuffer := '';
              FIntermediateBuffer := '';
            end;
          end;
        psOSC:
          begin
            if Ch = #7 then
            begin
              FState := psNormal;
              FParamBuffer := '';
            end
            else if (Ch = #27) and (I <= Length(Input)) and (Input[I] = '\')
            then
            begin
              FState := psNormal;
              FParamBuffer := '';
              Inc(I);
            end
            else if (Ch = #27) and (I <= Length(Input)) and (Input[I] = ']')
            then
              FParamBuffer := ''
            else
              FParamBuffer := FParamBuffer + Ch;
          end;
      end;
    end;
    Commands := CmdList.ToArray;
  finally
    CmdList.Free;
  end;
end;

end.
