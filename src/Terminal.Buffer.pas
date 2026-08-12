unit Terminal.Buffer;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Types, System.Math, System.Character,
  Terminal.Types, Terminal.AnsiParser, Terminal.Theme;

type
  // Терминал должен иногда отвечать хосту (ответ на DA, DSR и т.п.).
  // Эти ответы уходят в SSH-канал, как обычный ввод пользователя.
  TTerminalResponseEvent = procedure(const S: string) of object;

  TTerminalBuffer = class
  private
    FLines: TList<TTerminalLine>;
    FWidth: Integer;
    FHeight: Integer;
    FCursor: TTerminalCursor;
    FCurrentAttributes: TCharAttributes;
    FScrollback: TList<TTerminalLine>;
    FMaxScrollback: Integer;
    FLastChar: string;
    FScrollTop: Integer;
    FScrollBottom: Integer;
    FAlternateBuffer: TList<TTerminalLine>;
    FUseAlternateBuffer: Boolean;
    FSavedCursorMain: TTerminalCursor;
    FSavedCursorAlt: TTerminalCursor;
    FSavedScrollTopMain: Integer;
    FSavedScrollBottomMain: Integer;
    FSavedScrollTopAlt: Integer;
    FSavedScrollBottomAlt: Integer;
    FSavedCursor: TTerminalCursor;
    FAppCursorKeys: Boolean;
    FTheme: TTerminalTheme;
    FLinesDirty: TArray<Boolean>;
    FVisualScrollDelta: Integer;
    FViewportOffset: Integer;
    FMouseModes: TMouseTrackingModes;
    FLastMouseCol: Integer;
    FLastMouseRow: Integer;
    FSelStart: TPoint;
    FSelEnd: TPoint;
    FHasSelection: Boolean;
    FBracketedPaste: Boolean;
    FCarriageReturnPending: Boolean;
    FOnResponse: TTerminalResponseEvent;

    function GetLine(Index: Integer): TTerminalLine;
    procedure SetLine(Index: Integer; const Value: TTerminalLine);
    function GetCurrentLines: TList<TTerminalLine>;
    procedure EnsureLine(Index: Integer);
    procedure ScrollUp(Lines: Integer = 1);
    procedure ScrollDown(Lines: Integer = 1);
    procedure RemapBufferColors(Buffer: TList<TTerminalLine>;
      NewTheme: TTerminalTheme);
    function CreateBlankLine: TTerminalLine;
    procedure SetDirty(LineIndex: Integer);
    procedure SetRangeDirty(FromIndex, ToIndex: Integer);
    procedure InternalScrollUp(Top, Bottom, Count: Integer);
    procedure InternalScrollDown(Top, Bottom, Count: Integer);
    procedure AdvanceToNextLine(IsWrapped, ResetColumn: Boolean);
    procedure BlankCell(var Cell: TTerminalChar;
      const Attr: TCharAttributes);
    procedure ClearCellRange(var Line: TTerminalLine; First, Last: Integer;
      const Attr: TCharAttributes);
    procedure NormalizeWideCells(var Line: TTerminalLine;
      const Attr: TCharAttributes);
    procedure NormalizeSelection;
    function GetLineByAbsoluteIndex(Index: Integer): TTerminalLine;
    procedure SetSelectionRangeDirty(StartAbsY, EndAbsY: Integer);
    procedure ReflowMainBuffer(NewWidth, NewHeight: Integer);
    
    // Очистка "хвоста" wide-символа если перезаписываем
    procedure ClearWideCharTail(Line: TTerminalLine; X: Integer);
    // Очистка "головы" wide-символа если пишем в его хвост
    procedure ClearWideCharHead(Line: TTerminalLine; X: Integer);

  public
    constructor Create(AWidth, AHeight: Integer; ATheme: TTerminalTheme);
    destructor Destroy; override;
    procedure Clear;
    procedure ClearLine(Y: Integer; Mode: Integer = 2);

    // ПРИНИМАЕТ STRING
    procedure WriteChar(Ch: string; Attr: TCharAttributes);
    procedure WriteText(const Text: string; Attr: TCharAttributes);

    procedure ProcessCommand(const Cmd: TAnsiCommand);
    procedure MoveCursor(X, Y: Integer);
    procedure MoveCursorRelative(DX, DY: Integer);
    procedure InsertLine(Y: Integer; Count: Integer = 1);
    procedure DeleteLine(Y: Integer; Count: Integer = 1);
    procedure InsertChar(X, Y: Integer; Count: Integer = 1);
    procedure DeleteChar(X, Y: Integer; Count: Integer = 1);
    procedure EraseChar(X, Y: Integer; Count: Integer = 1);
    procedure SwitchToAlternateBuffer;
    procedure SwitchToMainBuffer;
    procedure AdvanceCursor;
    procedure Resize(NewWidth, NewHeight: Integer);
    procedure SetTheme(ATheme: TTerminalTheme);
    function IsLineDirty(Index: Integer): Boolean;
    procedure CleanLine(Index: Integer);
    procedure SetAllDirty;
    function GetAndResetVisualScrollDelta: Integer;
    procedure ScrollViewport(Delta: Integer);
    procedure ResetViewport;
    function GetRenderLine(Index: Integer): TTerminalLine;
    procedure SetSelection(StartX, StartY, EndX, EndY: Integer);
    procedure ClearSelection;
    function IsCellSelected(X, ScreenY: Integer): Boolean;
    function GetSelectedText: string;
    function GetTotalLinesCount: Integer;
    function ScreenYToAbsolute(ScreenY: Integer): Integer;

    property Lines[Index: Integer]: TTerminalLine read GetLine write SetLine;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Cursor: TTerminalCursor read FCursor write FCursor;
    property CurrentAttributes: TCharAttributes read FCurrentAttributes
      write FCurrentAttributes;
    property Scrollback: TList<TTerminalLine> read FScrollback;
    property MaxScrollback: Integer read FMaxScrollback write FMaxScrollback;
    property AppCursorKeys: Boolean read FAppCursorKeys;
    property MouseModes: TMouseTrackingModes read FMouseModes;
    property LastMouseCol: Integer read FLastMouseCol write FLastMouseCol;
    property LastMouseRow: Integer read FLastMouseRow write FLastMouseRow;
    property ViewportOffset: Integer read FViewportOffset;
    property HasSelection: Boolean read FHasSelection;
    property IsAlternateBuffer: Boolean read FUseAlternateBuffer;
    property BracketedPaste: Boolean read FBracketedPaste;
    property OnResponse: TTerminalResponseEvent read FOnResponse write FOnResponse;
  end;

implementation

{ TTerminalBuffer }

constructor TTerminalBuffer.Create(AWidth, AHeight: Integer; ATheme: TTerminalTheme);
var
  I: Integer;
begin
  inherited Create;
  FTheme := ATheme;
  FWidth := AWidth;
  FHeight := AHeight;
  (* Лимит истории. Каждая строка ~30-40 байт на ячейку (TTerminalChar
     record) плюс отдельная heap-аллокация под Char: string на каждый
     непустой символ - т.е. строка из ~120 колонок занимает ориентировочно
     8-10 КБ. 100 000 строк - это ~1 ГБ в худшем случае на одну вкладку
     терминала; выбрано как верхняя разумная граница, покрывающая cat
     больших логов без риска OOM при нескольких одновременно открытых
     SSH-сессиях. *)
  FMaxScrollback := 100000;
  FScrollTop := 0;
  FScrollBottom := FHeight - 1;
  FUseAlternateBuffer := False;
  FAppCursorKeys := False;
  FVisualScrollDelta := 0;
  FViewportOffset := 0;
  FMouseModes := [];
  FLastMouseCol := 1;
  FLastMouseRow := 1;
  FHasSelection := False;
  FBracketedPaste := False;
  FCarriageReturnPending := False;

  FLines := TList<TTerminalLine>.Create;
  FScrollback := TList<TTerminalLine>.Create;
  FAlternateBuffer := TList<TTerminalLine>.Create;

  for I := 0 to FHeight - 1 do
    FLines.Add(CreateBlankLine);

  SetLength(FLinesDirty, FHeight);
  SetAllDirty;

  FCursor.X := 0;
  FCursor.Y := 0;
  FCursor.Visible := True;
  FCursor.Shape := tcsBlock;
  FCursor.Blink := True;
  FSavedCursor := FCursor;
  FSavedCursorMain := FCursor;
  FSavedCursorAlt := FCursor;
  FCurrentAttributes := TCharAttributes.Default(FTheme);
  FLastChar := ' ';
end;

destructor TTerminalBuffer.Destroy;
begin
  // НЕ освобождаем FTheme - он внешний!
  FLines.Free;
  FScrollback.Free;
  FAlternateBuffer.Free;
  inherited;
end;

function TTerminalBuffer.CreateBlankLine: TTerminalLine;
var
  J: Integer;
  BlankAttributes: TCharAttributes;
begin
  Result := Default(TTerminalLine);
  SetLength(Result.Cells, FWidth);
  BlankAttributes := TCharAttributes.Default(FTheme);
  for J := 0 to FWidth - 1 do
    BlankCell(Result.Cells[J], BlankAttributes);
  Result.IsWrapped := False;
end;

procedure TTerminalBuffer.ClearWideCharTail(Line: TTerminalLine; X: Integer);
begin
  // Если текущая ячейка — wide (Width=2), очищаем следующую ячейку (хвост)
  if (X < Length(Line.Cells)) and (Line.Cells[X].Width = 2) then
  begin
    if (X + 1 < Length(Line.Cells)) and (Line.Cells[X + 1].Width = 0) then
    begin
      BlankCell(Line.Cells[X + 1], TCharAttributes.Default(FTheme));
    end;
  end;
end;

procedure TTerminalBuffer.ClearWideCharHead(Line: TTerminalLine; X: Integer);
begin
  // Если текущая ячейка — хвост wide-символа (Width=0), очищаем голову
  if (X < Length(Line.Cells)) and (Line.Cells[X].Width = 0) then
  begin
    if (X > 0) and (Line.Cells[X - 1].Width = 2) then
    begin
      BlankCell(Line.Cells[X - 1], TCharAttributes.Default(FTheme));
    end;
  end;
end;

function TTerminalBuffer.GetCurrentLines: TList<TTerminalLine>;
begin
  if FUseAlternateBuffer then
    Result := FAlternateBuffer
  else
    Result := FLines;
end;

function TTerminalBuffer.GetLine(Index: Integer): TTerminalLine;
var
  CurrentLines: TList<TTerminalLine>;
begin
  CurrentLines := GetCurrentLines;
  if (Index >= 0) and (Index < CurrentLines.Count) then
    Result := CurrentLines[Index]
  else
    Result := Default(TTerminalLine);
end;

procedure TTerminalBuffer.SetLine(Index: Integer; const Value: TTerminalLine);
var
  CurrentLines: TList<TTerminalLine>;
begin
  CurrentLines := GetCurrentLines;
  if (Index >= 0) and (Index < CurrentLines.Count) then
  begin
    CurrentLines[Index] := Value;
    SetDirty(Index);
  end;
end;

procedure TTerminalBuffer.EnsureLine(Index: Integer);
var
  CurrentLines: TList<TTerminalLine>;
begin
  CurrentLines := GetCurrentLines;
  while CurrentLines.Count <= Index do
    CurrentLines.Add(CreateBlankLine);
end;

procedure TTerminalBuffer.SetDirty(LineIndex: Integer);
begin
  if (LineIndex >= 0) and (LineIndex < Length(FLinesDirty)) then
    FLinesDirty[LineIndex] := True;
end;

procedure TTerminalBuffer.SetRangeDirty(FromIndex, ToIndex: Integer);
begin
  FromIndex := Max(FromIndex, 0);
  ToIndex := Min(ToIndex, High(FLinesDirty));
  if FromIndex <= ToIndex then
    FillChar(FLinesDirty[FromIndex],
      (ToIndex - FromIndex + 1) * SizeOf(Boolean), Ord(True));
end;

procedure TTerminalBuffer.BlankCell(var Cell: TTerminalChar;
  const Attr: TCharAttributes);
begin
  Cell.Char := ' ';
  Cell.Attributes := Attr;
  Cell.Width := 1;
end;

procedure TTerminalBuffer.ClearCellRange(var Line: TTerminalLine;
  First, Last: Integer; const Attr: TCharAttributes);
var
  I: Integer;
begin
  First := Max(First, 0);
  Last := Min(Last, High(Line.Cells));
  for I := First to Last do
    BlankCell(Line.Cells[I], Attr);
end;

procedure TTerminalBuffer.NormalizeWideCells(var Line: TTerminalLine;
  const Attr: TCharAttributes);
var
  I: Integer;
begin
  for I := 0 to High(Line.Cells) do
    case Line.Cells[I].Width of
      0:
        if (I = 0) or (Line.Cells[I - 1].Width <> 2) then
          BlankCell(Line.Cells[I], Attr);
      2:
        if (I = High(Line.Cells)) or (Line.Cells[I + 1].Width <> 0) then
          BlankCell(Line.Cells[I], Attr);
    end;
end;

procedure TTerminalBuffer.SetAllDirty;
begin
  if Length(FLinesDirty) > 0 then
    FillChar(FLinesDirty[0], Length(FLinesDirty) * SizeOf(Boolean), Ord(True));
end;

function TTerminalBuffer.IsLineDirty(Index: Integer): Boolean;
begin
  if (Index >= 0) and (Index < Length(FLinesDirty)) then
    Result := FLinesDirty[Index]
  else
    Result := False;
end;

procedure TTerminalBuffer.CleanLine(Index: Integer);
begin
  if (Index >= 0) and (Index < Length(FLinesDirty)) then
    FLinesDirty[Index] := False;
end;

procedure TTerminalBuffer.InternalScrollUp(Top, Bottom, Count: Integer);
var
  CurrentLines: TList<TTerminalLine>;
  I, TrimCount: Integer;
  HistoryLine: TTerminalLine;
begin
  CurrentLines := GetCurrentLines;
  EnsureLine(Bottom);
  Count := EnsureRange(Count, 0, Bottom - Top + 1);
  if Count = 0 then
    Exit;

  if (not FUseAlternateBuffer) and (Top = 0) and
    (Bottom = FHeight - 1) then
  begin
    for I := Top to Top + Count - 1 do
    begin
      HistoryLine := CurrentLines[I];
      HistoryLine.Cells := Copy(HistoryLine.Cells);
      FScrollback.Add(HistoryLine);
    end;
    TrimCount := Min(FScrollback.Count,
      Max(0, FScrollback.Count - FMaxScrollback));
    if TrimCount > 0 then
      FScrollback.DeleteRange(0, TrimCount);
  end;

  for I := Top to Bottom - Count do
    CurrentLines[I] := CurrentLines[I + Count];
  for I := Bottom - Count + 1 to Bottom do
    CurrentLines[I] := CreateBlankLine;
  SetRangeDirty(Top, Bottom);
end;

procedure TTerminalBuffer.InternalScrollDown(Top, Bottom, Count: Integer);
var
  CurrentLines: TList<TTerminalLine>;
  I: Integer;
begin
  CurrentLines := GetCurrentLines;
  EnsureLine(Bottom);
  Count := EnsureRange(Count, 0, Bottom - Top + 1);
  if Count = 0 then
    Exit;

  for I := Bottom downto Top + Count do
    CurrentLines[I] := CurrentLines[I - Count];
  for I := Top to Top + Count - 1 do
    CurrentLines[I] := CreateBlankLine;
  SetRangeDirty(Top, Bottom);
end;

procedure TTerminalBuffer.ScrollUp(Lines: Integer);
var
  IsFullScreenScroll: Boolean;
  K: Integer;
begin
  Lines := EnsureRange(Lines, 0, FScrollBottom - FScrollTop + 1);
  if Lines = 0 then
    Exit;
  IsFullScreenScroll := (FScrollTop = 0) and (FScrollBottom = FHeight - 1);
  InternalScrollUp(FScrollTop, FScrollBottom, Lines);
  if IsFullScreenScroll then
  begin
    Inc(FVisualScrollDelta, Lines);
    if Lines < Length(FLinesDirty) then
    begin
      Move(FLinesDirty[Lines], FLinesDirty[0], (Length(FLinesDirty) - Lines) *
        SizeOf(Boolean));
      for K := FHeight - Lines to FHeight - 1 do
        FLinesDirty[K] := True;
    end
    else
      SetAllDirty;
  end;
end;

procedure TTerminalBuffer.ScrollDown(Lines: Integer);
begin
  Lines := EnsureRange(Lines, 0, FScrollBottom - FScrollTop + 1);
  if Lines = 0 then
    Exit;
  InternalScrollDown(FScrollTop, FScrollBottom, Lines);
end;

procedure TTerminalBuffer.AdvanceToNextLine(IsWrapped,
  ResetColumn: Boolean);
var
  CurrentLines: TList<TTerminalLine>;
  Line: TTerminalLine;
begin
  CurrentLines := GetCurrentLines;
  Line := CurrentLines[FCursor.Y];
  Line.IsWrapped := IsWrapped;
  CurrentLines[FCursor.Y] := Line;

  if ResetColumn then
    FCursor.X := 0;
  if FCursor.Y = FScrollBottom then
    ScrollUp(1)
  else
    FCursor.Y := Min(FCursor.Y + 1, FHeight - 1);
end;

procedure TTerminalBuffer.DeleteLine(Y: Integer; Count: Integer);
var
  Limit: Integer;
begin
  if (Y < FScrollTop) or (Y > FScrollBottom) then
    Y := FScrollTop;
  Limit := FScrollBottom - Y + 1;
  if Count > Limit then
    Count := Limit;
  if Count > 0 then
    InternalScrollUp(Y, FScrollBottom, Count);
end;

procedure TTerminalBuffer.InsertLine(Y: Integer; Count: Integer);
var
  Limit: Integer;
begin
  if (Y < FScrollTop) or (Y > FScrollBottom) then
    Y := FScrollTop;
  Limit := FScrollBottom - Y + 1;
  if Count > Limit then
    Count := Limit;
  if Count > 0 then
    InternalScrollDown(Y, FScrollBottom, Count);
end;

function TTerminalBuffer.GetAndResetVisualScrollDelta: Integer;
begin
  Result := FVisualScrollDelta;
  FVisualScrollDelta := 0;
end;

procedure TTerminalBuffer.ScrollViewport(Delta: Integer);
begin
  if FUseAlternateBuffer then
    Exit;
  FViewportOffset := EnsureRange(FViewportOffset + Delta, 0, FScrollback.Count);
  SetAllDirty;
end;

procedure TTerminalBuffer.ResetViewport;
begin
  if FViewportOffset <> 0 then
  begin
    FViewportOffset := 0;
    SetAllDirty;
  end;
end;

function TTerminalBuffer.GetRenderLine(Index: Integer): TTerminalLine;
var
  TotalHistory, TargetIndex: Integer;
  CurrentLines: TList<TTerminalLine>;
begin
  if FUseAlternateBuffer then
  begin
    CurrentLines := FAlternateBuffer;
    if (Index >= 0) and (Index < CurrentLines.Count) then
      Result := CurrentLines[Index]
    else
      Result := Default(TTerminalLine);
    Exit;
  end;
  CurrentLines := FLines;
  TotalHistory := FScrollback.Count;
  TargetIndex := (TotalHistory + Index) - FViewportOffset;
  if TargetIndex < 0 then
    Result := Default(TTerminalLine)
  else if TargetIndex < TotalHistory then
    Result := FScrollback[TargetIndex]
  else
  begin
    TargetIndex := TargetIndex - TotalHistory;
    if (TargetIndex >= 0) and (TargetIndex < CurrentLines.Count) then
      Result := CurrentLines[TargetIndex]
    else
      Result := Default(TTerminalLine);
  end;
end;

procedure TTerminalBuffer.Clear;
var
  I: Integer;
  CurrentLines: TList<TTerminalLine>;
begin
  CurrentLines := GetCurrentLines;
  CurrentLines.Clear;
  for I := 0 to FHeight - 1 do
    CurrentLines.Add(CreateBlankLine);
  FCursor.X := 0;
  FCursor.Y := 0;
  FScrollTop := 0;
  FScrollBottom := FHeight - 1;
  SetAllDirty;
end;

procedure TTerminalBuffer.ClearLine(Y: Integer; Mode: Integer);
var
  CurrentLines: TList<TTerminalLine>;
  Line: TTerminalLine;
  Row, LogicalStart, StartX, EndX: Integer;
begin
  CurrentLines := GetCurrentLines;
  if (Y < 0) or (Y >= CurrentLines.Count) then Exit;

  // Readline redraws an input line after SIGWINCH as CR + EL + text.
  // If the old input occupied several soft-wrapped rows, EL must replace
  // that logical line, otherwise every redraw leaves its previous head.
  if FCarriageReturnPending and (Mode = 0) and (FCursor.X = 0) then
  begin
    LogicalStart := Y;
    while (LogicalStart > 0) and CurrentLines[LogicalStart - 1].IsWrapped do
      Dec(LogicalStart);
    if LogicalStart < Y then
    begin
      for Row := LogicalStart to Y do
      begin
        Line := CurrentLines[Row];
        ClearCellRange(Line, 0, High(Line.Cells), FCurrentAttributes);
        Line.IsWrapped := False;
        CurrentLines[Row] := Line;
        SetDirty(Row);
      end;
      FCursor.Y := LogicalStart;
      FCarriageReturnPending := False;
      Exit;
    end;
  end;
  
  Line := CurrentLines[Y];
  
  case Mode of
    0: begin StartX := FCursor.X; EndX := FWidth - 1; end;  // От курсора до конца
    1: begin StartX := 0; EndX := FCursor.X; end;           // От начала до курсора
    2: begin StartX := 0; EndX := FWidth - 1; end;          // Вся строка
  else
    Exit;
  end;
  
  ClearCellRange(Line, StartX, EndX, FCurrentAttributes);
  NormalizeWideCells(Line, FCurrentAttributes);
  if (Mode = 2) or ((Mode = 0) and (StartX = 0)) then
    Line.IsWrapped := False;
  
  CurrentLines[Y] := Line;
  FCarriageReturnPending := False;
  SetDirty(Y);
end;

procedure TTerminalBuffer.WriteChar(Ch: string; Attr: TCharAttributes);
var
  CurrentLines: TList<TTerminalLine>;
  Line: TTerminalLine;
  C: Char;
  CharWidth: Integer;
  ShouldMerge: Boolean;
  PrevChar: string;
  PrevX: Integer;
begin
  ResetViewport;
  CurrentLines := GetCurrentLines;

  (* Печатные ASCII-символы (подавляющее большинство обычного текстового
     вывода) разделяют одну heap-строку на весь процесс вместо отдельной
     аллокации на каждую ячейку буфера/истории - см. InternAsciiChar. *)
  Ch := InternAsciiChar(Ch);

  // Коррекция позиции курсора
  if (FCursor.Y < 0) or (FCursor.Y >= FHeight) or (FCursor.X < 0) or
    (FCursor.X > FWidth) then
  begin
    FCursor.X := EnsureRange(FCursor.X, 0, FWidth - 1);
    FCursor.Y := EnsureRange(FCursor.Y, 0, FHeight - 1);
  end;

  // Обработка управляющих символов
  if Length(Ch) = 1 then
  begin
    C := Ch[1];
    case C of
      #7:  // Bell
        Exit;
      #10: // Line Feed
        begin
          FCarriageReturnPending := False;
          AdvanceToNextLine(False, False);
          Exit;
        end;
      #13: // Carriage Return
        begin
          FCursor.X := 0;
          FCarriageReturnPending := True;
          Exit;
        end;
      #8:  // Backspace
        begin
          if FCursor.X > 0 then
            Dec(FCursor.X);
          Exit;
        end;
      #9:  // Tab
        begin
          FCursor.X := ((FCursor.X div 8) + 1) * 8;
          if FCursor.X >= FWidth then
            AdvanceToNextLine(False, True);
          Exit;
        end;
    end;
  end;

  // Zero-width символы (ZWJ, variation selectors) — склеиваем с предыдущим
  FCarriageReturnPending := False;
  if IsZeroWidthChar(Ch) then
  begin
    if FCursor.X > 0 then
    begin
      EnsureLine(FCursor.Y);
      Line := CurrentLines[FCursor.Y];
      PrevX := FCursor.X - 1;
      if (PrevX > 0) and (Line.Cells[PrevX].Width = 0) then
        Dec(PrevX);
      Line.Cells[PrevX].Char := Line.Cells[PrevX].Char + Ch;
      CurrentLines[FCursor.Y] := Line;
      SetDirty(FCursor.Y);
    end;
    Exit; // Не двигаем курсор!
  end;

  // Получаем ширину символа
  CharWidth := GetCharDisplayWidth(Ch);
  if CharWidth = 0 then
    Exit;

  // Автоперенос строки
  if FCursor.X >= FWidth then
    AdvanceToNextLine(True, True);
  
  // Для wide-символов проверяем, влезет ли
  if (CharWidth = 2) and (FCursor.X = FWidth - 1) then
  begin
    // Wide-символ не влезает — переносим на следующую строку
    AdvanceToNextLine(True, True);
  end;

  if FCursor.Y > FScrollBottom then
    FCursor.Y := FScrollBottom;
    
  EnsureLine(FCursor.Y);
  Line := CurrentLines[FCursor.Y];

  // Проверка на склейку ZWJ-последовательностей (для combining marks)
  ShouldMerge := False;
  PrevX := -1;
  if (Length(Ch) > 0) and (FCursor.X > 0) then
  begin
    PrevX := FCursor.X - 1;
    if (PrevX > 0) and (Line.Cells[PrevX].Width = 0) then
      Dec(PrevX);
    PrevChar := Line.Cells[PrevX].Char;
    // Если предыдущий символ заканчивается на ZWJ — склеиваем
    if (Length(PrevChar) > 0) and (PrevChar[Length(PrevChar)] = #$200D) then
      ShouldMerge := True;
  end;

  if ShouldMerge then
  begin
    Line.Cells[PrevX].Char := Line.Cells[PrevX].Char + Ch;
    CurrentLines[FCursor.Y] := Line;
    SetDirty(FCursor.Y);
    Exit;
  end;

  // Очищаем старые wide-символы если перезаписываем
  ClearWideCharHead(Line, FCursor.X);
  ClearWideCharTail(Line, FCursor.X);

  // Записываем символ
  Line.Cells[FCursor.X].Char := Ch;
  Line.Cells[FCursor.X].Attributes := Attr;
  Line.Cells[FCursor.X].Width := CharWidth;
  
  // Если wide — помечаем следующую ячейку как продолжение
  if (CharWidth = 2) and (FCursor.X + 1 < FWidth) then
  begin
    ClearWideCharHead(Line, FCursor.X + 1);
    ClearWideCharTail(Line, FCursor.X + 1);
    Line.Cells[FCursor.X + 1].Char := '';
    Line.Cells[FCursor.X + 1].Width := 0;  // Маркер "продолжение"
    Line.Cells[FCursor.X + 1].Attributes := Attr;
  end;

  CurrentLines[FCursor.Y] := Line;
  
  if Length(Ch) > 1 then
    FLastChar := ' '
  else
    FLastChar := Ch;
    
  Inc(FCursor.X, CharWidth);
  SetDirty(FCursor.Y);
end;

procedure TTerminalBuffer.WriteText(const Text: string; Attr: TCharAttributes);
var
  I: Integer;
  S: string;
  Ch: Char;
begin
  I := 1;
  while I <= Length(Text) do
  begin
    Ch := Text[I];
    S := Ch;
    Inc(I);
    // Если суррогатная пара, берем второй символ
    if Ch.IsHighSurrogate and (I <= Length(Text)) and
      Text[I].IsLowSurrogate then
    begin
      SetLength(S, 2);
      S[2] := Text[I];
      Inc(I);
    end;
    WriteChar(S, Attr);
  end;
end;

procedure TTerminalBuffer.MoveCursor(X, Y: Integer);
begin
  FCursor.X := EnsureRange(X, 0, FWidth - 1);
  FCursor.Y := EnsureRange(Y, 0, FHeight - 1);
end;

procedure TTerminalBuffer.MoveCursorRelative(DX, DY: Integer);
begin
  MoveCursor(FCursor.X + DX, FCursor.Y + DY);
end;

procedure TTerminalBuffer.AdvanceCursor;
begin
  Inc(FCursor.X);
  if FCursor.X >= FWidth then
  begin
    FCursor.X := 0;
    Inc(FCursor.Y);
    if FCursor.Y >= FHeight then
      FCursor.Y := FHeight - 1;
  end;
end;

procedure TTerminalBuffer.InsertChar(X, Y: Integer; Count: Integer);
var
  CurrentLines: TList<TTerminalLine>;
  Line: TTerminalLine;
  I, CellCount: Integer;
begin
  CurrentLines := GetCurrentLines;
  if (Y < 0) or (Y >= CurrentLines.Count) then Exit;
  Line := CurrentLines[Y];
  CellCount := Min(FWidth, Length(Line.Cells));
  X := EnsureRange(X, 0, CellCount);
  Count := EnsureRange(Count, 0, CellCount - X);
  if Count = 0 then Exit;

  for I := CellCount - 1 downto X + Count do
    Line.Cells[I] := Line.Cells[I - Count];
  ClearCellRange(Line, X, X + Count - 1, FCurrentAttributes);
  NormalizeWideCells(Line, FCurrentAttributes);
  
  CurrentLines[Y] := Line;
  SetDirty(Y);
end;

procedure TTerminalBuffer.DeleteChar(X, Y: Integer; Count: Integer);
var
  CurrentLines: TList<TTerminalLine>;
  Line: TTerminalLine;
  I, CellCount: Integer;
begin
  CurrentLines := GetCurrentLines;
  if (Y < 0) or (Y >= CurrentLines.Count) then Exit;
  Line := CurrentLines[Y];
  CellCount := Min(FWidth, Length(Line.Cells));
  X := EnsureRange(X, 0, CellCount);
  Count := EnsureRange(Count, 0, CellCount - X);
  if Count = 0 then Exit;

  for I := X to CellCount - Count - 1 do
    Line.Cells[I] := Line.Cells[I + Count];
  ClearCellRange(Line, CellCount - Count, CellCount - 1,
    FCurrentAttributes);
  NormalizeWideCells(Line, FCurrentAttributes);
  
  CurrentLines[Y] := Line;
  SetDirty(Y);
end;

procedure TTerminalBuffer.EraseChar(X, Y: Integer; Count: Integer);
var
  CurrentLines: TList<TTerminalLine>;
  Line: TTerminalLine;
  CellCount: Integer;
begin
  CurrentLines := GetCurrentLines;
  if (Y < 0) or (Y >= CurrentLines.Count) then Exit;
  Line := CurrentLines[Y];
  CellCount := Min(FWidth, Length(Line.Cells));
  X := EnsureRange(X, 0, CellCount);
  Count := EnsureRange(Count, 0, CellCount - X);
  if Count = 0 then Exit;

  ClearCellRange(Line, X, X + Count - 1, FCurrentAttributes);
  NormalizeWideCells(Line, FCurrentAttributes);
  
  CurrentLines[Y] := Line;
  SetDirty(Y);
end;

procedure TTerminalBuffer.SwitchToAlternateBuffer;
var
  I: Integer;
  CursorVisible: Boolean;
  CursorShape: TTerminalCursorShape;
  CursorBlink: Boolean;
begin
  if FUseAlternateBuffer then Exit;

  CursorVisible := FCursor.Visible;
  CursorShape := FCursor.Shape;
  CursorBlink := FCursor.Blink;
  
  // Сохраняем состояние main buffer
  FSavedCursorMain := FCursor;
  FSavedScrollTopMain := FScrollTop;
  FSavedScrollBottomMain := FScrollBottom;
  
  // Инициализируем alternate buffer
  FAlternateBuffer.Clear;
  for I := 0 to FHeight - 1 do
    FAlternateBuffer.Add(CreateBlankLine);
  
  FUseAlternateBuffer := True;
  FCursor := FSavedCursorAlt;
  FCursor.Visible := CursorVisible;
  FCursor.Shape := CursorShape;
  FCursor.Blink := CursorBlink;
  FScrollTop := FSavedScrollTopAlt;
  FScrollBottom := FSavedScrollBottomAlt;
  
  if FScrollBottom = 0 then
    FScrollBottom := FHeight - 1;
  
  SetAllDirty;
end;

procedure TTerminalBuffer.SwitchToMainBuffer;
var
  CursorVisible: Boolean;
  CursorShape: TTerminalCursorShape;
  CursorBlink: Boolean;
begin
  if not FUseAlternateBuffer then Exit;

  CursorVisible := FCursor.Visible;
  CursorShape := FCursor.Shape;
  CursorBlink := FCursor.Blink;
  
  // Сохраняем состояние alternate buffer
  FSavedCursorAlt := FCursor;
  FSavedScrollTopAlt := FScrollTop;
  FSavedScrollBottomAlt := FScrollBottom;
  
  FUseAlternateBuffer := False;
  FCursor := FSavedCursorMain;
  FCursor.Visible := CursorVisible;
  FCursor.Shape := CursorShape;
  FCursor.Blink := CursorBlink;
  FScrollTop := FSavedScrollTopMain;
  FScrollBottom := FSavedScrollBottomMain;
  
  if FScrollBottom = 0 then
    FScrollBottom := FHeight - 1;
  
  SetAllDirty;
end;

procedure TTerminalBuffer.SetTheme(ATheme: TTerminalTheme);
begin
  if FTheme = ATheme then Exit;

  FTheme.Assign(ATheme);
  RemapBufferColors(FLines, FTheme);
  RemapBufferColors(FAlternateBuffer, FTheme);
  RemapBufferColors(FScrollback, FTheme);
  FCurrentAttributes.Reset(FTheme);
  
  SetAllDirty;
end;

procedure TTerminalBuffer.RemapBufferColors(Buffer: TList<TTerminalLine>;
  NewTheme: TTerminalTheme);
var
  I, J: Integer;
  Line: TTerminalLine;
begin
  for I := 0 to Buffer.Count - 1 do
  begin
    Line := Buffer[I];
    for J := 0 to High(Line.Cells) do
    begin
      // Remap foreground
      if Line.Cells[J].Attributes.ForegroundSource = tcsDefault then
        Line.Cells[J].Attributes.ForegroundColor := NewTheme.DefaultFG
      else if Line.Cells[J].Attributes.ForegroundSource = tcsAnsi then
        Line.Cells[J].Attributes.ForegroundColor := NewTheme.AnsiColors[
          EnsureRange(Line.Cells[J].Attributes.ForegroundIndex, 0, 15)];
      
      // Remap background
      if Line.Cells[J].Attributes.BackgroundSource = tcsDefault then
        Line.Cells[J].Attributes.BackgroundColor := NewTheme.DefaultBG
      else if Line.Cells[J].Attributes.BackgroundSource = tcsAnsi then
        Line.Cells[J].Attributes.BackgroundColor := NewTheme.AnsiColors[
          EnsureRange(Line.Cells[J].Attributes.BackgroundIndex, 0, 15)];
    end;
    Buffer[I] := Line;
  end;
end;

procedure TTerminalBuffer.ReflowMainBuffer(NewWidth, NewHeight: Integer);
var
  AllLines, Reflowed: TList<TTerminalLine>;
  Glyphs: TList<TTerminalChar>;
  Source, Dest: TTerminalLine;
  I, J, K, ChainStart, ChainEnd, Limit, Col, CellWidth, ActiveLast: Integer;
  OldCursorAbs, CursorLogicalOffset, ChainColumns: Integer;
  NewCursorAbs, NewCursorX, OutputStart, ScreenStart: Integer;
  OldViewportAnchor, NewViewportAnchor, AnchorLogicalOffset: Integer;
  TrimCount: Integer;
  CursorInChain, AnchorInChain: Boolean;
  BlankAttributes: TCharAttributes;

  function NewBlankLine: TTerminalLine;
  var
    X: Integer;
  begin
    Result := Default(TTerminalLine);
    SetLength(Result.Cells, NewWidth);
    for X := 0 to NewWidth - 1 do
    begin
      Result.Cells[X].Char := ' ';
      Result.Cells[X].Attributes := BlankAttributes;
      Result.Cells[X].Width := 1;
    end;
  end;

  function LastUsedColumn(const ALine: TTerminalLine): Integer;
  begin
    Result := Min(FWidth, Length(ALine.Cells));
    while (Result > 0) and (ALine.Cells[Result - 1].Char = ' ') and
      (ALine.Cells[Result - 1].Width <> 0) do
      Dec(Result);
  end;

  function IsBlankLine(const ALine: TTerminalLine): Boolean;
  begin
    Result := LastUsedColumn(ALine) = 0;
  end;

begin
  BlankAttributes := TCharAttributes.Default(FTheme);
  AllLines := TList<TTerminalLine>.Create;
  Reflowed := TList<TTerminalLine>.Create;
  Glyphs := TList<TTerminalChar>.Create;
  try
    AllLines.Capacity := FScrollback.Count + FLines.Count;
    AllLines.AddRange(FScrollback);
    ActiveLast := EnsureRange(FCursor.Y, 0, FLines.Count - 1);
    for I := FLines.Count - 1 downto ActiveLast + 1 do
      if not IsBlankLine(FLines[I]) then
      begin
        ActiveLast := I;
        Break;
      end;
    for I := 0 to ActiveLast do
      AllLines.Add(FLines[I]);
    OldCursorAbs := FScrollback.Count + FCursor.Y;
    if FViewportOffset > 0 then
      OldViewportAnchor := Max(0, FScrollback.Count - FViewportOffset)
    else
      OldViewportAnchor := -1;
    NewCursorAbs := 0;
    NewCursorX := 0;
    NewViewportAnchor := -1;

    I := 0;
    while I < AllLines.Count do
    begin
      ChainStart := I;
      ChainEnd := I;
      while (ChainEnd < AllLines.Count - 1) and
        AllLines[ChainEnd].IsWrapped do
        Inc(ChainEnd);

      Glyphs.Clear;
      ChainColumns := 0;
      CursorLogicalOffset := 0;
      AnchorLogicalOffset := 0;
      CursorInChain := (OldCursorAbs >= ChainStart) and
        (OldCursorAbs <= ChainEnd);
      AnchorInChain := (OldViewportAnchor >= ChainStart) and
        (OldViewportAnchor <= ChainEnd);

      for J := ChainStart to ChainEnd do
      begin
        Source := AllLines[J];
        if Source.IsWrapped then
          Limit := Min(FWidth, Length(Source.Cells))
        else
          Limit := LastUsedColumn(Source);

        if J = OldCursorAbs then
        begin
          Limit := Max(Limit, Min(FCursor.X, FWidth));
          CursorLogicalOffset := ChainColumns + Min(FCursor.X, FWidth);
        end;
        if J = OldViewportAnchor then
          AnchorLogicalOffset := ChainColumns;

        for K := 0 to Limit - 1 do
          if Source.Cells[K].Width <> 0 then
            Glyphs.Add(Source.Cells[K]);
        Inc(ChainColumns, Limit);
      end;

      OutputStart := Reflowed.Count;
      Dest := NewBlankLine;
      Col := 0;
      for K := 0 to Glyphs.Count - 1 do
      begin
        CellWidth := Max(1, Glyphs[K].Width);
        if CellWidth > NewWidth then
          CellWidth := NewWidth;
        if Col + CellWidth > NewWidth then
        begin
          Dest.IsWrapped := True;
          Reflowed.Add(Dest);
          Dest := NewBlankLine;
          Col := 0;
        end;
        Dest.Cells[Col] := Glyphs[K];
        Dest.Cells[Col].Width := CellWidth;
        if CellWidth = 2 then
        begin
          Dest.Cells[Col + 1].Char := '';
          Dest.Cells[Col + 1].Attributes := Glyphs[K].Attributes;
          Dest.Cells[Col + 1].Width := 0;
        end;
        Inc(Col, CellWidth);
      end;
      Reflowed.Add(Dest);

      if CursorInChain then
      begin
        if (CursorLogicalOffset > 0) and
          ((CursorLogicalOffset mod NewWidth) = 0) then
        begin
          NewCursorAbs := OutputStart + (CursorLogicalOffset div NewWidth) - 1;
          NewCursorX := NewWidth;
        end
        else
        begin
          NewCursorAbs := OutputStart + (CursorLogicalOffset div NewWidth);
          NewCursorX := CursorLogicalOffset mod NewWidth;
        end;
      end;
      if AnchorInChain then
        NewViewportAnchor := OutputStart +
          (AnchorLogicalOffset div NewWidth);

      I := ChainEnd + 1;
    end;

    while Reflowed.Count < NewHeight do
      Reflowed.Add(NewBlankLine);

    ScreenStart := Max(0, Reflowed.Count - NewHeight);
    FScrollback.Clear;
    for I := 0 to ScreenStart - 1 do
      FScrollback.Add(Reflowed[I]);
    TrimCount := Min(FScrollback.Count,
      Max(0, FScrollback.Count - FMaxScrollback));
    if TrimCount > 0 then
    begin
      FScrollback.DeleteRange(0, TrimCount);
      Dec(NewCursorAbs, TrimCount);
      if NewViewportAnchor >= 0 then
        Dec(NewViewportAnchor, TrimCount);
    end;

    FLines.Clear;
    for I := ScreenStart to Reflowed.Count - 1 do
      FLines.Add(Reflowed[I]);

    FCursor.X := EnsureRange(NewCursorX, 0, NewWidth);
    FCursor.Y := EnsureRange(NewCursorAbs - FScrollback.Count, 0,
      NewHeight - 1);
    if NewViewportAnchor >= 0 then
      FViewportOffset := EnsureRange(FScrollback.Count - NewViewportAnchor,
        0, FScrollback.Count)
    else
      FViewportOffset := 0;
    FHasSelection := False;
  finally
    Glyphs.Free;
    Reflowed.Free;
    AllLines.Free;
  end;
end;

procedure TTerminalBuffer.Resize(NewWidth, NewHeight: Integer);
var
  I, J: Integer;
  NewLine: TTerminalLine;
  AlternateCursor: TTerminalCursor;
begin
  if (NewWidth <= 0) or (NewHeight <= 0) then Exit;
  if (NewWidth = FWidth) and (NewHeight = FHeight) then Exit;

  if not FUseAlternateBuffer then
  begin
    ReflowMainBuffer(NewWidth, NewHeight);
    FWidth := NewWidth;
    FHeight := NewHeight;
    FScrollTop := 0;
    FScrollBottom := FHeight - 1;
    SetLength(FLinesDirty, FHeight);
    SetAllDirty;
    Exit;
  end;

  // Alternate screen is a disposable grid redrawn by fullscreen apps after
  // SIGWINCH. The saved main screen is independent and must be reflowed with
  // its own cursor; truncating its physical cells destroys shell history.
  AlternateCursor := FCursor;
  FCursor := FSavedCursorMain;
  ReflowMainBuffer(NewWidth, NewHeight);
  FSavedCursorMain := FCursor;
  FCursor := AlternateCursor;

  while FAlternateBuffer.Count > NewHeight do
    FAlternateBuffer.Delete(FAlternateBuffer.Count - 1);
  while FAlternateBuffer.Count < NewHeight do
    FAlternateBuffer.Add(CreateBlankLine);

  for I := 0 to FAlternateBuffer.Count - 1 do
  begin
    NewLine := FAlternateBuffer[I];
    if NewWidth > Length(NewLine.Cells) then
    begin
      J := Length(NewLine.Cells);
      SetLength(NewLine.Cells, NewWidth);
      while J < NewWidth do
      begin
        NewLine.Cells[J].Char := ' ';
        NewLine.Cells[J].Attributes := TCharAttributes.Default(FTheme);
        NewLine.Cells[J].Width := 1;
        Inc(J);
      end;
    end
    else
      SetLength(NewLine.Cells, NewWidth);
    NewLine.IsWrapped := False;
    FAlternateBuffer[I] := NewLine;
  end;

  FWidth := NewWidth;
  FHeight := NewHeight;
  FCursor.X := EnsureRange(FCursor.X, 0, FWidth - 1);
  FCursor.Y := EnsureRange(FCursor.Y, 0, FHeight - 1);
  FScrollTop := 0;
  FScrollBottom := FHeight - 1;
  FSavedScrollTopMain := 0;
  FSavedScrollBottomMain := FHeight - 1;
  SetLength(FLinesDirty, FHeight);
  SetAllDirty;
  Exit;
end;

procedure TTerminalBuffer.ProcessCommand(const Cmd: TAnsiCommand);
var
  N, M: Integer;
begin
  case Cmd.Command of
    apcPrintChar:
      WriteChar(Cmd.Char, Cmd.Attributes);
    
    apcCursorUp:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        MoveCursorRelative(0, -N);
      end;
    
    apcCursorDown:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        MoveCursorRelative(0, N);
      end;
    
    apcCursorForward:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        MoveCursorRelative(N, 0);
      end;
    
    apcCursorBack:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        MoveCursorRelative(-N, 0);
      end;
    
    apcCursorNextLine:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        FCursor.X := 0;
        MoveCursorRelative(0, N);
      end;
    
    apcCursorPrevLine:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        FCursor.X := 0;
        MoveCursorRelative(0, -N);
      end;
    
    apcCursorHorizontalAbs:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Cmd.Params[0];
        FCursor.X := EnsureRange(N - 1, 0, FWidth - 1);
      end;
    
    apcCursorPosition:
      begin
        N := 1; M := 1;
        if Length(Cmd.Params) > 0 then N := Cmd.Params[0];
        if Length(Cmd.Params) > 1 then M := Cmd.Params[1];
        MoveCursor(M - 1, N - 1);
      end;
    
    apcVerticalPositionAbs:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Cmd.Params[0];
        FCursor.Y := EnsureRange(N - 1, 0, FHeight - 1);
      end;
    
    apcEraseDisplay:
      begin
        N := 0;
        if Length(Cmd.Params) > 0 then N := Cmd.Params[0];
        case N of
          0: begin
               ClearLine(FCursor.Y, 0);
               for M := FCursor.Y + 1 to FHeight - 1 do
                 ClearLine(M, 2);
             end;
          1: begin
               for M := 0 to FCursor.Y - 1 do
                 ClearLine(M, 2);
               ClearLine(FCursor.Y, 1);
             end;
          2: Clear;
          3: begin
               (* ESC[3J - xterm-расширение "erase saved lines": именно эту
                  последовательность шлёт `clear` в современных дистрибутивах
                  (E3-capability в terminfo). Помимо видимого экрана нужно
                  стирать ещё и историю, иначе `clear` выглядит рабочим, а
                  scrollback молча продолжает копиться. *)
               Clear;
               FScrollback.Clear;
               ResetViewport;
             end;
        end;
      end;
    
    apcEraseLine:
      begin
        N := 0;
        if Length(Cmd.Params) > 0 then N := Cmd.Params[0];
        ClearLine(FCursor.Y, N);
      end;
    
    apcEraseChar:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        EraseChar(FCursor.X, FCursor.Y, N);
      end;
    
    apcScrollUp:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        InternalScrollUp(FScrollTop, FScrollBottom, N);
      end;
    
    apcScrollDown:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        InternalScrollDown(FScrollTop, FScrollBottom, N);
      end;
    
    apcInsertLine:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        InsertLine(FCursor.Y, N);
      end;
    
    apcDeleteLine:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        DeleteLine(FCursor.Y, N);
      end;
    
    apcInsertChar:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        InsertChar(FCursor.X, FCursor.Y, N);
      end;
    
    apcDeleteChar:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        DeleteChar(FCursor.X, FCursor.Y, N);
      end;
    
    apcRepeatChar:
      begin
        N := 1;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        for M := 1 to N do
          WriteChar(FLastChar, Cmd.Attributes);
      end;
    
    apcSetScrollingRegion:
      begin
        N := 1; M := FHeight;
        if Length(Cmd.Params) > 0 then N := Max(1, Cmd.Params[0]);
        if Length(Cmd.Params) > 1 then M := Min(Cmd.Params[1], FHeight);
        FScrollTop := N - 1;
        FScrollBottom := M - 1;
        MoveCursor(0, 0);
      end;
    
    apcSoftTerminalReset:
      begin
        FScrollTop := 0;
        FScrollBottom := FHeight - 1;
        FCurrentAttributes.Reset(FTheme);
        FCursor.X := 0;
        FCursor.Y := 0;
        FCursor.Visible := True;
        FCursor.Shape := tcsBlock;
        FCursor.Blink := True;
        FAppCursorKeys := False;
        FMouseModes := [];
        FBracketedPaste := False;
      end;
    
    apcSaveCursorPosition:
      begin
        FSavedCursor.X := FCursor.X;
        FSavedCursor.Y := FCursor.Y;
      end;
    
    apcRestoreCursorPosition:
      begin
        FCursor.X := FSavedCursor.X;
        FCursor.Y := FSavedCursor.Y;
      end;
    
    apcSetPrivateMode:
      begin
        for N in Cmd.Params do
          case N of
            1: FAppCursorKeys := True;
            25: FCursor.Visible := True;
            1000: Include(FMouseModes, mtm1000_Click);
            1002: Include(FMouseModes, mtm1002_Wheel);
            1003: Include(FMouseModes, mtm1003_Any);
            1006: Include(FMouseModes, mtm1006_SGR);
            1049, 47, 1047: SwitchToAlternateBuffer;
            2004: FBracketedPaste := True;
          end;
      end;
    
    apcResetPrivateMode:
      begin
        for N in Cmd.Params do
          case N of
            1: FAppCursorKeys := False;
            25: FCursor.Visible := False;
            1000: Exclude(FMouseModes, mtm1000_Click);
            1002: Exclude(FMouseModes, mtm1002_Wheel);
            1003: Exclude(FMouseModes, mtm1003_Any);
            1006: Exclude(FMouseModes, mtm1006_SGR);
            1049, 47, 1047: SwitchToMainBuffer;
            2004: FBracketedPaste := False;
          end;
      end;

    apcSetCursorStyle:
      begin
        N := 0;
        if Length(Cmd.Params) > 0 then
          N := Cmd.Params[0];
        case N of
          0, 1:
            begin
              FCursor.Shape := tcsBlock;
              FCursor.Blink := True;
            end;
          2:
            begin
              FCursor.Shape := tcsBlock;
              FCursor.Blink := False;
            end;
          3:
            begin
              FCursor.Shape := tcsUnderline;
              FCursor.Blink := True;
            end;
          4:
            begin
              FCursor.Shape := tcsUnderline;
              FCursor.Blink := False;
            end;
          5:
            begin
              FCursor.Shape := tcsBar;
              FCursor.Blink := True;
            end;
          6:
            begin
              FCursor.Shape := tcsBar;
              FCursor.Blink := False;
            end;
        end;
      end;
    
    apcReverseIndex:
      begin
        if FCursor.Y = FScrollTop then
          ScrollDown(1)
        else if FCursor.Y > 0 then
          Dec(FCursor.Y);
      end;
    
    apcDeviceAttributes:
      (* Ответ на "Send Device Attributes" (CSI c).
         Представляемся как VT100 с поддержкой Advanced Video. *)
      if Assigned(FOnResponse) then
        FOnResponse(#27'[?1;2c');

    apcDeviceStatusReport:
      begin
        N := 0;
        if Length(Cmd.Params) > 0 then N := Cmd.Params[0];
        if Assigned(FOnResponse) then
          case N of
            5: FOnResponse(#27'[0n');  // статус терминала: OK
            6: FOnResponse(Format(#27'[%d;%dR',
                 [FCursor.Y + 1, FCursor.X + 1]));  // позиция курсора
          end;
      end;

    apcSetGraphicsMode:
      FCurrentAttributes := Cmd.Attributes;
  end;
end;

function TTerminalBuffer.GetTotalLinesCount: Integer;
begin
  if FUseAlternateBuffer then
    Result := FAlternateBuffer.Count
  else
    Result := FScrollback.Count + FLines.Count;
end;

function TTerminalBuffer.ScreenYToAbsolute(ScreenY: Integer): Integer;
begin
  if FUseAlternateBuffer then
    Result := ScreenY
  else
    Result := (FScrollback.Count + ScreenY) - FViewportOffset;
end;

function TTerminalBuffer.GetLineByAbsoluteIndex(Index: Integer): TTerminalLine;
begin
  if FUseAlternateBuffer then
  begin
    if InRange(Index, 0, FAlternateBuffer.Count - 1) then
      Exit(FAlternateBuffer[Index]);
  end
  else if InRange(Index, 0, FScrollback.Count - 1) then
    Exit(FScrollback[Index])
  else if InRange(Index - FScrollback.Count, 0, FLines.Count - 1) then
    Exit(FLines[Index - FScrollback.Count]);
  Result := Default(TTerminalLine);
end;

procedure TTerminalBuffer.NormalizeSelection;
var
  Swap: TPoint;
begin
  if (FSelStart.Y > FSelEnd.Y) or
    ((FSelStart.Y = FSelEnd.Y) and (FSelStart.X > FSelEnd.X)) then
  begin
    Swap := FSelStart;
    FSelStart := FSelEnd;
    FSelEnd := Swap;
  end;
end;

procedure TTerminalBuffer.SetSelection(StartX, StartY, EndX, EndY: Integer);
var
  Line: TTerminalLine;
  MaxY, OldStartY, OldEndY: Integer;
  HadSelection: Boolean;
begin
  HadSelection := FHasSelection;
  OldStartY := FSelStart.Y;
  OldEndY := FSelEnd.Y;
  MaxY := GetTotalLinesCount - 1;
  if MaxY < 0 then
  begin
    ClearSelection;
    Exit;
  end;
  StartY := EnsureRange(StartY, 0, MaxY);
  EndY := EnsureRange(EndY, 0, MaxY);
  FSelStart := TPoint.Create(StartX, StartY);
  FSelEnd := TPoint.Create(EndX, EndY);
  NormalizeSelection;

  Line := GetLineByAbsoluteIndex(FSelStart.Y);
  if Length(Line.Cells) > 0 then
  begin
    FSelStart.X := EnsureRange(FSelStart.X, 0, High(Line.Cells));
    if (FSelStart.X > 0) and (Line.Cells[FSelStart.X].Width = 0) then
      Dec(FSelStart.X);
  end
  else
    FSelStart.X := 0;

  Line := GetLineByAbsoluteIndex(FSelEnd.Y);
  if Length(Line.Cells) > 0 then
  begin
    FSelEnd.X := EnsureRange(FSelEnd.X, 0, High(Line.Cells));
    if (FSelEnd.X > 0) and (Line.Cells[FSelEnd.X].Width = 0) then
      Dec(FSelEnd.X);
  end
  else
    FSelEnd.X := 0;

  FHasSelection := True;
  if HadSelection then
    SetSelectionRangeDirty(OldStartY, OldEndY);
  SetSelectionRangeDirty(FSelStart.Y, FSelEnd.Y);
end;

procedure TTerminalBuffer.SetSelectionRangeDirty(StartAbsY,
  EndAbsY: Integer);
var
  FirstScreenY, LastScreenY, ScreenOrigin, Temp: Integer;
begin
  if StartAbsY > EndAbsY then
  begin
    Temp := StartAbsY;
    StartAbsY := EndAbsY;
    EndAbsY := Temp;
  end;
  if FUseAlternateBuffer then
    ScreenOrigin := 0
  else
    ScreenOrigin := FScrollback.Count - FViewportOffset;
  FirstScreenY := Max(0, StartAbsY - ScreenOrigin);
  LastScreenY := Min(FHeight - 1, EndAbsY - ScreenOrigin);
  if FirstScreenY <= LastScreenY then
    SetRangeDirty(FirstScreenY, LastScreenY);
end;

procedure TTerminalBuffer.ClearSelection;
begin
  if FHasSelection then
  begin
    SetSelectionRangeDirty(FSelStart.Y, FSelEnd.Y);
    FHasSelection := False;
  end;
end;

function TTerminalBuffer.IsCellSelected(X, ScreenY: Integer): Boolean;
var
  AbsY: Integer;
begin
  if not FHasSelection then
    Exit(False);
  AbsY := ScreenYToAbsolute(ScreenY);
  if (AbsY > FSelStart.Y) and (AbsY < FSelEnd.Y) then
    Exit(True);
  if (AbsY = FSelStart.Y) and (AbsY = FSelEnd.Y) then
    Exit((X >= FSelStart.X) and (X <= FSelEnd.X));
  if AbsY = FSelStart.Y then
    Exit(X >= FSelStart.X);
  if AbsY = FSelEnd.Y then
    Exit(X <= FSelEnd.X);
  Result := False;
end;

function TTerminalBuffer.GetSelectedText: string;
var
  X, StartX, EndX, AbsY: Integer;
  Line: TTerminalLine;
  ResultStr: TStringBuilder;

begin
  if not FHasSelection then
    Exit('');
    
  ResultStr := TStringBuilder.Create;
  try
    for AbsY := FSelStart.Y to FSelEnd.Y do
    begin
      Line := GetLineByAbsoluteIndex(AbsY);
      if AbsY = FSelStart.Y then
        StartX := FSelStart.X
      else
        StartX := 0;
      if AbsY = FSelEnd.Y then
        EndX := FSelEnd.X
      else
        EndX := Length(Line.Cells) - 1;
      StartX := EnsureRange(StartX, 0, Length(Line.Cells));
      EndX := Min(EndX, High(Line.Cells));
      if (AbsY < FSelEnd.Y) and not Line.IsWrapped then
        while (EndX >= StartX) and (Line.Cells[EndX].Char = ' ') and
          (Line.Cells[EndX].Width <> 0) do
          Dec(EndX);
      for X := StartX to EndX do
      begin
        // Пропускаем "хвосты" wide-символов
        if (Line.Cells[X].Width > 0) then
          ResultStr.Append(Line.Cells[X].Char);
      end;
      if (AbsY < FSelEnd.Y) and not Line.IsWrapped then
        ResultStr.Append(sLineBreak);
    end;
    Result := ResultStr.ToString;
  finally
    ResultStr.Free;
  end;
end;

end.
