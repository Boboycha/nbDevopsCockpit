unit Terminal.Renderer;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  System.Character, System.Math.Vectors,
  System.Generics.Collections,
  FMX.Types, FMX.Graphics, FMX.TextLayout,
  Terminal.Types, Terminal.Buffer, System.UIConsts,
  Terminal.Theme;

type
  TTerminalRenderer = class
  private
    FBuffer: TTerminalBuffer;
    FCharWidth: Single;
    FCharHeight: Single;
    (* Естественная высота глифа без межстрочного зазора; используется для
       вертикального центрирования текста внутри увеличенной строки и для
       размера кэша глифов *)
    FNaturalCharHeight: Single;
    (* Половина межстрочного зазора - смещение вниз, применяемое только к
       отрисовке текста (не к фону и не к псевдографике, которая обязана
       стыковаться между строками без разрывов) *)
    FLineGapOffset: Single;
    FScaleX: Single;
    FScaleY: Single;
    FContentScale: Single;
    FUIScale: Single;
    FAscentOffset: Single;
    FFontFamily: string;
    FFontSize: Single;
    FFontWidthScale: Single;
    FFontHeightScale: Single;
    FFontBold: Boolean;
    FFontItalic: Boolean;
    FShowCursor: Boolean;
    FCursorBlinkState: Boolean;
    FSemanticHighlighting: Boolean;
    FTheme: TTerminalTheme;
    FSemanticColors: TArray<TAlphaColor>;
    FSemanticBold: TArray<Boolean>;
    FSemanticText: string;

    (* Растеризация и измерение глифов - один переиспользуемый layout *)
    FTextLayout: TTextLayout;
    (* Кэш готовых глифов: символ+цвет+стиль+ширина -> битмап в физических
       пикселях. Позволяет класть каждый символ строго в ячейку сетки
       (DirectWrite сам по себе double-space шрифты кладёт по своим advance). *)
    FGlyphCache: TObjectDictionary<string, TBitmap>;

    FResourcesValid: Boolean;
    (* Retained back-buffer. Два битмапа (ping-pong): самокопирование канваса
       в FMX небезопасно, поэтому сдвиг кадра при скролле делается копией
       текущего кадра в соседний битмап. *)
    FBackBuffers: array [0 .. 1] of TBitmap;
    FBackIndex: Integer;
    FBackBufferWidth: Integer;
    FBackBufferHeight: Integer;

    function GetEffectiveForeground(const Attr: TCharAttributes): TAlphaColor;
    function SameVisualAttributes(const Left,
      Right: TCharAttributes): Boolean; inline;
    procedure UpdateResources;
    procedure CheckBackBuffer(Width, Height: Integer);
    procedure SetScale(const Value: Single);
    procedure SetContentScale(const Value: Single);
    procedure SetUIScale(const Value: Single);
    procedure SetFontWidthScale(const Value: Single);
    procedure SetFontHeightScale(const Value: Single);
    function SnapToPixel(const Value: Single): Single;
    function EffectiveFontSize: Single;
    function GlyphWidthFactor: Single;
    function BlendColor(const Overlay, Base: TAlphaColor): TAlphaColor;
    procedure BuildSemanticColors(const Line: TTerminalLine;
      var Colors: TArray<TAlphaColor>; var Bold: TArray<Boolean>);
    procedure SetSemanticHighlighting(const Value: Boolean);
    procedure InvalidateBackBuffers;

    function GetGlyphBitmap(const Ch: string; CellCount: Integer;
      Bold, Italic: Boolean; Color: TAlphaColor): TBitmap;
    procedure DrawGlyph(Canvas: TCanvas; const Ch: string; CellCount: Integer;
      Bold, Italic: Boolean; X, Y: Single; Color: TAlphaColor);
    procedure RenderBoxDrawingChar(Canvas: TCanvas; Ch: string;
      X, Y, W, H: Single; Color: TAlphaColor);

  public
    constructor Create(ABuffer: TTerminalBuffer; ATheme: TTerminalTheme);
    destructor Destroy; override;

    procedure Render(Canvas: TCanvas; const Bounds: TRectF);
    procedure RenderLine(Canvas: TCanvas; LineIndex: Integer;
      const Bounds: TRectF; OffsetY: Single; DefaultBG: TAlphaColor);
    procedure RenderCursor(Canvas: TCanvas; const Bounds: TRectF);

    procedure MeasureChar;
    procedure ToggleCursorBlink;
    procedure RenderDebugInfo(Canvas: TCanvas; const Bounds: TRectF);
    procedure SetTheme(ATheme: TTerminalTheme);
    procedure InvalidateResources;

    property CharWidth: Single read FCharWidth;
    property CharHeight: Single read FCharHeight;
    property FontFamily: string read FFontFamily write FFontFamily;
    property FontSize: Single read FFontSize write FFontSize;
    property FontWidthScale: Single read FFontWidthScale
      write SetFontWidthScale;
    property FontHeightScale: Single read FFontHeightScale
      write SetFontHeightScale;
    property FontBold: Boolean read FFontBold write FFontBold;
    property FontItalic: Boolean read FFontItalic write FFontItalic;
    property ShowCursor: Boolean read FShowCursor write FShowCursor;
    property Scale: Single read FScaleX write SetScale;
    property ContentScale: Single read FContentScale write SetContentScale;
    property UIScale: Single read FUIScale write SetUIScale;
    property SemanticHighlighting: Boolean read FSemanticHighlighting
      write SetSemanticHighlighting;
  end;

implementation

const
  (* Верхняя граница кэша глифов. htop/mc с богатой раскраской дают
     сотни уникальных пар символ+цвет; при переполнении кэш очищается
     целиком - редкое событие, самовосстанавливается за кадр. *)
  GlyphCacheLimit = 4096;
  (* Запас по высоте битмапа глифа: эмодзи и фолбэк-гарнитуры (CJK)
     имеют межстрочник выше ячейки терминала. *)
  GlyphHeightFactor = 1.5;
  (* Межстрочный интервал сверх голой высоты глифа - без этого строки
     стоят вплотную и текст выглядит теснее, чем в эталонных терминалах *)
  LineHeightFactor = 1.18;
  (* Базовый вес текста. Skia-версия рендерера создавала шрифт с весом
     Medium (не Regular); без этого текст выглядит заметно тоньше. *)
  BaseFontWeight = TFontWeight.Medium;
  BoldFontWeight = TFontWeight.Bold;

{ TTerminalRenderer }

constructor TTerminalRenderer.Create(ABuffer: TTerminalBuffer;
  ATheme: TTerminalTheme);
begin
  inherited Create;
  FBuffer := ABuffer;
  FTheme := ATheme;
{$IFDEF LINUX}
  FFontFamily := 'Monospace';
{$ELSEIF DEFINED(MACOS)}
  FFontFamily := 'Menlo';
{$ELSE}
  FFontFamily := 'Source Code Pro';
{$ENDIF}
  FFontSize := 13;
  FFontWidthScale := 1.0;
  FFontHeightScale := 1.0;
  FFontBold := False;
  FFontItalic := False;
  FShowCursor := True;
  FCursorBlinkState := True;
  FSemanticHighlighting := False;
  FAscentOffset := 0;
  FResourcesValid := False;
  FScaleX := 1.0;
  FScaleY := 1.0;
  FContentScale := 1.0;
  FUIScale := 1.0;
  FBackBuffers[0] := nil;
  FBackBuffers[1] := nil;
  FBackIndex := 0;
  FBackBufferWidth := 0;
  FBackBufferHeight := 0;

  FTextLayout := TTextLayoutManager.DefaultTextLayout.Create;
  FGlyphCache := TObjectDictionary<string, TBitmap>.Create([doOwnsValues]);

  MeasureChar;
end;

destructor TTerminalRenderer.Destroy;
begin
  FGlyphCache.Free;
  FTextLayout.Free;
  FBackBuffers[0].Free;
  FBackBuffers[1].Free;
  inherited;
end;

procedure TTerminalRenderer.SetTheme(ATheme: TTerminalTheme);
begin
  FTheme := ATheme;
  FGlyphCache.Clear;
  FBuffer.SetAllDirty;
end;

procedure TTerminalRenderer.InvalidateResources;
begin
  FResourcesValid := False;
  FGlyphCache.Clear;
end;

procedure TTerminalRenderer.InvalidateBackBuffers;
begin
  FBackBufferWidth := 0;
  FBackBufferHeight := 0;
end;

procedure TTerminalRenderer.SetScale(const Value: Single);
begin
  if not SameValue(FScaleX, Value, 0.001) then
  begin
    FScaleX := Value;
    FScaleY := Value;
    MeasureChar;
    InvalidateBackBuffers;
    FBuffer.SetAllDirty;
  end;
end;

procedure TTerminalRenderer.SetFontWidthScale(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := EnsureRange(Value, 0.75, 1.50);
  if SameValue(FFontWidthScale, NewValue, 0.001) then
    Exit;
  FFontWidthScale := NewValue;
  MeasureChar;
  InvalidateBackBuffers;
  FBuffer.SetAllDirty;
end;

procedure TTerminalRenderer.SetFontHeightScale(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := EnsureRange(Value, 0.75, 1.50);
  if SameValue(FFontHeightScale, NewValue, 0.001) then
    Exit;
  FFontHeightScale := NewValue;
  MeasureChar;
  InvalidateBackBuffers;
  FBuffer.SetAllDirty;
end;

procedure TTerminalRenderer.SetSemanticHighlighting(const Value: Boolean);
begin
  if FSemanticHighlighting = Value then
    Exit;
  FSemanticHighlighting := Value;
  FBuffer.SetAllDirty;
end;

procedure TTerminalRenderer.BuildSemanticColors(const Line: TTerminalLine;
  var Colors: TArray<TAlphaColor>; var Bold: TArray<Boolean>);
var
  I, StartPos, EndPos, HostStart, HostEnd: Integer;

  function IsHostChar(const C: Char): Boolean;
  begin
    Result := C.IsLetterOrDigit or CharInSet(C, ['.', '-']);
  end;

  function IsWordChar(const C: Char): Boolean;
  begin
    Result := C.IsLetterOrDigit or (C = '_');
  end;

  (* Цвет и жирность для уровня логирования по его имени (без учёта
     регистра). Список покрывает syslog/journald и типичные логгеры
     приложений (Python logging, log4j, npm, etc). *)
  function LogLevelColor(const Word: string; out AColor: TAlphaColor;
    out ABold: Boolean): Boolean;
  var
    Upper: string;
  begin
    Upper := Word.ToUpper;
    ABold := True;
    Result := True;
    if (Upper = 'TRACE') or (Upper = 'VERBOSE') then
      AColor := FTheme.AnsiColors[8]
    else if (Upper = 'DEBUG') or (Upper = 'DBG') then
      AColor := FTheme.AnsiColors[12]
    else if (Upper = 'INFO') or (Upper = 'NOTICE') then
      AColor := FTheme.AnsiColors[10]
    else if (Upper = 'WARN') or (Upper = 'WARNING') then
      AColor := FTheme.AnsiColors[11]
    else if (Upper = 'ERROR') or (Upper = 'ERR') or (Upper = 'FATAL') or
      (Upper = 'CRITICAL') or (Upper = 'CRIT') or (Upper = 'EMERG') or
      (Upper = 'ALERT') or (Upper = 'PANIC') then
      AColor := FTheme.AnsiColors[9]
    else
      Result := False;
  end;

  function IsIPv4(AStart, AEnd: Integer): Boolean;
  var
    P, OctetCount, DigitCount, Value: Integer;
  begin
    OctetCount := 0;
    P := AStart;
    while P <= AEnd do
    begin
      Value := 0;
      DigitCount := 0;
      while (P <= AEnd) and FSemanticText[P].IsDigit do
      begin
        Inc(DigitCount);
        if DigitCount > 3 then
          Exit(False);
        Value := Value * 10 + Ord(FSemanticText[P]) - Ord('0');
        Inc(P);
      end;
      if (DigitCount = 0) or (Value > 255) then
        Exit(False);
      Inc(OctetCount);
      if P <= AEnd then
      begin
        if FSemanticText[P] <> '.' then
          Exit(False);
        Inc(P);
      end;
    end;
    Result := OctetCount = 4;
  end;

  procedure MarkRange(AStart, AEnd: Integer; AColor: TAlphaColor;
    AWordBold: Boolean = False);
  var
    K: Integer;
  begin
    for K := Max(0, AStart) to Min(AEnd, High(Colors)) do
    begin
      Colors[K] := AColor;
      if AWordBold then
        Bold[K] := True;
    end;
  end;

begin
  SetLength(Colors, 0);
  SetLength(Bold, 0);
  if (not FSemanticHighlighting) or FBuffer.IsAlternateBuffer then
    Exit;
  SetLength(Colors, Length(Line.Cells));
  SetLength(Bold, Length(Line.Cells));
  if Length(Colors) > 0 then
  begin
    FillChar(Colors[0], Length(Colors) * SizeOf(TAlphaColor), 0);
    FillChar(Bold[0], Length(Bold) * SizeOf(Boolean), 0);
  end;

  SetLength(FSemanticText, Length(Line.Cells));
  for I := 0 to High(Line.Cells) do
    if Line.Cells[I].Char = '' then
      FSemanticText[I + 1] := ' '
    else
      FSemanticText[I + 1] := Line.Cells[I].Char[1];

  { Host names in URLs. Keep scheme, port and punctuation in the normal color. }
  I := 1;
  while I <= Length(FSemanticText) - 2 do
  begin
    if (FSemanticText[I] = ':') and (FSemanticText[I + 1] = '/') and
      (FSemanticText[I + 2] = '/') then
    begin
      HostStart := I + 3;
      HostEnd := HostStart;
      while (HostEnd <= Length(FSemanticText)) and
        IsHostChar(FSemanticText[HostEnd]) do
        Inc(HostEnd);
      if HostEnd > HostStart then
        MarkRange(HostStart - 1, HostEnd - 2, FTheme.AnsiColors[15]);
      I := HostEnd;
    end
    else
      Inc(I);
  end;

  { IPv4 addresses everywhere, including URL hosts and "Last login". }
  I := 1;
  while I <= Length(FSemanticText) do
  begin
    if FSemanticText[I].IsDigit and ((I = 1) or
      not (FSemanticText[I - 1].IsDigit or
      (FSemanticText[I - 1] = '.'))) then
    begin
      StartPos := I;
      while (I <= Length(FSemanticText)) and
        (FSemanticText[I].IsDigit or (FSemanticText[I] = '.')) do
        Inc(I);
      EndPos := I - 1;
      if IsIPv4(StartPos, EndPos) then
        MarkRange(StartPos - 1, EndPos - 1, FTheme.AnsiColors[9]);
    end
    else
      Inc(I);
  end;

  { Уровни логирования (DEBUG, WARN, ERROR и т.п.) как целые слова. }
  I := 1;
  while I <= Length(FSemanticText) do
  begin
    if IsWordChar(FSemanticText[I]) and ((I = 1) or
      not IsWordChar(FSemanticText[I - 1])) then
    begin
      StartPos := I;
      while (I <= Length(FSemanticText)) and IsWordChar(FSemanticText[I]) do
        Inc(I);
      EndPos := I - 1;
      var LevelColor: TAlphaColor;
      var LevelBold: Boolean;
      if LogLevelColor(Copy(FSemanticText, StartPos, EndPos - StartPos + 1),
        LevelColor, LevelBold) then
        MarkRange(StartPos - 1, EndPos - 1, LevelColor, LevelBold);
    end
    else
      Inc(I);
  end;
end;

procedure TTerminalRenderer.SetContentScale(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := Value;
  if NewValue <= 0 then
    NewValue := 1.0;

  if not SameValue(FContentScale, NewValue, 0.001) then
  begin
    FContentScale := NewValue;
    MeasureChar;
    InvalidateBackBuffers;
    FBuffer.SetAllDirty;
  end;
end;

procedure TTerminalRenderer.SetUIScale(const Value: Single);
var
  NewValue: Single;
begin
  NewValue := Value;
  if NewValue <= 0 then
    NewValue := 1.0;

  if not SameValue(FUIScale, NewValue, 0.001) then
  begin
    FUIScale := NewValue;
    MeasureChar;
    InvalidateBackBuffers;
    FBuffer.SetAllDirty;
  end;
end;

function TTerminalRenderer.SnapToPixel(const Value: Single): Single;
begin
  if FScaleX <= 0 then
    Result := Value
  else
    Result := Round(Value * FScaleX) / FScaleX;
end;

function TTerminalRenderer.EffectiveFontSize: Single;
begin
  Result := FFontSize * FUIScale * FFontHeightScale;
  if FContentScale > 0 then
    Result := Result / FContentScale;
  if FScaleX > 0 then
    Result := Max(1, Round(Result * FScaleX)) / FScaleX;
end;

function TTerminalRenderer.GlyphWidthFactor: Single;
begin
  (* Аналог Skia Font.ScaleX: горизонтальное сжатие/растяжение глифа.
     Высотная составляющая уже сидит в EffectiveFontSize. *)
  if FFontHeightScale > 0 then
    Result := FFontWidthScale / FFontHeightScale
  else
    Result := FFontWidthScale;
end;

function TTerminalRenderer.BlendColor(const Overlay,
  Base: TAlphaColor): TAlphaColor;
var
  A, InvA: UInt32;
  ORed, OGreen, OBlue, BRed, BGreen, BBlue: UInt32;
begin
  A := (UInt32(Overlay) shr 24) and $FF;
  InvA := 255 - A;
  ORed := (UInt32(Overlay) shr 16) and $FF;
  OGreen := (UInt32(Overlay) shr 8) and $FF;
  OBlue := UInt32(Overlay) and $FF;
  BRed := (UInt32(Base) shr 16) and $FF;
  BGreen := (UInt32(Base) shr 8) and $FF;
  BBlue := UInt32(Base) and $FF;
  Result := TAlphaColor($FF000000 or
    (((ORed * A + BRed * InvA + 127) div 255) shl 16) or
    (((OGreen * A + BGreen * InvA + 127) div 255) shl 8) or
    ((OBlue * A + BBlue * InvA + 127) div 255));
end;

procedure TTerminalRenderer.UpdateResources;
begin
  if FResourcesValid then
    Exit;

  FTextLayout.BeginUpdate;
  try
    FTextLayout.Font.Family := FFontFamily;
    FTextLayout.Font.Size := EffectiveFontSize;
    FTextLayout.Font.StyleExt := TFontStyleExt.Create(BaseFontWeight);
    FTextLayout.MaxSize := TPointF.Create(4096, 4096);
    FTextLayout.WordWrap := False;
    FTextLayout.HorizontalAlign := TTextAlign.Leading;
    FTextLayout.VerticalAlign := TTextAlign.Leading;
    FTextLayout.Padding.Rect := TRectF.Empty;
    FTextLayout.TopLeft := TPointF.Zero;
  finally
    FTextLayout.EndUpdate;
  end;
  FResourcesValid := True;
end;

procedure TTerminalRenderer.MeasureChar;
var
  RealWidth, RealHeight: Single;
begin
  InvalidateResources;
  UpdateResources;

  FTextLayout.BeginUpdate;
  try
    FTextLayout.Font.Family := FFontFamily;
    FTextLayout.Font.Size := EffectiveFontSize;
    FTextLayout.Font.StyleExt := TFontStyleExt.Create(BaseFontWeight);
    FTextLayout.Text := 'W';
  finally
    FTextLayout.EndUpdate;
  end;

  RealWidth := FTextLayout.TextWidth * GlyphWidthFactor;
  if RealWidth < 1 then
    RealWidth := 8;
  FCharWidth := SnapToPixel(RealWidth);   (* целые физические пиксели - нужно для чёткости и псевдографики *)
  if FCharWidth < 1 then
    FCharWidth := 8;

  RealHeight := FTextLayout.TextHeight;
  if RealHeight < 1 then
    RealHeight := 12;
  FNaturalCharHeight := SnapToPixel(RealHeight);
  FCharHeight := SnapToPixel(RealHeight * LineHeightFactor); (* целые физические пиксели, с межстрочным зазором *)
  if FCharHeight < FNaturalCharHeight then
    FCharHeight := FNaturalCharHeight;
  FLineGapOffset := SnapToPixel((FCharHeight - FNaturalCharHeight) / 2);

  (* У FMX-layout нет публичного ascent; 0.8 от естественной высоты глифа -
     стандартное приближение базовой линии, используется только для
     подчёркивания. Считается от FNaturalCharHeight, а не от FCharHeight,
     чтобы межстрочный зазор не сдвигал подчёркивание. *)
  FAscentOffset := SnapToPixel(FNaturalCharHeight * 0.8);
end;

function TTerminalRenderer.GetEffectiveForeground(const Attr: TCharAttributes): TAlphaColor;
begin
  if Attr.Inverse then
    Result := Attr.BackgroundColor
  else
    Result := Attr.ForegroundColor;
  if Attr.Faint then
    Result := MakeColor(Result, 0.45);
end;

function TTerminalRenderer.SameVisualAttributes(const Left,
  Right: TCharAttributes): Boolean;
begin
  Result :=
    (Left.ForegroundColor = Right.ForegroundColor) and
    (Left.BackgroundColor = Right.BackgroundColor) and
    (Left.ForegroundSource = Right.ForegroundSource) and
    (Left.BackgroundSource = Right.BackgroundSource) and
    (Left.ForegroundIndex = Right.ForegroundIndex) and
    (Left.BackgroundIndex = Right.BackgroundIndex) and
    (Left.Bold = Right.Bold) and
    (Left.Faint = Right.Faint) and
    (Left.Italic = Right.Italic) and
    (Left.Underline = Right.Underline) and
    (Left.Strikethrough = Right.Strikethrough) and
    (Left.Hidden = Right.Hidden) and
    (Left.Inverse = Right.Inverse);
end;

procedure TTerminalRenderer.CheckBackBuffer(Width, Height: Integer);
var
  PhysW, PhysH, I: Integer;
begin
  PhysW := Max(1, Round(Width  * FScaleX));
  PhysH := Max(1, Round(Height * FScaleX));
  if (FBackBuffers[FBackIndex] = nil) or (FBackBufferWidth <> PhysW) or
    (FBackBufferHeight <> PhysH) then
  begin
    FBackBufferWidth  := PhysW;
    FBackBufferHeight := PhysH;
    for I := 0 to 1 do
    begin
      if FBackBuffers[I] = nil then
        FBackBuffers[I] := TBitmap.Create(FBackBufferWidth, FBackBufferHeight)
      else
        FBackBuffers[I].SetSize(FBackBufferWidth, FBackBufferHeight);
      FBackBuffers[I].Clear(FTheme.DefaultBG);
    end;
    FBuffer.GetAndResetVisualScrollDelta;
    FBuffer.SetAllDirty;
  end;
end;

procedure TTerminalRenderer.RenderBoxDrawingChar(Canvas: TCanvas; Ch: string;
  X, Y, W, H: Single; Color: TAlphaColor);
var
  Cx, Cy: Single;
  Code: Integer;
  DrawUp, DrawDown, DrawLeft, DrawRight: Boolean;
begin
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := Color;
  Canvas.Stroke.Thickness := 1;
  Canvas.Stroke.Dash := TStrokeDash.Solid;
  Cx := Floor(X + (W / 2));
  Cy := Floor(Y + (H / 2));
  if Length(Ch) <> 1 then
    Exit;
  Code := Ord(Ch[1]);
  DrawUp := False;
  DrawDown := False;
  DrawLeft := False;
  DrawRight := False;

  case Code of
    $2500, $2501, $2504, $2505, $2508, $2509, $254C, $254D, $2550:
      begin
        DrawLeft := True;
        DrawRight := True;
      end;
    $2502, $2503, $2506, $2507, $250A, $250B, $2551:
      begin
        DrawUp := True;
        DrawDown := True;
      end;
    $250C..$250F, $2552..$2554:
      begin
        DrawDown := True;
        DrawRight := True;
      end;
    $2510..$2513, $2555..$2557:
      begin
        DrawDown := True;
        DrawLeft := True;
      end;
    $2514..$2517, $2558..$255A:
      begin
        DrawUp := True;
        DrawRight := True;
      end;
    $2518..$251B, $255B..$255D:
      begin
        DrawUp := True;
        DrawLeft := True;
      end;
    $251C..$2523, $255E..$2560:
      begin
        DrawUp := True;
        DrawDown := True;
        DrawRight := True;
      end;
    $2524..$252B, $2561..$2563:
      begin
        DrawUp := True;
        DrawDown := True;
        DrawLeft := True;
      end;
    $252C..$2533, $2564..$2566:
      begin
        DrawDown := True;
        DrawLeft := True;
        DrawRight := True;
      end;
    $2534..$253B, $2567..$2569:
      begin
        DrawUp := True;
        DrawLeft := True;
        DrawRight := True;
      end;
    $253C..$254B, $256A..$256C:
      begin
        DrawUp := True;
        DrawDown := True;
        DrawLeft := True;
        DrawRight := True;
      end;
  end;

  if DrawUp then
    Canvas.DrawLine(TPointF.Create(Cx, Cy), TPointF.Create(Cx, Y), 1);
  if DrawDown then
    Canvas.DrawLine(TPointF.Create(Cx, Cy), TPointF.Create(Cx, Y + H), 1);
  if DrawLeft then
    Canvas.DrawLine(TPointF.Create(Cx, Cy), TPointF.Create(X, Cy), 1);
  if DrawRight then
    Canvas.DrawLine(TPointF.Create(Cx, Cy), TPointF.Create(X + W, Cy), 1);
end;

function TTerminalRenderer.GetGlyphBitmap(const Ch: string; CellCount: Integer;
  Bold, Italic: Boolean; Color: TAlphaColor): TBitmap;
var
  CacheKey: string;
  PhysW, PhysH: Integer;
  UseBold, UseItalic: Boolean;
  Weight: TFontWeight;
  Slant: TFontSlant;
begin
  UseBold := Bold or FFontBold;
  UseItalic := Italic or FFontItalic;
  CacheKey := Ch + #1 + IntToHex(Color, 8) + #1 +
    Chr(Ord('0') + Ord(UseBold) + Ord(UseItalic) * 2) + #1 +
    IntToStr(CellCount);
  if FGlyphCache.TryGetValue(CacheKey, Result) then
    Exit;

  PhysW := Max(1, Round(CellCount * FCharWidth * FScaleX));
  PhysH := Max(1, Round(FNaturalCharHeight * GlyphHeightFactor * FScaleX));

  if UseBold then
    Weight := BoldFontWeight
  else
    Weight := BaseFontWeight;
  if UseItalic then
    Slant := TFontSlant.Italic
  else
    Slant := TFontSlant.Regular;

  Result := TBitmap.Create(PhysW, PhysH);
  try
    if Result.Canvas.BeginScene then
      try
        Result.Canvas.Clear(TAlphaColors.Null);
        (* Глиф растеризуется сразу в физическом разрешении; матрица заодно
           даёт горизонтальный масштаб FontWidthScale (аналога Font.ScaleX
           в FMX нет). *)
        Result.Canvas.SetMatrix(
          TMatrix.CreateScaling(FScaleX * GlyphWidthFactor, FScaleX));
        FTextLayout.BeginUpdate;
        try
          FTextLayout.Text := Ch;
          (* Эмодзи рисуем цветным emoji-шрифтом; для остальных «сложных»
             символов (CJK и т.п.) берём обычный шрифт терминала - TTextLayout
             сам подберёт фолбэк-гарнитуру с нужными глифами. *)
          if IsEmojiChar(Ch) then
          begin
            {$IFDEF MSWINDOWS}
            FTextLayout.Font.Family := 'Segoe UI Emoji';
            {$ELSE}
            FTextLayout.Font.Family := 'Apple Color Emoji';
            {$ENDIF}
          end
          else
            FTextLayout.Font.Family := FFontFamily;
          FTextLayout.Font.Size := EffectiveFontSize;
          FTextLayout.Font.StyleExt := TFontStyleExt.Create(Weight, Slant);
          FTextLayout.Color := Color;
          FTextLayout.Opacity := 1;
          FTextLayout.TopLeft := TPointF.Zero;
        finally
          FTextLayout.EndUpdate;
        end;
        FTextLayout.RenderLayout(Result.Canvas);
      finally
        Result.Canvas.EndScene;
      end;
  except
    Result.Free;
    raise;
  end;

  if FGlyphCache.Count >= GlyphCacheLimit then
    FGlyphCache.Clear;
  FGlyphCache.Add(CacheKey, Result);
end;

procedure TTerminalRenderer.DrawGlyph(Canvas: TCanvas; const Ch: string;
  CellCount: Integer; Bold, Italic: Boolean; X, Y: Single;
  Color: TAlphaColor);
var
  Glyph: TBitmap;
  DstW, DstH: Single;
begin
  Glyph := GetGlyphBitmap(Ch, CellCount, Bold, Italic, Color);
  if (Glyph = nil) or (FScaleX <= 0) then
    Exit;
  (* Логический размер назначения подобран так, чтобы при текущем масштабе
     канваса блит был 1:1 по физическим пикселям. *)
  DstW := Glyph.Width / FScaleX;
  DstH := Glyph.Height / FScaleX;
  Canvas.DrawBitmap(Glyph, TRectF.Create(0, 0, Glyph.Width, Glyph.Height),
    TRectF.Create(X, Y, X + DstW, Y + DstH), 1, True);
end;

procedure TTerminalRenderer.RenderLine(Canvas: TCanvas; LineIndex: Integer;
  const Bounds: TRectF; OffsetY: Single; DefaultBG: TAlphaColor);
var
  Line: TTerminalLine;
  Width, I, RunStart, RunLen: Integer;
  Y, RunX: Single;
  RunAttr: TCharAttributes;
  BgColor, FgColor: TAlphaColor;
  RunSelected: Boolean;
  HasSelection: Boolean;
  RunSemanticColor, CurrentSemanticColor: TAlphaColor;
  RunSemanticBold, CurrentSemanticBold: Boolean;
  BgRect: TRectF;
  CharToDraw: string;
  CharIdx: Integer;
  CharX: Single;
  CharDisplayWidth: Integer;
  RenderWidth: Single;
  UnderlineY, StrikethroughY: Single;
  DefaultAttr: TCharAttributes;
begin
  if (LineIndex < 0) or (LineIndex >= FBuffer.Height) then
    Exit;

  Line := FBuffer.GetRenderLine(LineIndex);
  Y := SnapToPixel(Bounds.Top + OffsetY + (LineIndex * FCharHeight));
  UnderlineY := SnapToPixel(Y + FLineGapOffset + FAscentOffset + 2);
  StrikethroughY := SnapToPixel(Y + FLineGapOffset + FNaturalCharHeight / 2);

  (* Очистка строки фоном *)
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := DefaultBG;
  Canvas.FillRect(TRectF.Create(Bounds.Left, Y, Bounds.Right, Y + FCharHeight),
    0, 0, [], 1);

  if Length(Line.Cells) = 0 then
    Exit;

  Width := Min(FBuffer.Width, Length(Line.Cells));
  DefaultAttr := TCharAttributes.Default(FTheme);
  HasSelection := FBuffer.HasSelection;
  BuildSemanticColors(Line, FSemanticColors, FSemanticBold);
  I := 0;

  while I < Width do
  begin
    // Пропускаем "хвосты" wide-символов (Width = 0)
    if (I < Length(Line.Cells)) and (Line.Cells[I].Width = 0) then
    begin
      Inc(I);
      Continue;
    end;

    RunStart := I;
    if I < Length(Line.Cells) then
      RunAttr := Line.Cells[I].Attributes
    else
      RunAttr := DefaultAttr;
    if HasSelection then
      RunSelected := FBuffer.IsCellSelected(I, LineIndex)
    else
      RunSelected := False;
    if I < Length(FSemanticColors) then
      RunSemanticColor := FSemanticColors[I]
    else
      RunSemanticColor := 0;
    if I < Length(FSemanticBold) then
      RunSemanticBold := FSemanticBold[I]
    else
      RunSemanticBold := False;
    Inc(I);

    // Собираем run символов с одинаковыми атрибутами
    while I < Width do
    begin
      // Пропускаем хвосты в подсчёте run
      if (I < Length(Line.Cells)) and (Line.Cells[I].Width = 0) then
      begin
        Inc(I);
        Continue;
      end;

      var CurrentAttr: TCharAttributes;
      if I < Length(Line.Cells) then
        CurrentAttr := Line.Cells[I].Attributes
      else
        CurrentAttr := DefaultAttr;

      if not SameVisualAttributes(CurrentAttr, RunAttr) then
        Break;
      if HasSelection and
        (FBuffer.IsCellSelected(I, LineIndex) <> RunSelected) then
          Break;
      if I < Length(FSemanticColors) then
        CurrentSemanticColor := FSemanticColors[I]
      else
        CurrentSemanticColor := 0;
      if CurrentSemanticColor <> RunSemanticColor then
        Break;
      if I < Length(FSemanticBold) then
        CurrentSemanticBold := FSemanticBold[I]
      else
        CurrentSemanticBold := False;
      if CurrentSemanticBold <> RunSemanticBold then
        Break;
      Inc(I);
    end;

    RunLen := I - RunStart;
    RunX := SnapToPixel(Bounds.Left + (RunStart * FCharWidth));

    // Определяем цвета
    if RunAttr.Inverse then
      BgColor := RunAttr.ForegroundColor
    else
      BgColor := RunAttr.BackgroundColor;
    if RunSelected then
      BgColor := BlendColor(FTheme.SelectionColor, BgColor);
    FgColor := GetEffectiveForeground(RunAttr);
    if (RunSemanticColor <> 0) and
      (RunAttr.ForegroundSource = tcsDefault) and not RunAttr.Inverse then
    begin
      FgColor := RunSemanticColor;
      if RunAttr.Faint then
        FgColor := MakeColor(FgColor, 0.45);
    end;

    (* Рисуем фон если отличается от default *)
    if (BgColor <> DefaultBG) or RunSelected then
    begin
      Canvas.Fill.Kind := TBrushKind.Solid;
      Canvas.Fill.Color := BgColor;
      BgRect := TRectF.Create(RunX, Y, RunX + (RunLen * FCharWidth), Y + FCharHeight);
      BgRect.Inflate(0.5, 0.0);
      Canvas.FillRect(BgRect, 0, 0, [], 1);
    end;

    (* Рисуем символы *)
    if not RunAttr.Hidden then
    begin
      CharIdx := RunStart;
      CharX := RunX;

      while CharIdx < I do
      begin
        if CharIdx >= Length(Line.Cells) then
          Break;

        if Line.Cells[CharIdx].Width = 0 then
        begin
          Inc(CharIdx);
          Continue;
        end;

        CharToDraw := Line.Cells[CharIdx].Char;
        CharDisplayWidth := Line.Cells[CharIdx].Width;
        RenderWidth := CharDisplayWidth * FCharWidth;

        if IsBoxDrawingChar(CharToDraw) then
          RenderBoxDrawingChar(Canvas, CharToDraw, CharX, Y, FCharWidth, FCharHeight, FgColor)
        else if (CharToDraw <> '') and (CharToDraw <> ' ') then
          DrawGlyph(Canvas, CharToDraw, CharDisplayWidth,
            RunAttr.Bold or RunSemanticBold, RunAttr.Italic, CharX,
            Y + FLineGapOffset, FgColor);

        CharX := SnapToPixel(CharX + RenderWidth);
        Inc(CharIdx);
      end;

      if RunAttr.Underline or RunAttr.Strikethrough then
      begin
        Canvas.Stroke.Kind := TBrushKind.Solid;
        Canvas.Stroke.Thickness := 1;
        Canvas.Stroke.Dash := TStrokeDash.Solid;
        Canvas.Stroke.Color := FgColor;
        if RunAttr.Underline then
          Canvas.DrawLine(TPointF.Create(RunX, UnderlineY),
            TPointF.Create(SnapToPixel(RunX + RunLen * FCharWidth),
            UnderlineY), 1);
        if RunAttr.Strikethrough then
          Canvas.DrawLine(TPointF.Create(RunX, StrikethroughY),
            TPointF.Create(SnapToPixel(RunX + RunLen * FCharWidth),
            StrikethroughY), 1);
      end;
    end;

  end;
end;

procedure TTerminalRenderer.RenderCursor(Canvas: TCanvas; const Bounds: TRectF);
var
  CursorRect: TRectF;
  Line: TTerminalLine;
  Cell: TTerminalChar;
  CursorCol, CellWidth: Integer;
  X, Y, RenderWidth: Single;
  CursorBackground, CursorForeground: TAlphaColor;
begin
  if (FBuffer.ViewportOffset > 0) then
    Exit;
  if not FShowCursor or not FBuffer.Cursor.Visible or
    (FBuffer.Cursor.Blink and not FCursorBlinkState) then
    Exit;
  CursorCol := EnsureRange(FBuffer.Cursor.X, 0, FBuffer.Width - 1);
  Line := FBuffer.GetRenderLine(FBuffer.Cursor.Y);
  if (CursorCol >= Length(Line.Cells)) then
    Exit;
  if (Line.Cells[CursorCol].Width = 0) and (CursorCol > 0) then
    Dec(CursorCol);
  Cell := Line.Cells[CursorCol];
  CellWidth := Max(1, Cell.Width);

  X := Bounds.Left + CursorCol * FCharWidth;
  Y := Bounds.Top + FBuffer.Cursor.Y * FCharHeight;
  RenderWidth := CellWidth * FCharWidth;
  CursorRect := TRectF.Create(X, Y, X + RenderWidth, Y + FCharHeight);
  CursorRect := TRectF.Create(SnapToPixel(CursorRect.Left),
    SnapToPixel(CursorRect.Top), SnapToPixel(CursorRect.Right),
    SnapToPixel(CursorRect.Bottom));

  CursorBackground := TAlphaColor($FF000000) or
    (FTheme.CursorColor and TAlphaColor($00FFFFFF));
  if Cell.Attributes.Inverse then
    CursorForeground := Cell.Attributes.ForegroundColor
  else
    CursorForeground := Cell.Attributes.BackgroundColor;

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := CursorBackground;
  case FBuffer.Cursor.Shape of
    tcsUnderline:
      CursorRect.Top := Max(CursorRect.Top,
        CursorRect.Bottom - Max(2.0, FCharHeight * 0.12));
    tcsBar:
      CursorRect.Right := Min(CursorRect.Right,
        CursorRect.Left + Max(2.0, FCharWidth * 0.18));
  end;
  Canvas.FillRect(CursorRect, 0, 0, [], 1);

  if FBuffer.Cursor.Shape <> tcsBlock then
    Exit;

  if Cell.Attributes.Hidden or (Cell.Char = '') or (Cell.Char = ' ') then
    Exit;

  if IsBoxDrawingChar(Cell.Char) then
    RenderBoxDrawingChar(Canvas, Cell.Char, CursorRect.Left, CursorRect.Top,
      FCharWidth, FCharHeight, CursorForeground)
  else
    DrawGlyph(Canvas, Cell.Char, CellWidth, Cell.Attributes.Bold,
      Cell.Attributes.Italic, CursorRect.Left,
      CursorRect.Top + FLineGapOffset, CursorForeground);
end;

procedure TTerminalRenderer.RenderDebugInfo(Canvas: TCanvas; const Bounds: TRectF);
begin
  // Debug info placeholder
end;

procedure TTerminalRenderer.Render(Canvas: TCanvas; const Bounds: TRectF);
var
  I: Integer;
  LDefaultBG: TAlphaColor;
  BackCanvas: TCanvas;
  Cur, Prev: TBitmap;
  W, H: Integer;
  ScrollDelta: Integer;
  ScrollPx: Single;
  ShiftFrame: Boolean;
  TailY: Single;
begin
  UpdateResources;
  LDefaultBG := FTheme.DefaultBG;
  W := Ceil(Bounds.Width);
  H := Ceil(Bounds.Height);
  CheckBackBuffer(W, H);
  if FBackBuffers[FBackIndex] = nil then
    Exit;
  ScrollDelta := FBuffer.GetAndResetVisualScrollDelta;

  ShiftFrame := (not FBuffer.HasSelection) and (FBuffer.ViewportOffset = 0) and
    (ScrollDelta > 0) and (ScrollDelta * FCharHeight < H);

  Prev := FBackBuffers[FBackIndex];
  if ShiftFrame then
    FBackIndex := 1 - FBackIndex;
  Cur := FBackBuffers[FBackIndex];

  BackCanvas := Cur.Canvas;
  if BackCanvas.BeginScene then
    try
      BackCanvas.SetMatrix(TMatrix.Identity);

      if ShiftFrame then
      begin
        (* Сдвиг предыдущего кадра вверх в физических пикселях: копия из
           соседнего битмапа (самокопирование канваса в FMX небезопасно). *)
        ScrollPx := ScrollDelta * FCharHeight * FScaleX;
        BackCanvas.Clear(LDefaultBG);
        BackCanvas.DrawBitmap(Prev,
          TRectF.Create(0, 0, Prev.Width, Prev.Height),
          TRectF.Create(0, -ScrollPx, Prev.Width, Prev.Height - ScrollPx),
          1, True);
      end
      else if (FBuffer.ViewportOffset = 0) and (ScrollDelta > 0) then
        BackCanvas.Clear(LDefaultBG);

      // Рисуем в логических координатах поверх физического буфера
      BackCanvas.SetMatrix(TMatrix.CreateScaling(FScaleX, FScaleX));

      for I := 0 to FBuffer.Height - 1 do
        if FBuffer.IsLineDirty(I) then
        begin
          RenderLine(BackCanvas, I,
            TRectF.Create(0, 0, Bounds.Width, Bounds.Height), 0, LDefaultBG);
          FBuffer.CleanLine(I);
        end;

      TailY := FBuffer.Height * FCharHeight;
      if TailY < Bounds.Height then
      begin
        BackCanvas.Fill.Kind := TBrushKind.Solid;
        BackCanvas.Fill.Color := LDefaultBG;
        BackCanvas.FillRect(TRectF.Create(0, TailY, Bounds.Width,
          Bounds.Height), 0, 0, [], 1);
      end;
    finally
      BackCanvas.EndScene;
    end;

  // Блиттинг: физический буфер → логический прямоугольник (1:1 на HiDPI)
  Canvas.DrawBitmap(Cur, TRectF.Create(0, 0, Cur.Width, Cur.Height),
    Bounds, 1, True);
  RenderCursor(Canvas, Bounds);
end;

procedure TTerminalRenderer.ToggleCursorBlink;
begin
  FCursorBlinkState := not FCursorBlinkState;
end;

end.
