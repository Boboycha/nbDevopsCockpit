unit Terminal.Renderer;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  System.Character,
  System.Generics.Collections,
  FMX.Types, FMX.Graphics, FMX.TextLayout,
  FMX.Skia, System.Skia,
  Terminal.Types, Terminal.Buffer, System.UIConsts,
  Terminal.Theme;

type
  TTerminalRenderer = class
  private
    FBuffer: TTerminalBuffer;
    FCharWidth: Single;
    FCharHeight: Single;
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
    FSemanticText: string;

    FCachedPaint: ISkPaint;
    FCachedFontNormal: ISkFont;
    FCachedFontBold: ISkFont;
    FCachedFontItalic: ISkFont;
    FCachedFontBoldItalic: ISkFont;

    // Для гибридного рендеринга
    FTextLayout: TTextLayout;
    FEmojiBitmap: TBitmap;
    FComplexGlyphCache: TDictionary<string, ISkImage>;

    FResourcesValid: Boolean;
    FBackBuffer: ISkSurface;
    FBackBufferWidth: Integer;
    FBackBufferHeight: Integer;

    function GetEffectiveForeground(const Attr: TCharAttributes): TAlphaColor;
    function SameVisualAttributes(const Left,
      Right: TCharAttributes): Boolean; inline;
    procedure UpdateResources;
    function GetFontForStyle(Bold, Italic: Boolean): ISkFont;
    procedure CheckBackBuffer(Width, Height: Integer);
    procedure SetScale(const Value: Single);
    procedure SetContentScale(const Value: Single);
    procedure SetUIScale(const Value: Single);
    procedure SetFontWidthScale(const Value: Single);
    procedure SetFontHeightScale(const Value: Single);
    function SnapToPixel(const Value: Single): Single;
    function EffectiveFontSize: Single;
    function BlendColor(const Overlay, Base: TAlphaColor): TAlphaColor;
    procedure BuildSemanticColors(const Line: TTerminalLine;
      var Colors: TArray<TAlphaColor>);
    procedure SetSemanticHighlighting(const Value: Boolean);

    procedure RenderBoxDrawingChar(Canvas: ISkCanvas; Ch: string;
      X, Y, W, H: Single; Color: TAlphaColor);
    procedure RenderComplexChar(Canvas: ISkCanvas; const Ch: string;
      X, Y, W: Single; Color: TAlphaColor);

  public
    constructor Create(ABuffer: TTerminalBuffer; ATheme: TTerminalTheme);
    destructor Destroy; override;

    procedure Render(Canvas: ISkCanvas; const Bounds: TRectF);
    procedure RenderLine(Canvas: ISkCanvas; LineIndex: Integer;
      const Bounds: TRectF; OffsetY: Single; DefaultBG: TAlphaColor);
    procedure RenderCursor(Canvas: ISkCanvas; const Bounds: TRectF);

    procedure MeasureChar;
    procedure ToggleCursorBlink;
    procedure RenderDebugInfo(Canvas: ISkCanvas; const Bounds: TRectF);
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
  FCachedPaint := TSkPaint.Create;
  FCachedPaint.AntiAlias := True;
  FBackBuffer := nil;
  FBackBufferWidth := 0;
  FBackBufferHeight := 0;

  FTextLayout := TTextLayoutManager.DefaultTextLayout.Create;
  FEmojiBitmap := TBitmap.Create;
  FComplexGlyphCache := TDictionary<string, ISkImage>.Create;

  MeasureChar;
end;

destructor TTerminalRenderer.Destroy;
begin
  FComplexGlyphCache.Free;
  FTextLayout.Free;
  FEmojiBitmap.Free;
  inherited;
end;

procedure TTerminalRenderer.SetTheme(ATheme: TTerminalTheme);
begin
  FTheme := ATheme;
  FComplexGlyphCache.Clear;
  FBuffer.SetAllDirty;
end;

procedure TTerminalRenderer.InvalidateResources;
begin
  FResourcesValid := False;
  FComplexGlyphCache.Clear;
end;

procedure TTerminalRenderer.SetScale(const Value: Single);
begin
  if not SameValue(FScaleX, Value, 0.001) then
  begin
    FScaleX := Value;
    FScaleY := Value;
    MeasureChar;
    FBackBufferWidth  := 0;
    FBackBufferHeight := 0;
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
  FBackBufferWidth := 0;
  FBackBufferHeight := 0;
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
  FBackBufferWidth := 0;
  FBackBufferHeight := 0;
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
  var Colors: TArray<TAlphaColor>);
var
  I, StartPos, EndPos, HostStart, HostEnd: Integer;

  function IsHostChar(const C: Char): Boolean;
  begin
    Result := C.IsLetterOrDigit or CharInSet(C, ['.', '-']);
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

  procedure MarkRange(AStart, AEnd: Integer; AColor: TAlphaColor);
  var
    K: Integer;
  begin
    for K := Max(0, AStart) to Min(AEnd, High(Colors)) do
      Colors[K] := AColor;
  end;

begin
  SetLength(Colors, 0);
  if (not FSemanticHighlighting) or FBuffer.IsAlternateBuffer then
    Exit;
  SetLength(Colors, Length(Line.Cells));
  if Length(Colors) > 0 then
    FillChar(Colors[0], Length(Colors) * SizeOf(TAlphaColor), 0);

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
    FBackBufferWidth := 0;
    FBackBufferHeight := 0;
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
    FBackBufferWidth := 0;
    FBackBufferHeight := 0;
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
var
  Typeface: ISkTypeface;
  RenderFontSize: Single;
  
  procedure ConfigureFont(Font: ISkFont);
  begin
    Font.Edging   := TSkFontEdging.AntiAlias;
    Font.Hinting  := TSkFontHinting.Full;
    Font.Subpixel := True;
    Font.ScaleX := FFontWidthScale / FFontHeightScale;
  end;

begin
  if FResourcesValid then
    Exit;
  RenderFontSize := EffectiveFontSize;

  Typeface := TSkTypeface.MakeFromName(FFontFamily, TSkFontStyle.Create(
    Integer(TSkFontWeight.Medium), Integer(TSkFontWidth.Normal),
    TSkFontSlant.Upright));

  FCachedFontNormal := TSkFont.Create(Typeface, RenderFontSize);
  ConfigureFont(FCachedFontNormal);
  Typeface := TSkTypeface.MakeFromName(FFontFamily, TSkFontStyle.Bold);
  FCachedFontBold := TSkFont.Create(Typeface, RenderFontSize);
  ConfigureFont(FCachedFontBold);
  Typeface := TSkTypeface.MakeFromName(FFontFamily, TSkFontStyle.Italic);
  FCachedFontItalic := TSkFont.Create(Typeface, RenderFontSize);
  ConfigureFont(FCachedFontItalic);
  Typeface := TSkTypeface.MakeFromName(FFontFamily, TSkFontStyle.BoldItalic);
  FCachedFontBoldItalic := TSkFont.Create(Typeface, RenderFontSize);
  ConfigureFont(FCachedFontBoldItalic);
  FTextLayout.Font.Size := RenderFontSize;
  FTextLayout.WordWrap := False;
  FTextLayout.HorizontalAlign := TTextAlign.Leading;
  FTextLayout.VerticalAlign := TTextAlign.Leading;
  FResourcesValid := True;
end;

function TTerminalRenderer.GetFontForStyle(Bold, Italic: Boolean): ISkFont;
var
  UseBold, UseItalic: Boolean;
begin
  UseBold := Bold or FFontBold;
  UseItalic := Italic or FFontItalic;

  if UseBold and UseItalic then
    Result := FCachedFontBoldItalic
  else if UseBold then
    Result := FCachedFontBold
  else if UseItalic then
    Result := FCachedFontItalic
  else
    Result := FCachedFontNormal;
end;

procedure TTerminalRenderer.MeasureChar;
var
  Metrics: TSkFontMetrics;
  RealWidth, RealHeight: Single;
begin
  InvalidateResources;
  UpdateResources;
  FCachedFontNormal.GetMetrics(Metrics);

  RealWidth := FCachedFontNormal.MeasureText('W');
  if RealWidth < 1 then
    RealWidth := 8;
  FCharWidth := SnapToPixel(RealWidth);   (* целые физические пиксели - нужно для чёткости и псевдографики *)
  if FCharWidth < 1 then
    FCharWidth := 8;

  RealHeight := Abs(Metrics.Ascent) + Metrics.Descent;
  FCharHeight := SnapToPixel(RealHeight); (* целые физические пиксели *)
  if FCharHeight < 1 then
    FCharHeight := 12;

  FAscentOffset := SnapToPixel(Abs(Metrics.Ascent));
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
  PhysW, PhysH: Integer;
begin
  PhysW := Max(1, Round(Width  * FScaleX));
  PhysH := Max(1, Round(Height * FScaleX));
  if (FBackBuffer = nil) or (FBackBufferWidth <> PhysW) or
    (FBackBufferHeight <> PhysH) then
  begin
    FBackBufferWidth  := PhysW;
    FBackBufferHeight := PhysH;
    FBackBuffer := TSkSurface.MakeRaster(FBackBufferWidth, FBackBufferHeight);
    FBuffer.GetAndResetVisualScrollDelta;
    FBuffer.SetAllDirty;
    if FBackBuffer <> nil then
      FBackBuffer.Canvas.Clear(FTheme.DefaultBG);
  end;
end;

procedure TTerminalRenderer.RenderBoxDrawingChar(Canvas: ISkCanvas; Ch: string;
  X, Y, W, H: Single; Color: TAlphaColor);
var
  Cx, Cy: Single;
  Code: Integer;
  DrawUp, DrawDown, DrawLeft, DrawRight: Boolean;
begin
  FCachedPaint.Style := TSkPaintStyle.Stroke;
  FCachedPaint.Color := Color;
  FCachedPaint.StrokeWidth := 1;
//  Cx := Floor(X + (W / 2)) + 0.5;
//  Cy := Floor(Y + (H / 2)) + 0.5;
  Cx := Floor(X + (W / 2)) ;
  Cy := Floor(Y + (H / 2)) ;
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
    Canvas.DrawLine(Cx, Cy, Cx, Y, FCachedPaint);
  if DrawDown then
    Canvas.DrawLine(Cx, Cy, Cx, Y + H, FCachedPaint);
  if DrawLeft then
    Canvas.DrawLine(Cx, Cy, X, Cy, FCachedPaint);
  if DrawRight then
    Canvas.DrawLine(Cx, Cy, X + W, Cy, FCachedPaint);
end;

procedure TTerminalRenderer.RenderComplexChar(Canvas: ISkCanvas;
  const Ch: string; X, Y, W: Single; Color: TAlphaColor);
var
  BmpW, BmpH: Integer;
  Image: ISkImage;
  CacheKey: string;
begin
  BmpW := Max(1, Round(W));
  BmpH := Max(1, Round(FCharHeight * 1.5));
  CacheKey := Ch + #0 + IntToHex(Color, 8) + #0 + IntToStr(BmpW);
  if FComplexGlyphCache.TryGetValue(CacheKey, Image) then
  begin
    Canvas.DrawImage(Image, X, Y);
    Exit;
  end;

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

  FTextLayout.Color := Color;

  if (FEmojiBitmap.Width < BmpW) or (FEmojiBitmap.Height < BmpH) then
    FEmojiBitmap.SetSize(BmpW, BmpH);
  FEmojiBitmap.Clear(0);

  if FEmojiBitmap.Canvas.BeginScene then
    try
      FTextLayout.RenderLayout(FEmojiBitmap.Canvas);
    finally
      FEmojiBitmap.Canvas.EndScene;
    end;

  Image := FEmojiBitmap.ToSkImage;
  if Image <> nil then
  begin
    if FComplexGlyphCache.Count >= 256 then
      FComplexGlyphCache.Clear;
    FComplexGlyphCache.Add(CacheKey, Image);
    Canvas.DrawImage(Image, X, Y);
  end;
end;

procedure TTerminalRenderer.RenderLine(Canvas: ISkCanvas; LineIndex: Integer;
  const Bounds: TRectF; OffsetY: Single; DefaultBG: TAlphaColor);
var
  Line: TTerminalLine;
  Width, I, RunStart, RunLen: Integer;
  Y, RunX: Single;
  RunAttr: TCharAttributes;
  CurrentFont: ISkFont;
  BgColor, FgColor: TAlphaColor;
  RunSelected: Boolean;
  HasSelection: Boolean;
  RunSemanticColor, CurrentSemanticColor: TAlphaColor;
  BgRect: TRectF;
  CharToDraw: string;
  CharIdx: Integer;
  CharX: Single;
  CharDisplayWidth: Integer;
  RenderWidth: Single;
  BaselineY, UnderlineY, StrikethroughY: Single;
  DefaultAttr: TCharAttributes;
begin
  if (LineIndex < 0) or (LineIndex >= FBuffer.Height) then
    Exit;
    
  Line := FBuffer.GetRenderLine(LineIndex);
  Y := SnapToPixel(Bounds.Top + OffsetY + (LineIndex * FCharHeight));
  BaselineY := SnapToPixel(Y + FAscentOffset);
  UnderlineY := SnapToPixel(Y + FAscentOffset + 2);
  StrikethroughY := SnapToPixel(Y + FCharHeight / 2);
  
  // Очистка строки фоном
  FCachedPaint.Style := TSkPaintStyle.Fill;
  FCachedPaint.Color := DefaultBG;
  Canvas.DrawRect(TRectF.Create(Bounds.Left, Y, Bounds.Right, Y + FCharHeight), FCachedPaint);
  
  if Length(Line.Cells) = 0 then
    Exit;
    
  Width := Min(FBuffer.Width, Length(Line.Cells));
  DefaultAttr := TCharAttributes.Default(FTheme);
  HasSelection := FBuffer.HasSelection;
  BuildSemanticColors(Line, FSemanticColors);
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
      Inc(I);
    end;
    
    RunLen := I - RunStart;
    RunX := SnapToPixel(Bounds.Left + (RunStart * FCharWidth));
    
    // Определяем цвета
    if RunSelected then
    begin
      if RunAttr.Inverse then
        BgColor := RunAttr.ForegroundColor
      else
        BgColor := RunAttr.BackgroundColor;
      BgColor := BlendColor(FTheme.SelectionColor, BgColor);
      FgColor := GetEffectiveForeground(RunAttr);
    end
    else
    begin
      if RunAttr.Inverse then
        BgColor := RunAttr.ForegroundColor
      else
        BgColor := RunAttr.BackgroundColor;
      FgColor := GetEffectiveForeground(RunAttr);
    end;
    if (RunSemanticColor <> 0) and
      (RunAttr.ForegroundSource = tcsDefault) and not RunAttr.Inverse then
    begin
      FgColor := RunSemanticColor;
      if RunAttr.Faint then
        FgColor := MakeColor(FgColor, 0.45);
    end;
    
    // Рисуем фон если отличается от default
(* Рисуем фон если отличается от default *)
    if (BgColor <> DefaultBG) or RunSelected then
    begin
      FCachedPaint.Style := TSkPaintStyle.Fill;
      FCachedPaint.Color := BgColor;
      BgRect := TRectF.Create(RunX, Y, RunX + (RunLen * FCharWidth), Y + FCharHeight);
      BgRect.Inflate(0.5, 0.0);
      Canvas.DrawRect(BgRect, FCachedPaint);
    end;

    (* Рисуем символы *)
    if not RunAttr.Hidden then
    begin
      CurrentFont := GetFontForStyle(RunAttr.Bold, RunAttr.Italic);
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
        else if CharToDraw <> '' then
        begin
          if (Length(CharToDraw) > 1) or (Ord(CharToDraw[1]) > $2E80) then
            RenderComplexChar(Canvas, CharToDraw, CharX, Y, RenderWidth, FgColor)
          else
          begin
//            FCachedPaint.AntiAlias := True;
            FCachedPaint.Style := TSkPaintStyle.Fill;
            FCachedPaint.Color := FgColor;
            Canvas.DrawSimpleText(CharToDraw, CharX, BaselineY,
              CurrentFont, FCachedPaint);
          end;
        end;

        CharX := SnapToPixel(CharX + RenderWidth);
        Inc(CharIdx);
      end;

      if RunAttr.Underline or RunAttr.Strikethrough then
      begin
        FCachedPaint.Style := TSkPaintStyle.Stroke;
        FCachedPaint.StrokeWidth := 1;
        FCachedPaint.Color := FgColor;
        if RunAttr.Underline then
          Canvas.DrawLine(RunX, UnderlineY,
            SnapToPixel(RunX + RunLen * FCharWidth), UnderlineY,
            FCachedPaint);
        if RunAttr.Strikethrough then
          Canvas.DrawLine(RunX, StrikethroughY,
            SnapToPixel(RunX + RunLen * FCharWidth), StrikethroughY,
            FCachedPaint);
      end;
    end;

    end;
end;

procedure TTerminalRenderer.RenderCursor(Canvas: ISkCanvas; const Bounds: TRectF);
var
  CursorRect: TRectF;
  Line: TTerminalLine;
  Cell: TTerminalChar;
  CursorCol, CellWidth: Integer;
  X, Y, BaselineY, RenderWidth: Single;
  CursorBackground, CursorForeground: TAlphaColor;
  CurrentFont: ISkFont;
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
  BaselineY := SnapToPixel(Y + FAscentOffset);
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

  FCachedPaint.Style := TSkPaintStyle.Fill;
  FCachedPaint.Color := CursorBackground;
  case FBuffer.Cursor.Shape of
    tcsUnderline:
      CursorRect.Top := Max(CursorRect.Top,
        CursorRect.Bottom - Max(2.0, FCharHeight * 0.12));
    tcsBar:
      CursorRect.Right := Min(CursorRect.Right,
        CursorRect.Left + Max(2.0, FCharWidth * 0.18));
  end;
  Canvas.DrawRect(CursorRect, FCachedPaint);

  if FBuffer.Cursor.Shape <> tcsBlock then
    Exit;

  if Cell.Attributes.Hidden or (Cell.Char = '') then
    Exit;

  if IsBoxDrawingChar(Cell.Char) then
    RenderBoxDrawingChar(Canvas, Cell.Char, CursorRect.Left, CursorRect.Top,
      FCharWidth, FCharHeight, CursorForeground)
  else if (Length(Cell.Char) > 1) or (Ord(Cell.Char[1]) > $2E80) then
    RenderComplexChar(Canvas, Cell.Char, CursorRect.Left, CursorRect.Top,
      RenderWidth, CursorForeground)
  else
  begin
    CurrentFont := GetFontForStyle(Cell.Attributes.Bold,
      Cell.Attributes.Italic);
    FCachedPaint.Style := TSkPaintStyle.Fill;
    FCachedPaint.Color := CursorForeground;
    Canvas.DrawSimpleText(Cell.Char, CursorRect.Left, BaselineY,
      CurrentFont, FCachedPaint);
  end;
end;

procedure TTerminalRenderer.RenderDebugInfo(Canvas: ISkCanvas; const Bounds: TRectF);
begin
  // Debug info placeholder
end;

procedure TTerminalRenderer.Render(Canvas: ISkCanvas; const Bounds: TRectF);
var
  I: Integer;
  LDefaultBG: TAlphaColor;
  BackCanvas: ISkCanvas;
  W, H: Integer;
  ImageSnapshot: ISkImage;
  ScrollDelta: Integer;
  ScrollPx: Single;
begin
//  FCachedPaint.AntiAlias := True;   (* ← добавить эту строку в начало *)

  UpdateResources;
  LDefaultBG := FTheme.DefaultBG;
  W := Ceil(Bounds.Width);
  H := Ceil(Bounds.Height);
  CheckBackBuffer(W, H);
  if FBackBuffer = nil then
    Exit;
  BackCanvas := FBackBuffer.Canvas;
  ScrollDelta := FBuffer.GetAndResetVisualScrollDelta;
  
  if (not FBuffer.HasSelection) and (FBuffer.ViewportOffset = 0) and
    (ScrollDelta > 0) and (ScrollDelta * FCharHeight < H) then
  begin
    ImageSnapshot := FBackBuffer.MakeImageSnapshot;
    if ImageSnapshot <> nil then
    begin
      // Сдвиг предыдущего кадра вверх в физических пикселях
      ScrollPx := ScrollDelta * FCharHeight * FScaleX;
      BackCanvas.DrawImage(ImageSnapshot, 0, -ScrollPx);
    end;
  end
  else if (FBuffer.ViewportOffset = 0) and (ScrollDelta > 0) then
    BackCanvas.Clear(LDefaultBG);

  // Рисуем в логических координатах поверх физического буфера
  BackCanvas.Save;
  BackCanvas.Scale(FScaleX, FScaleX);

  for I := 0 to FBuffer.Height - 1 do
    if FBuffer.IsLineDirty(I) then
    begin
      RenderLine(BackCanvas, I, TRectF.Create(0, 0, Bounds.Width, Bounds.Height), 0, LDefaultBG);
      FBuffer.CleanLine(I);
    end;

    var TailY: Single := FBuffer.Height * FCharHeight;
    if TailY < Bounds.Height then
    begin
      FCachedPaint.Style := TSkPaintStyle.Fill;
      FCachedPaint.Color := LDefaultBG;
      BackCanvas.DrawRect(TRectF.Create(0, TailY, Bounds.Width, Bounds.Height), FCachedPaint);
    end;

  BackCanvas.Restore;

  // Блиттинг: физический буфер → логический прямоугольник (1:1 на HiDPI)
  ImageSnapshot := FBackBuffer.MakeImageSnapshot;
  if ImageSnapshot <> nil then
    Canvas.DrawImageRect(ImageSnapshot,
      TRectF.Create(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom),
      TSkSamplingOptions.Create(TSkFilterMode.Nearest, TSkMipmapMode.None));
  RenderCursor(Canvas, Bounds);
end;

procedure TTerminalRenderer.ToggleCursorBlink;
begin
  FCursorBlinkState := not FCursorBlinkState;
end;

end.
