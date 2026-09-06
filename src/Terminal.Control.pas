unit Terminal.Control;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Math, System.Generics.Collections, System.Diagnostics,
  System.Character, System.IOUtils, System.TypInfo,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Dialogs,
  FMX.Consts, FMX.Platform,
  Terminal.Types, Terminal.Buffer, Terminal.AnsiParser, Terminal.Renderer,
  Terminal.Theme, Terminal.Input, Terminal.Clipboard, Terminal.SSHBridge,
  ModernSSHClient, GoghThemeLoader, Terminal.LocalSession;

type
  TTerminalDataEvent = procedure(const S: string) of object;
  TTerminalHostOutputEvent = procedure(var S: string) of object;

  TSyntaxRule = record
    Keyword: string;
    AnsiColor: string;
    IgnoreCase: Boolean;
  end;

  TnbTerminalControl = class(TControl)
  private
    FBuffer: TTerminalBuffer;
    FParser: TAnsiParser;
    FRenderer: TTerminalRenderer;
    FCursorTimer: TTimer;
    FOnData: TTerminalDataEvent;
    FOnUserInput: TTerminalDataEvent;
    FOnHostOutput: TTerminalHostOutputEvent;
    FTheme: TTerminalTheme;

    FRenderTimer: TTimer;
    FNeedRedraw: Boolean;
    FPendingHostCols: Integer;
    FPendingHostRows: Integer;

    FSyntaxRules: TList<TSyntaxRule>;
    FEnableSyntaxHighlighting: Boolean;

    // Для выделения
    FIsSelecting: Boolean;
    FSelectionStartAbs: TPoint;
    FSelectionDragOrigin: TPointF;
    FSelectionDragStarted: Boolean;
    FSelectionAutoScrollTimer: TTimer;
    FSelectionMousePos: TPointF;
    FSelectionAutoScrollDirection: Integer;
    FClearSelectionOnNextAction: Boolean;
    FSelectionProtectedUntilTick: Int64;
    FSuppressNextRightMouseUp: Boolean;
    FLastClickTick: Int64;
    FLastClickPoint: TPointF;
    FAutoCopySelection: Boolean;
    FPasteOnRightClick: Boolean;
    FScrollBarDragging: Boolean;
    FScrollBarDragOffset: Single;
    FActiveMouseButton: Integer;
    FSSHBridge: TTerminalSSHBridge;
    FLocalSession: TnbLocalTerminalSession;
    FShowSSHErrors: Boolean;
    FTraceEnabled: Boolean;
    FTraceFileName: string;
    FLastHostCols: Integer;
    FLastHostRows: Integer;
   FDeferHostResize: Boolean;

    function GetSSHClient: TnbSSHClient;
    procedure SetSSHClient(const Value: TnbSSHClient);
    procedure HandleSSHConnected(Sender: TObject);
    procedure HandleSSHError(Sender: TObject; const ErrorMessage: string);
    procedure HandleSSHReadData(Sender: TObject; const Data: string);
    procedure HandleLocalError(Sender: TObject; const Data: string);
    procedure HandleOwnResize(Sender: TObject);
    procedure HandleBufferResponse(const S: string);
    procedure TraceTerminalData(const Direction, Data: string);
    procedure TraceKeyInput(Key: Word; KeyChar: WideChar; Shift: TShiftState;
      const Data: string);
    procedure TraceAnsiCommands(const Commands: TArray<TAnsiCommand>);

    procedure CursorTimerProc(Sender: TObject);
    procedure RenderTimerProc(Sender: TObject);
    procedure SelectionAutoScrollTimerProc(Sender: TObject);
    procedure UpdateSelectionAt(const X, Y: Single);

    function GetCols: Integer;
    function GetRows: Integer;
    function GetFontSize: Single;
    procedure SetFontSize(const Value: Single);
    function GetFontWidthScale: Single;
    procedure SetFontWidthScale(const Value: Single);
    function GetFontHeightScale: Single;
    procedure SetFontHeightScale(const Value: Single);
    function GetFontFamily: string;
    procedure SetFontFamily(const Value: string);
    function GetFontBold: Boolean;
    procedure SetFontBold(Value: Boolean);
    function GetFontItalic: Boolean;
    procedure SetFontItalic(Value: Boolean);
   procedure SetDeferHostResize(const Value: Boolean);
    function GetTheme: TTerminalTheme;
    procedure SetTheme(const Value: TTerminalTheme);
    function GetSemanticHighlighting: Boolean;
    procedure SetSemanticHighlighting(const Value: Boolean);

    procedure UpdateTerminalSize(NotifyHost: Boolean);
    procedure ApplyTerminalSize(NewCols, NewRows: Integer;
      NotifyHost: Boolean);
    procedure ScheduleHostResize(NewCols, NewRows: Integer);
    procedure FlushHostResize;
    procedure SendMouseReport(AButton, ACol, ARow: Integer; AShift: TShiftState;
      AState: TMouseButtonState);
    function MouseReportingEnabled: Boolean;
    function TryMouseCell(const X, Y: Single; OneBased: Boolean;
      out Col, Row: Integer): Boolean;
    class function MouseButtonCode(Button: TMouseButton;
      out Code: Integer): Boolean; static;
    function ScrollBarVisible: Boolean;
    procedure GetScrollBarRects(out TrackRect, ThumbRect: TRectF);
    procedure SetViewportFromThumb(const ThumbTop: Single);
    procedure DrawScrollBar(const ACanvas: TCanvas);

    function ApplyHighlighting(const Input: string): string;
    function TrySelectWordAt(Col, Row: Integer): Boolean;
    function IsSelectionProtected: Boolean;
    procedure ProtectSelection;
    procedure ClearSelectionOnTerminalAction;
    procedure ResetViewportToBottom;

    // Буфер обмена
    procedure CopyToClipboard;
    procedure PasteFromClipboard;

protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure DoExit; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
    procedure DialogKey(var Key: Word; Shift: TShiftState); override;

    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure WriteText(const Text: string);
    procedure Clear;
    procedure StartLocalSession(const Executable: string = '';
      const Arguments: TArray<string> = nil; const Directory: string = '');
    procedure StopLocalSession;

    (* Внешняя подача клавиши в терминал. Нужна, когда форма перехватывает
       клавишу (например Tab — FMX уводит его на навигацию по фокусу). *)
    procedure InjectKey(Key: Word; KeyChar: WideChar; Shift: TShiftState);

    procedure AddSyntaxRule(const Keyword: string; const AnsiColor: string; IgnoreCase: Boolean = True);
    procedure ClearSyntaxRules;

    procedure LoadThemeFromFile(const FileName: string); overload;
    function LoadThemeFromFile(const FileName: string;
    out ErrorMsg: string): Boolean; overload;
    procedure LoadDefaultTheme;
    class function EnumThemes(const Folder: string): TGoghThemeInfoArray; static;


    property Buffer: TTerminalBuffer read FBuffer;
    property Parser: TAnsiParser read FParser;
    property Renderer: TTerminalRenderer read FRenderer;
    property Cols: Integer read GetCols;
    property Rows: Integer read GetRows;
    property DeferHostResize: Boolean read FDeferHostResize
      write SetDeferHostResize;
    property LocalSession: TnbLocalTerminalSession read FLocalSession;

  published
    (* Свойства TControl, публикуемые заново: базовый класс сменился
       на TControl, а TControl их не публикует - без этого
       ломается загрузка из .fmx. *)
    property Align;
    property Anchors;
    property CanFocus default True;
    property ClipChildren;
    property ClipParent;
    property Cursor;
    property DragMode;
    property Enabled;
    property Height;
    property HitTest;
    property Locked;
    property Margins;
    property Opacity;
    property Padding;
    property PopupMenu;
    property Position;
    property RotationAngle;
    property RotationCenter;
    property Scale;
    property Size;
    property TabOrder;
    property TabStop default False;
    property Visible;
    property Width;
    property OnClick;
    property OnDblClick;
    property OnKeyDown;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnPainting;
    property OnPaint;
    property OnResize;
    property OnResized;
    property FontSize: Single read GetFontSize write SetFontSize;
    property FontWidthScale: Single read GetFontWidthScale
      write SetFontWidthScale;
    property FontHeightScale: Single read GetFontHeightScale
      write SetFontHeightScale;
    property FontFamily: string read GetFontFamily write SetFontFamily;
    property FontBold: Boolean read GetFontBold write SetFontBold;
    property FontItalic: Boolean read GetFontItalic write SetFontItalic;
   property Theme: TTerminalTheme read GetTheme write SetTheme;
    property SSHClient: TnbSSHClient read GetSSHClient write SetSSHClient;
    property ShowSSHErrors: Boolean read FShowSSHErrors
      write FShowSSHErrors default True;
    property EnableSyntaxHighlighting: Boolean read FEnableSyntaxHighlighting
      write FEnableSyntaxHighlighting default False;
    property SemanticHighlighting: Boolean read GetSemanticHighlighting
      write SetSemanticHighlighting default False;
    property AutoCopySelection: Boolean read FAutoCopySelection
      write FAutoCopySelection default True;
    property PasteOnRightClick: Boolean read FPasteOnRightClick
      write FPasteOnRightClick default True;
    property OnData: TTerminalDataEvent read FOnData write FOnData;
    (* OnUserInput is keyboard/paste input only. It excludes terminal
       auto-responses and mouse-tracking bytes. *)
    property OnUserInput: TTerminalDataEvent read FOnUserInput write FOnUserInput;
    property OnHostOutput: TTerminalHostOutputEvent
      read FOnHostOutput write FOnHostOutput;
  end;


implementation

const
  SelectionProtectionMs = 250;
  ScrollBarWidth = 8.0;
  ScrollBarMinThumbHeight = 24.0;

{ TnbTerminalControl }

constructor TnbTerminalControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FTheme := TTerminalTheme.Create;

  FBuffer := TTerminalBuffer.Create(80, 24, FTheme);
  FBuffer.OnResponse := HandleBufferResponse;
  FParser := TAnsiParser.Create(FTheme);
  FTraceEnabled := SameText(GetEnvironmentVariable('NTIZGIN_TERMINAL_TRACE'), '1');
  if FTraceEnabled then
  begin
    FTraceFileName := TPath.Combine(TPath.GetTempPath, 'nTizgin-terminal-trace.log');
    TFile.AppendAllText(FTraceFileName, Format('# %s terminal trace start%s', [DateTimeToStr(Now), sLineBreak]), TEncoding.UTF8);
  end;
  FRenderer := TTerminalRenderer.Create(FBuffer, FTheme);

  FCursorTimer := TTimer.Create(Self);
  FCursorTimer.Interval := 500;
  FCursorTimer.OnTimer := CursorTimerProc;
  FCursorTimer.Enabled := True;

  FRenderTimer := TTimer.Create(Self);
  FRenderTimer.Interval := 16;
  FRenderTimer.OnTimer := RenderTimerProc;
  FRenderTimer.Enabled := True;
  FNeedRedraw := True;


  FPendingHostCols := 0;
  FPendingHostRows := 0;

  FSelectionAutoScrollTimer := TTimer.Create(Self);
  FSelectionAutoScrollTimer.Interval := 50;
  FSelectionAutoScrollTimer.OnTimer := SelectionAutoScrollTimerProc;
  FSelectionAutoScrollTimer.Enabled := False;
  FSelectionAutoScrollDirection := 0;
  FSelectionMousePos := TPointF.Zero;

  FSyntaxRules := TList<TSyntaxRule>.Create;
  FEnableSyntaxHighlighting := False;

  FIsSelecting := False;
  FSelectionDragOrigin := TPointF.Zero;
  FSelectionDragStarted := False;
  FClearSelectionOnNextAction := False;
  FSelectionProtectedUntilTick := 0;
  FSuppressNextRightMouseUp := False;
  FLastClickTick := 0;
  FLastClickPoint := TPointF.Zero;
  FAutoCopySelection := True;
  FPasteOnRightClick := True;
  FScrollBarDragging := False;
  FScrollBarDragOffset := 0;
  FActiveMouseButton := -1;
  FLastHostCols := 0;
  FLastHostRows := 0;
 FDeferHostResize := False;

  FShowSSHErrors := True;

  FSSHBridge := TTerminalSSHBridge.Create(Self);
  FSSHBridge.OnConnected := HandleSSHConnected;
  FSSHBridge.OnError := HandleSSHError;
  FSSHBridge.OnReadData := HandleSSHReadData;

  TabStop := False;
  CanFocus := True;
  HitTest := True;
end;

destructor TnbTerminalControl.Destroy;
begin
  FreeAndNil(FLocalSession);
  SetSSHClient(nil);  (* отписаться от старого клиента *)
  FSelectionAutoScrollTimer.Free;
  FRenderTimer.Free;
  FCursorTimer.Free;
  FSyntaxRules.Free;
  FSSHBridge.Free;
  FRenderer.Free;
  FParser.Free;
  FBuffer.Free;
  FTheme.Free;
  inherited;
end;

function TnbTerminalControl.GetTheme: TTerminalTheme;
begin
  Result := FTheme;
end;

function TnbTerminalControl.GetSemanticHighlighting: Boolean;
begin
  Result := Assigned(FRenderer) and FRenderer.SemanticHighlighting;
end;

procedure TnbTerminalControl.SetSemanticHighlighting(const Value: Boolean);
begin
  if Assigned(FRenderer) then
  begin
    FRenderer.SemanticHighlighting := Value;
    FNeedRedraw := True;
  end;
end;

procedure TnbTerminalControl.SetTheme(const Value: TTerminalTheme);
begin
  FBuffer.SetTheme(Value);
  FParser.SetTheme(FTheme);
  FRenderer.SetTheme(FTheme);

  FNeedRedraw := True;
  Repaint;
end;
function TnbTerminalControl.GetCols: Integer;
begin
  Result := FBuffer.Width;
end;

function TnbTerminalControl.GetRows: Integer;
begin
  Result := FBuffer.Height;
end;

function TnbTerminalControl.GetFontSize: Single;
begin
  if Assigned(FRenderer) then
    Result := FRenderer.FontSize
  else
    Result := 0;
end;

function TnbTerminalControl.GetFontWidthScale: Single;
begin
  Result := FRenderer.FontWidthScale;
end;

function TnbTerminalControl.GetFontHeightScale: Single;
begin
  Result := FRenderer.FontHeightScale;
end;

procedure TnbTerminalControl.SetFontHeightScale(const Value: Single);
begin
  if SameValue(FRenderer.FontHeightScale, Value, 0.001) then
    Exit;
  FRenderer.FontHeightScale := Value;
  UpdateTerminalSize(True);
  FNeedRedraw := True;
end;

procedure TnbTerminalControl.SetFontWidthScale(const Value: Single);
begin
  if SameValue(FRenderer.FontWidthScale, Value, 0.001) then
    Exit;
  FRenderer.FontWidthScale := Value;
  UpdateTerminalSize(True);
  FNeedRedraw := True;
end;

procedure TnbTerminalControl.SetFontSize(const Value: Single);
begin
  if not Assigned(FRenderer) then Exit;
  if FRenderer.FontSize <> Value then
  begin
    FRenderer.FontSize := Value;
    FRenderer.MeasureChar;
    FNeedRedraw := True;
  end;
end;

function TnbTerminalControl.GetFontFamily: string;
begin
  if Assigned(FRenderer) then
    Result := FRenderer.FontFamily
  else
    Result := '';
end;

procedure TnbTerminalControl.SetFontFamily(const Value: string);
begin
  if not Assigned(FRenderer) then Exit;
  if FRenderer.FontFamily <> Value then
  begin
    FRenderer.FontFamily := Value;
    FRenderer.MeasureChar;
    FNeedRedraw := True;
  end;
end;

function TnbTerminalControl.GetFontBold: Boolean;
begin
  if Assigned(FRenderer) then
    Result := FRenderer.FontBold
  else
    Result := False;
end;

procedure TnbTerminalControl.SetFontBold(Value: Boolean);
begin
  if not Assigned(FRenderer) then Exit;
  if FRenderer.FontBold <> Value then
  begin
    FRenderer.FontBold := Value;
    FRenderer.MeasureChar;
    FNeedRedraw := True;
  end;
end;

function TnbTerminalControl.GetFontItalic: Boolean;
begin
  if Assigned(FRenderer) then
    Result := FRenderer.FontItalic
  else
    Result := False;
end;

procedure TnbTerminalControl.SetFontItalic(Value: Boolean);
begin
  if not Assigned(FRenderer) then Exit;
  if FRenderer.FontItalic <> Value then
  begin
    FRenderer.FontItalic := Value;
    FRenderer.MeasureChar;
    FNeedRedraw := True;
  end;
end;


procedure TnbTerminalControl.CursorTimerProc(Sender: TObject);
begin
  if not FBuffer.Cursor.Blink then
    Exit;
  FRenderer.ToggleCursorBlink;
  FNeedRedraw := True;
end;

procedure TnbTerminalControl.SetDeferHostResize(const Value: Boolean);
begin
  if FDeferHostResize = Value then
    Exit;

  FDeferHostResize := Value;
  if (not FDeferHostResize) and Assigned(FSSHBridge) and
    ((FBuffer.Width <> FLastHostCols) or
     (FBuffer.Height <> FLastHostRows)) then
    ScheduleHostResize(FBuffer.Width, FBuffer.Height);
end;

procedure TnbTerminalControl.RenderTimerProc(Sender: TObject);
begin
  if Assigned(FLocalSession) then FLocalSession.Pump;
  if FNeedRedraw then
  begin
    FNeedRedraw := False;
    Repaint;
  end;
end;

procedure TnbTerminalControl.Paint;
var
  ScreenSvc: IFMXScreenService;
  DPIScale: Single;
  ControlScale: Single;
begin
  inherited;
  DPIScale := 1.0;
  if TPlatformServices.Current.SupportsPlatformService(IFMXScreenService, ScreenSvc) then
    DPIScale := ScreenSvc.GetScreenScale;

  ControlScale := Max(Abs(AbsoluteScale.X), Abs(AbsoluteScale.Y));
  if ControlScale <= 0 then
    ControlScale := 1.0;

  FRenderer.Scale := DPIScale * ControlScale;
  FRenderer.ContentScale := ControlScale;
  FRenderer.UIScale := ControlScale;
  UpdateTerminalSize(False);

  FRenderer.Render(Canvas, LocalRect);
  DrawScrollBar(Canvas);
end;

procedure TnbTerminalControl.Resize;
begin
  inherited;

  UpdateTerminalSize(True);
  Repaint;
  FNeedRedraw := False;
end;

procedure TnbTerminalControl.DoExit;
begin
  if FActiveMouseButton >= 0 then
  begin
    SendMouseReport(FActiveMouseButton, Max(1, FBuffer.LastMouseCol),
      Max(1, FBuffer.LastMouseRow), [], mbsUp);
    FActiveMouseButton := -1;
  end;

  FScrollBarDragging := False;
  FIsSelecting := False;
  FSelectionAutoScrollDirection := 0;
  FSelectionAutoScrollTimer.Enabled := False;
  ReleaseCapture;
  inherited;
end;

procedure TnbTerminalControl.UpdateTerminalSize(NotifyHost: Boolean);
var
  NewCols, NewRows: Integer;
begin
  if not Assigned(FRenderer) or not Assigned(FBuffer) then
    Exit;

  if (FRenderer.CharWidth = 0) or (FRenderer.CharHeight = 0) then
  begin
    FRenderer.MeasureChar;
    if (FRenderer.CharWidth = 0) or (FRenderer.CharHeight = 0) then
      Exit;
  end;

  if (Width <= 0) or (Height <= 0) then
    Exit;

  NewCols := Trunc(Width / FRenderer.CharWidth);
  NewRows := Trunc(Height / FRenderer.CharHeight);

  ApplyTerminalSize(NewCols, NewRows, NotifyHost);
end;

procedure TnbTerminalControl.ApplyTerminalSize(NewCols, NewRows: Integer;
  NotifyHost: Boolean);
var
  SizeChanged: Boolean;
begin
  if (NewCols <= 0) or (NewRows <= 0) then
    Exit;

  SizeChanged := (NewCols <> FBuffer.Width) or (NewRows <> FBuffer.Height);

  if SizeChanged then
  begin
    FBuffer.Resize(NewCols, NewRows);
    FNeedRedraw := True;
  end;

  if (not FDeferHostResize) and (NotifyHost or SizeChanged) and
    Assigned(FSSHBridge) and
    ((NewCols <> FLastHostCols) or (NewRows <> FLastHostRows)) then
    ScheduleHostResize(NewCols, NewRows);
end;

procedure TnbTerminalControl.ScheduleHostResize(NewCols, NewRows: Integer);
begin
  if (NewCols <= 0) or (NewRows <= 0) then
    Exit;

  FPendingHostCols := NewCols;
  FPendingHostRows := NewRows;
  FlushHostResize;
end;

procedure TnbTerminalControl.FlushHostResize;
begin
  if (FPendingHostCols <= 0) or (FPendingHostRows <= 0) then
    Exit;

  if Assigned(FSSHBridge) and
    ((FPendingHostCols <> FLastHostCols) or
     (FPendingHostRows <> FLastHostRows)) then
  begin
    if Assigned(FLocalSession) and FLocalSession.Running then
      FLocalSession.ResizePTY(FPendingHostCols, FPendingHostRows)
    else FSSHBridge.ResizePTY(FPendingHostCols, FPendingHostRows);
    FLastHostCols := FPendingHostCols;
    FLastHostRows := FPendingHostRows;
  end;

  FPendingHostCols := 0;
  FPendingHostRows := 0;
end;

procedure TnbTerminalControl.AddSyntaxRule(const Keyword, AnsiColor: string; IgnoreCase: Boolean);
var
  Rule: TSyntaxRule;
begin
  Rule.Keyword := Keyword;
  Rule.AnsiColor := AnsiColor;
  Rule.IgnoreCase := IgnoreCase;
  FSyntaxRules.Add(Rule);
end;

procedure TnbTerminalControl.ClearSyntaxRules;
begin
  FSyntaxRules.Clear;
end;

function TnbTerminalControl.ApplyHighlighting(const Input: string): string;
var
  Position, I, MatchRule, MatchLength, EscapeLength: Integer;
  Rule: TSyntaxRule;
  Builder: TStringBuilder;

  function RuleMatches(const ARule: TSyntaxRule; const APosition: Integer): Boolean;
  var
    KeywordLength: Integer;
  begin
    KeywordLength := Length(ARule.Keyword);
    if (KeywordLength = 0) or
      (APosition + KeywordLength - 1 > Length(Input)) then
      Exit(False);

    if ARule.IgnoreCase then
      Result := StrLIComp(PChar(Input) + APosition - 1,
        PChar(ARule.Keyword), KeywordLength) = 0
    else
      Result := StrLComp(PChar(Input) + APosition - 1,
        PChar(ARule.Keyword), KeywordLength) = 0;
  end;

  function AnsiSequenceLength(const APosition: Integer): Integer;
  var
    P: Integer;
  begin
    Result := 0;
    if (Input[APosition] <> #27) then
      Exit;
    if APosition = Length(Input) then
      Exit(1);

    case Input[APosition + 1] of
      '[':
        begin
          P := APosition + 2;
          while P <= Length(Input) do
          begin
            if Ord(Input[P]) in [$40..$7E] then
              Exit(P - APosition + 1);
            Inc(P);
          end;
          Result := Length(Input) - APosition + 1;
        end;
      ']':
        begin
          P := APosition + 2;
          while P <= Length(Input) do
          begin
            if Input[P] = #7 then
              Exit(P - APosition + 1);
            if (Input[P] = #27) and (P < Length(Input)) and
              (Input[P + 1] = '\') then
              Exit(P - APosition + 2);
            Inc(P);
          end;
          Result := Length(Input) - APosition + 1;
        end;
    else
      Result := Min(2, Length(Input) - APosition + 1);
    end;
  end;

begin
  if (Input = '') or (FSyntaxRules.Count = 0) then
    Exit(Input);

  Builder := TStringBuilder.Create(Length(Input));
  try
    Position := 1;
    while Position <= Length(Input) do
    begin
      EscapeLength := AnsiSequenceLength(Position);
      if EscapeLength > 0 then
      begin
        Builder.Append(Input, Position - 1, EscapeLength);
        Inc(Position, EscapeLength);
        Continue;
      end;

      MatchRule := -1;
      MatchLength := 0;
      for I := 0 to FSyntaxRules.Count - 1 do
      begin
        Rule := FSyntaxRules[I];
        if (Length(Rule.Keyword) > MatchLength) and
          RuleMatches(Rule, Position) then
        begin
          MatchRule := I;
          MatchLength := Length(Rule.Keyword);
        end;
      end;

      if MatchRule >= 0 then
      begin
        Rule := FSyntaxRules[MatchRule];
        Builder.Append(Rule.AnsiColor);
        Builder.Append(Input, Position - 1, MatchLength);
        Builder.Append(#27'[0m');
        Inc(Position, MatchLength);
      end
      else
      begin
        Builder.Append(Input[Position]);
        Inc(Position);
      end;
    end;

    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TnbTerminalControl.WriteText(const Text: string);
var
  Commands: TArray<TAnsiCommand>;
  I: Integer;
  ProcessedText: string;
begin
  if Text = '' then
    Exit;

  if FEnableSyntaxHighlighting and (FSyntaxRules.Count > 0) and (not FBuffer.IsAlternateBuffer) then
    ProcessedText := ApplyHighlighting(Text)
  else
    ProcessedText := Text;

  if FParser.Parse(ProcessedText, Commands) then
  begin
    TraceAnsiCommands(Commands);
    if Length(Commands) = 0 then
      Exit;
    for I := 0 to High(Commands) do
      FBuffer.ProcessCommand(Commands[I]);

    FNeedRedraw := True;
  end;
end;

procedure TnbTerminalControl.Clear;
begin
  FBuffer.Clear;
  FBuffer.Scrollback.Clear;
  FBuffer.ResetViewport;
  FParser.Reset;
  FNeedRedraw := True;
end;

procedure TnbTerminalControl.CopyToClipboard;
var
  Text: string;
begin
  if not FBuffer.HasSelection then Exit;

  Text := FBuffer.GetSelectedText;
  if TTerminalClipboard.CopyText(Text) then
    FClearSelectionOnNextAction := True;
end;

procedure TnbTerminalControl.ClearSelectionOnTerminalAction;
begin
  if IsSelectionProtected then
    Exit;

  if FClearSelectionOnNextAction and FBuffer.HasSelection then
  begin
    FBuffer.ClearSelection;
    FNeedRedraw := True;
  end;
  FClearSelectionOnNextAction := False;
end;

function TnbTerminalControl.IsSelectionProtected: Boolean;
begin
  Result := (FSelectionProtectedUntilTick <> 0) and
    (TStopwatch.GetTimeStamp < FSelectionProtectedUntilTick);
  if not Result then
    FSelectionProtectedUntilTick := 0;
end;

procedure TnbTerminalControl.ProtectSelection;
begin
  FSelectionProtectedUntilTick := TStopwatch.GetTimeStamp +
    (TStopwatch.Frequency * SelectionProtectionMs div 1000);
end;

function TnbTerminalControl.TrySelectWordAt(Col, Row: Integer): Boolean;
var
  Line: TTerminalLine;
  StartCol, EndCol, AbsY: Integer;

  function IsWordChar(const S: string): Boolean;
  var
    C: Char;
  begin
    Result := False;
    if S = '' then
      Exit;

    C := S[1];
    Result := C.IsLetterOrDigit or CharInSet(C,
      ['_', '-', '.', '/', '\', '~', ':', '@']);
  end;

begin
  Result := False;

  if (Col < 0) or (Row < 0) or (Row >= FBuffer.Height) then
    Exit;

  Line := FBuffer.GetRenderLine(Row);
  if Col >= Length(Line.Cells) then
    Exit;
  if (Col > 0) and (Line.Cells[Col].Width = 0) then
    Dec(Col);
  if not IsWordChar(Line.Cells[Col].Char) then
    Exit;

  StartCol := Col;
  while (StartCol > 0) and IsWordChar(Line.Cells[StartCol - 1].Char) do
    Dec(StartCol);

  EndCol := Col;
  while (EndCol + 1 < Length(Line.Cells)) and IsWordChar(Line.Cells[EndCol + 1].Char) do
    Inc(EndCol);

  AbsY := FBuffer.ScreenYToAbsolute(Row);
  FSelectionStartAbs := TPoint.Create(StartCol, AbsY);
  FBuffer.SetSelection(StartCol, AbsY, EndCol, AbsY);
  FIsSelecting := False;
  FSelectionDragOrigin := TPointF.Zero;
  FSelectionDragStarted := False;
  FClearSelectionOnNextAction := False;
  if FAutoCopySelection then
    CopyToClipboard;
  ProtectSelection;
  FNeedRedraw := True;
  Result := True;
end;

procedure TnbTerminalControl.ResetViewportToBottom;
begin
  if FBuffer.ViewportOffset <> 0 then
  begin
    FBuffer.ResetViewport;
    FNeedRedraw := True;
  end;
end;

procedure TnbTerminalControl.PasteFromClipboard;
var
  Text: string;
begin
  ResetViewportToBottom;

  if FBuffer.HasSelection then
  begin
    FBuffer.ClearSelection;
    FClearSelectionOnNextAction := False;
    FNeedRedraw := True;
  end;

  if TTerminalClipboard.ReadText(Text) then
  begin
    if Assigned(FOnData) then
    begin
      // Нормализуем окончания строк: Enter в терминале = #13 (CR).
      // CRLF и LF → CR, иначе \r\n отправляет два события и дают пустые строки.
      Text := TTerminalClipboard.NormalizeLineEndings(Text);
      if FBuffer.BracketedPaste then
        Text := TTerminalClipboard.WrapBracketedPaste(Text);
      TraceTerminalData('IN paste', Text);
      FOnData(Text);
      if Assigned(FOnUserInput) then
        FOnUserInput(Text);
    end;
  end;
end;

procedure TnbTerminalControl.KeyDown(var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState);
var
  S: string;
begin
  // Обработка Copy/Paste
  // Ctrl + Shift + C или Ctrl + Insert -> Копировать
  if ((ssCtrl in Shift) and (ssShift in Shift) and (Key = vkC)) or
     ((ssCtrl in Shift) and (Key = vkInsert)) then
  begin
    CopyToClipboard;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  // Ctrl + Shift + V или Shift + Insert -> Вставить
  if ((ssCtrl in Shift) and (ssShift in Shift) and (Key = vkV)) or
     ((ssShift in Shift) and (Key = vkInsert)) then
  begin
    PasteFromClipboard;
    Key := 0;
    KeyChar := #0;
    Exit;
  end;

  S := TTerminalInput.TranslateKey(Key, KeyChar, Shift, FBuffer.AppCursorKeys);
  if (S <> '') and Assigned(FOnData) then
  begin
    ClearSelectionOnTerminalAction;
    ResetViewportToBottom;
    TraceKeyInput(Key, KeyChar, Shift, S);
    FOnData(S);
    if Assigned(FOnUserInput) then
      FOnUserInput(S);
    Key := 0;
    KeyChar := #0;
    FNeedRedraw := True;
  end;
end;

procedure TnbTerminalControl.DialogKey(var Key: Word; Shift: TShiftState);
var
  KeyChar: WideChar;
begin
  if (Key = vkTab) and (Root <> nil) and (Root.Focused <> nil) and (Root.Focused.GetObject = Self) then
  begin
    KeyChar := #0;
    InjectKey(Key, KeyChar, Shift);
    Key := 0;
    Exit;
  end;

  inherited;
end;
procedure TnbTerminalControl.InjectKey(Key: Word; KeyChar: WideChar;
  Shift: TShiftState);
begin
  // Переиспользуем штатную обработку ввода (перевод клавиши и отправку в SSH).
  KeyDown(Key, KeyChar, Shift);
end;

procedure TnbTerminalControl.SendMouseReport(AButton, ACol, ARow: Integer;
  AShift: TShiftState; AState: TMouseButtonState);
var
  S: string;
begin
  S := TTerminalInput.BuildMouseReport(AButton, ACol, ARow, AShift,
    AState, FBuffer.MouseModes);

  if (S <> '') and Assigned(FOnData) then
  begin
    TraceTerminalData('IN mouse', S);
    FOnData(S);
  end;
end;

function TnbTerminalControl.MouseReportingEnabled: Boolean;
begin
  Result := (FBuffer.MouseModes * [mtm1000_Click, mtm1002_Wheel,
    mtm1003_Any]) <> [];
end;

function TnbTerminalControl.TryMouseCell(const X, Y: Single;
  OneBased: Boolean; out Col, Row: Integer): Boolean;
begin
  Result := (FRenderer.CharWidth > 0) and (FRenderer.CharHeight > 0) and
    (FBuffer.Width > 0) and (FBuffer.Height > 0);
  if not Result then
    Exit;

  Col := EnsureRange(Trunc(X / FRenderer.CharWidth), 0, FBuffer.Width - 1);
  Row := EnsureRange(Trunc(Y / FRenderer.CharHeight), 0, FBuffer.Height - 1);
  if OneBased then
  begin
    Inc(Col);
    Inc(Row);
  end;
end;

class function TnbTerminalControl.MouseButtonCode(Button: TMouseButton;
  out Code: Integer): Boolean;
begin
  Result := True;
  case Button of
    TMouseButton.mbLeft: Code := 0;
    TMouseButton.mbMiddle: Code := 1;
    TMouseButton.mbRight: Code := 2;
  else
    Result := False;
  end;
end;

function TnbTerminalControl.ScrollBarVisible: Boolean;
begin
  Result := (FBuffer <> nil) and not FBuffer.IsAlternateBuffer and
    (FBuffer.Scrollback.Count > 0) and (Height > 0);
end;

procedure TnbTerminalControl.GetScrollBarRects(out TrackRect,
  ThumbRect: TRectF);
var
  HistoryCount, TotalLines: Integer;
  ThumbHeight, Travel, Position: Single;
begin
  TrackRect := TRectF.Create(Max(0, Width - ScrollBarWidth), 0, Width, Height);
  ThumbRect := TRectF.Empty;
  if not ScrollBarVisible then
    Exit;

  HistoryCount := FBuffer.Scrollback.Count;
  TotalLines := HistoryCount + FBuffer.Height;
  ThumbHeight := Max(ScrollBarMinThumbHeight,
    TrackRect.Height * FBuffer.Height / TotalLines);
  ThumbHeight := Min(TrackRect.Height, ThumbHeight);
  Travel := TrackRect.Height - ThumbHeight;
  Position := (HistoryCount - FBuffer.ViewportOffset) / HistoryCount;
  ThumbRect := TRectF.Create(TrackRect.Left, TrackRect.Top + Travel * Position,
    TrackRect.Right, TrackRect.Top + Travel * Position + ThumbHeight);
end;

procedure TnbTerminalControl.SetViewportFromThumb(const ThumbTop: Single);
var
  TrackRect, ThumbRect: TRectF;
  Travel, Position: Single;
  NewOffset: Integer;
begin
  GetScrollBarRects(TrackRect, ThumbRect);
  Travel := TrackRect.Height - ThumbRect.Height;
  if Travel <= 0 then
    NewOffset := 0
  else
  begin
    Position := EnsureRange((ThumbTop - TrackRect.Top) / Travel, 0.0, 1.0);
    NewOffset := Round(FBuffer.Scrollback.Count * (1.0 - Position));
  end;

  FBuffer.ScrollViewport(NewOffset - FBuffer.ViewportOffset);
  FNeedRedraw := True;
end;

procedure TnbTerminalControl.DrawScrollBar(const ACanvas: TCanvas);
var
  TrackRect, ThumbRect: TRectF;
begin
  if not ScrollBarVisible then
    Exit;

  GetScrollBarRects(TrackRect, ThumbRect);
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := ($28 shl 24) or
    (FTheme.TerminalUIColor and $00FFFFFF);
  ACanvas.FillRect(TrackRect, 0, 0, [], 1);
  ACanvas.Fill.Color := TAlphaColor($90000000) or
    (FTheme.DefaultFG and TAlphaColor($00FFFFFF));
  ACanvas.FillRect(ThumbRect, ScrollBarWidth / 2, ScrollBarWidth / 2,
    AllCorners, 1);
end;

procedure TnbTerminalControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  Col, Row, Cb, AbsY: Integer;
  IsMouseReporting: Boolean;
  OverrideSelection: Boolean;
  ClickTick: Int64;
  IsDoubleClick: Boolean;
begin
  inherited;
  SetFocus;
  Capture;
  if (Button = TMouseButton.mbLeft) and ScrollBarVisible then
  begin
    var TrackRect, ThumbRect: TRectF;
    GetScrollBarRects(TrackRect, ThumbRect);
    if TrackRect.Contains(TPointF.Create(X, Y)) then
    begin
      FScrollBarDragging := True;
      Cursor := crSizeNS;
      if ThumbRect.Contains(TPointF.Create(X, Y)) then
        FScrollBarDragOffset := Y - ThumbRect.Top
      else
      begin
        FScrollBarDragOffset := ThumbRect.Height / 2;
        SetViewportFromThumb(Y - FScrollBarDragOffset);
      end;
      Exit;
    end;
  end;

  if not TryMouseCell(X, Y, False, Col, Row) then
    Exit;

  ClickTick := TStopwatch.GetTimeStamp;
  IsDoubleClick := (Button = TMouseButton.mbLeft) and
    (FLastClickTick <> 0) and
    ((ClickTick - FLastClickTick) * 1000 div TStopwatch.Frequency <= 500) and
    (Abs(X - FLastClickPoint.X) <= 4) and
    (Abs(Y - FLastClickPoint.Y) <= 4);

  FLastClickTick := ClickTick;
  FLastClickPoint := TPointF.Create(X, Y);

  if not IsDoubleClick then
    ClearSelectionOnTerminalAction;

  var RepCol := Col + 1;
  var RepRow := Row + 1;

  IsMouseReporting := MouseReportingEnabled;
  OverrideSelection := (ssShift in Shift);

  if (Button = TMouseButton.mbRight) and FPasteOnRightClick and
    ((not IsMouseReporting) or OverrideSelection) then
  begin
    FSuppressNextRightMouseUp := True;
    PasteFromClipboard;
    Exit;
  end;

  if IsDoubleClick and ((not IsMouseReporting) or OverrideSelection) and
    TrySelectWordAt(Col, Row) then
    Exit;

  // Логика выделения и вставки
  if (not IsMouseReporting) or OverrideSelection then
  begin
    if Button = TMouseButton.mbLeft then
    begin
      AbsY := FBuffer.ScreenYToAbsolute(Row);
      FSelectionStartAbs := TPoint.Create(Col, AbsY);
      FSelectionDragOrigin := TPointF.Create(X, Y);
      FSelectionDragStarted := False;
      FIsSelecting := True;
    end;
    Exit;
  end;

  if not MouseButtonCode(Button, Cb) then
    Exit;

  SendMouseReport(Cb, RepCol, RepRow, Shift, mbsDown);
  FBuffer.LastMouseCol := RepCol;
  FBuffer.LastMouseRow := RepRow;
  FActiveMouseButton := Cb;
end;

procedure TnbTerminalControl.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  Col, Row, Cb: Integer;
  IsMouseReporting: Boolean;
  OverrideSelection: Boolean;
begin
  ReleaseCapture;

  if FScrollBarDragging then
  begin
    FScrollBarDragging := False;
    Cursor := crHandPoint;
    Exit;
  end;

  if (Button = TMouseButton.mbRight) and FSuppressNextRightMouseUp then
  begin
    FSuppressNextRightMouseUp := False;
    Exit;
  end;

  // Завершение выделения
  if FIsSelecting then
  begin
    FIsSelecting := False;
    FSelectionDragStarted := False;
    FSelectionAutoScrollDirection := 0;
    FSelectionAutoScrollTimer.Enabled := False;
    if FAutoCopySelection and FBuffer.HasSelection then
      CopyToClipboard;
    if FBuffer.HasSelection then
      ProtectSelection;
    Exit;
  end;

  IsMouseReporting := MouseReportingEnabled;
  OverrideSelection := (ssShift in Shift);

  if OverrideSelection and (FActiveMouseButton < 0) then Exit;

  if (not IsMouseReporting) and (FActiveMouseButton < 0) then
    Exit;

  if not TryMouseCell(X, Y, True, Col, Row) then
    Exit;

  if FActiveMouseButton >= 0 then
    Cb := FActiveMouseButton
  else if not MouseButtonCode(Button, Cb) then
    Exit;

  SendMouseReport(Cb, Col, Row, Shift, mbsUp);
  FBuffer.LastMouseCol := Col;
  FBuffer.LastMouseRow := Row;
  FActiveMouseButton := -1;
end;

procedure TnbTerminalControl.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Col, Row, Cb: Integer;
  OverrideSelection: Boolean;
begin
  if FScrollBarDragging then
  begin
    Cursor := crSizeNS;
    SetViewportFromThumb(Y - FScrollBarDragOffset);
    Exit;
  end;

  if ScrollBarVisible then
  begin
    var TrackRect, ThumbRect: TRectF;
    GetScrollBarRects(TrackRect, ThumbRect);
    if TrackRect.Contains(TPointF.Create(X, Y)) then
    begin
      Cursor := crHandPoint;
      Exit;
    end;
  end;

  if not TryMouseCell(X, Y, False, Col, Row) then
    Exit;

  // Обновление выделения
  if FIsSelecting then
  begin
    if not FSelectionDragStarted then
    begin
      if (Abs(X - FSelectionDragOrigin.X) < 4) and
         (Abs(Y - FSelectionDragOrigin.Y) < 4) then
        Exit;
      FSelectionDragStarted := True;
    end;
    FSelectionMousePos := TPointF.Create(X, Y);
    { FMX may clamp captured mouse coordinates to the control bounds, so start
      auto-scroll while the pointer is in the first/last visible cell row. }
    if Y < FRenderer.CharHeight then
      FSelectionAutoScrollDirection := 1
    else if Y >= Height - FRenderer.CharHeight then
      FSelectionAutoScrollDirection := -1
    else
      FSelectionAutoScrollDirection := 0;
    FSelectionAutoScrollTimer.Enabled := FSelectionAutoScrollDirection <> 0;
    UpdateSelectionAt(X, Y);
    Exit;
  end;

  OverrideSelection := (ssShift in Shift);

  if OverrideSelection then
  begin
     Cursor := crIBeam;
     Exit;
  end;

  var RepCol := Col + 1;
  var RepRow := Row + 1;

  if not ((mtm1003_Any in FBuffer.MouseModes) or
    ((mtm1002_Wheel in FBuffer.MouseModes) and
    (Shift * [ssLeft, ssRight, ssMiddle] <> []))) then
  begin
    Cursor := crIBeam;
    Exit;
  end;

  Cursor := crIBeam;

  if (RepCol = FBuffer.LastMouseCol) and (RepRow = FBuffer.LastMouseRow) then
    Exit;

  FBuffer.LastMouseCol := RepCol;
  FBuffer.LastMouseRow := RepRow;

  if ssLeft in Shift then
    Cb := 0
  else if ssMiddle in Shift then
    Cb := 1
  else if ssRight in Shift then
    Cb := 2
  else
    Cb := 3;

  SendMouseReport(Cb, RepCol, RepRow, Shift, mbsMove);
end;

procedure TnbTerminalControl.UpdateSelectionAt(const X, Y: Single);
var
  Col, Row, AbsY: Integer;
begin
  if not FIsSelecting then
    Exit;

  if not TryMouseCell(X, Y, False, Col, Row) then
    Exit;
  AbsY := FBuffer.ScreenYToAbsolute(Row);

  FBuffer.SetSelection(FSelectionStartAbs.X, FSelectionStartAbs.Y, Col, AbsY);
  FNeedRedraw := True;
end;

procedure TnbTerminalControl.SelectionAutoScrollTimerProc(Sender: TObject);
var
  OldOffset: Integer;
begin
  if (not FIsSelecting) or (FSelectionAutoScrollDirection = 0) then
  begin
    FSelectionAutoScrollTimer.Enabled := False;
    Exit;
  end;

  OldOffset := FBuffer.ViewportOffset;
  FBuffer.ScrollViewport(FSelectionAutoScrollDirection);
  if FBuffer.ViewportOffset = OldOffset then
  begin
    FSelectionAutoScrollTimer.Enabled := False;
    Exit;
  end;

  UpdateSelectionAt(FSelectionMousePos.X, FSelectionMousePos.Y);
end;

procedure TnbTerminalControl.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
var
  Col, Row, Cb, ScrollLines: Integer;
  LocalPos: TPointF;
  MouseService: IFMXMouseService;
  MousePos: TPointF;
begin
  if ssCtrl in Shift then
  begin
    inherited;
    Exit;
  end;

  // Случай 1: Мышь НЕ отслеживается
  if not MouseReportingEnabled then
  begin
    ScrollLines := Max(1, Abs(WheelDelta) div 120) * 3;
    if WheelDelta > 0 then
      FBuffer.ScrollViewport(ScrollLines)
    else
      FBuffer.ScrollViewport(-ScrollLines);
    FNeedRedraw := True;
    Handled := True;
    Exit;
  end;

  // Случай 2: Мышь отслеживается
  if not TPlatformServices.Current.SupportsPlatformService(IFMXMouseService, MouseService) then
  begin
     Handled := False;
     Exit;
  end;

  MousePos := MouseService.GetMousePos;
  LocalPos := AbsoluteToLocal(MousePos);

  if not TryMouseCell(LocalPos.X, LocalPos.Y, True, Col, Row) then
    Exit;

  if WheelDelta > 0 then
    Cb := 64
  else
    Cb := 65;

  SendMouseReport(Cb, Col, Row, Shift, mbsDown);
  Handled := True;
end;

function TnbTerminalControl.GetSSHClient: TnbSSHClient;
begin
  if Assigned(FSSHBridge) then
    Result := FSSHBridge.Client
  else
    Result := nil;
end;

procedure TnbTerminalControl.SetSSHClient(const Value: TnbSSHClient);
begin
  if Assigned(Value) then StopLocalSession;
  if GetSSHClient = Value then Exit;

  FSSHBridge.Client := Value;

  if Assigned(Value) then
  begin
    (* Подписываем терминал на свои собственные события - чтобы пробрасывать в SSH *)
    OnData := FSSHBridge.SendTerminalData;
    OnResized := HandleOwnResize;
    FLastHostCols := 0;
    FLastHostRows := 0;
    FPendingHostCols := 0;
    FPendingHostRows := 0;
    UpdateTerminalSize(True);
  end
  else
  begin
    (* Без SSH-клиента терминал работает как пассивный отображатель *)
    OnData := nil;
    OnResized := nil;
  end;
end;

procedure TnbTerminalControl.StartLocalSession(const Executable: string;
  const Arguments: TArray<string>; const Directory: string);
var
  Client: TnbSSHClient;
begin
  Client := GetSSHClient;
  if Assigned(Client) and
    (Client.Status in [ssConnecting, ssAuthenticating, ssConnected]) then
    raise EInvalidOperation.Create('Disconnect SSH before starting a local terminal');
  SetSSHClient(nil);
  if not Assigned(FLocalSession) then
  begin
    FLocalSession := TnbLocalTerminalSession.Create(Self);
    FLocalSession.OnReadData := HandleSSHReadData;
    FLocalSession.OnError := HandleLocalError;
  end;
  UpdateTerminalSize(False);
  Clear;
  FLocalSession.Start(Executable, Arguments, Directory, Cols, Rows);
  OnData := FLocalSession.SendText;
  OnResized := HandleOwnResize;
  FLastHostCols := Cols;
  FLastHostRows := Rows;
  FPendingHostCols := 0;
  FPendingHostRows := 0;
  SetFocus;
end;

procedure TnbTerminalControl.StopLocalSession;
begin
  if Assigned(FLocalSession) then FLocalSession.Stop;
end;

procedure TnbTerminalControl.HandleLocalError(Sender: TObject; const Data: string);
begin
  WriteText(#13#10 + #27'[1;31mLocal terminal: ' + Data + #27'[0m'#13#10);
end;

procedure TnbTerminalControl.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
end;

procedure TnbTerminalControl.HandleSSHConnected(Sender: TObject);
begin
  SetFocus;
  (* Передаём актуальный размер - на случай если форма успела
     отресайзиться пока шёл коннект *)
  UpdateTerminalSize(False);
  FSSHBridge.ResizePTY(Cols, Rows);
  FLastHostCols := Cols;
  FLastHostRows := Rows;
end;

procedure TnbTerminalControl.HandleSSHError(Sender: TObject;
  const ErrorMessage: string);
begin
  (* Пишем сообщение об ошибке прямо в терминал, красным *)
  if FShowSSHErrors and (ErrorMessage <> '') then
    WriteText(#13#10 + #27'[1;31m' +
      'SSH error: ' + ErrorMessage +
      #27'[0m'#13#10);
end;

procedure TnbTerminalControl.TraceKeyInput(Key: Word; KeyChar: WideChar;
  Shift: TShiftState; const Data: string);
var
  ShiftText: string;
begin
  if not FTraceEnabled then
    Exit;

  ShiftText := '';
  if ssShift in Shift then ShiftText := ShiftText + 'Shift,';
  if ssAlt in Shift then ShiftText := ShiftText + 'Alt,';
  if ssCtrl in Shift then ShiftText := ShiftText + 'Ctrl,';
  if ssCommand in Shift then ShiftText := ShiftText + 'Command,';
  if ssLeft in Shift then ShiftText := ShiftText + 'Left,';
  if ssRight in Shift then ShiftText := ShiftText + 'Right,';
  if ssMiddle in Shift then ShiftText := ShiftText + 'Middle,';
  if ShiftText = '' then
    ShiftText := 'none'
  else
    Delete(ShiftText, Length(ShiftText), 1);

  TFile.AppendAllText(FTraceFileName,
    Format('[%s] KEY key=%d keychar=%d shift=%s%s',
    [FormatDateTime('hh:nn:ss.zzz', Now), Key, Ord(KeyChar), ShiftText,
     sLineBreak]), TEncoding.UTF8);
  TraceTerminalData('IN key', Data);
end;
procedure TnbTerminalControl.TraceTerminalData(const Direction, Data: string);
var
  I, Code: Integer;
  Hex, View: TStringBuilder;

  function VisibleByte(ACode: Integer): string;
  begin
    case ACode of
      9: Result := '<TAB>';
      10: Result := '<LF>';
      13: Result := '<CR>';
      27: Result := '<ESC>';
      32..126: Result := Char(ACode);
    else
      Result := '<' + IntToStr(ACode) + '>';
    end;
  end;

begin
  if (not FTraceEnabled) or (Data = '') then
    Exit;

  Hex := TStringBuilder.Create;
  View := TStringBuilder.Create;
  try
    for I := 1 to Length(Data) do
    begin
      Code := Ord(Data[I]) and $FF;
      if I > 1 then
        Hex.Append(' ');
      Hex.Append(IntToHex(Code, 2));
      View.Append(VisibleByte(Code));
    end;

    TFile.AppendAllText(FTraceFileName,
      Format('[%s] %s len=%d cursor=%d,%d scroll=%d..%d hex=%s text=%s%s',
      [FormatDateTime('hh:nn:ss.zzz', Now), Direction, Length(Data),
       FBuffer.Cursor.X + 1, FBuffer.Cursor.Y + 1,
       FBuffer.ScrollTop + 1, FBuffer.ScrollBottom + 1,
       Hex.ToString, View.ToString, sLineBreak]), TEncoding.UTF8);
  finally
    Hex.Free;
    View.Free;
  end;
end;

procedure TnbTerminalControl.TraceAnsiCommands(const Commands: TArray<TAnsiCommand>);
var
  I, J: Integer;
  Params: string;
begin
  if (not FTraceEnabled) or (Length(Commands) = 0) then
    Exit;

  for I := 0 to High(Commands) do
  begin
    Params := '';
    for J := 0 to High(Commands[I].Params) do
    begin
      if J > 0 then
        Params := Params + ',';
      Params := Params + IntToStr(Commands[I].Params[J]);
    end;

    TFile.AppendAllText(FTraceFileName,
      Format('[%s] CMD %s params=[%s] char="%s" cursor=%d,%d%s',
      [FormatDateTime('hh:nn:ss.zzz', Now),
       GetEnumName(TypeInfo(TAnsiParserCommand), Ord(Commands[I].Command)),
       Params, Commands[I].Char, FBuffer.Cursor.X + 1, FBuffer.Cursor.Y + 1,
       sLineBreak]), TEncoding.UTF8);
  end;
end;
procedure TnbTerminalControl.HandleSSHReadData(Sender: TObject; const Data: string);
var
  Filtered: string;
begin
  Filtered := Data;
  if Assigned(FOnHostOutput) then
    FOnHostOutput(Filtered);
  if Filtered <> '' then
  begin
    TraceTerminalData('OUT raw', Filtered);
    WriteText(Filtered);
  end;
end;

procedure TnbTerminalControl.HandleOwnResize(Sender: TObject);
begin
  ScheduleHostResize(Cols, Rows);
end;

procedure TnbTerminalControl.HandleBufferResponse(const S: string);
begin
  (* Ответы терминала на запросы хоста (DA, DSR) уходят в тот же канал,
     что и пользовательский ввод *)
  if Assigned(FOnData) then
  begin
    TraceTerminalData('IN response', S);
    FOnData(S);
  end;
end;

function TnbTerminalControl.LoadThemeFromFile(const FileName: string;
  out ErrorMsg: string): Boolean;
var
  NewTheme: TTerminalTheme;
begin
  Result := False;
  ErrorMsg := '';

  NewTheme := TTerminalTheme.Create;
  try
    if not TGoghThemeLoader.LoadIntoTheme(FileName, NewTheme, ErrorMsg) then
      Exit;

    (* Применяем тему - это сделает SetAllDirty внутри *)
    Self.Theme := NewTheme;
    Result := True;

  finally
    NewTheme.Free;
  end;
end;

procedure TnbTerminalControl.LoadThemeFromFile(const FileName: string);
var
  ErrorMsg: string;
begin
  if not LoadThemeFromFile(FileName, ErrorMsg) then
    raise Exception.CreateFmt('Cannot load theme "%s": %s',
      [FileName, ErrorMsg]);
end;

procedure TnbTerminalControl.LoadDefaultTheme;
var
  DefaultTheme: TTerminalTheme;
begin
  DefaultTheme := TTerminalTheme.Create;
  try
    (* TTerminalTheme в конструкторе уже выставляет дефолтные цвета *)
    Self.Theme := DefaultTheme;

  finally
    DefaultTheme.Free;
  end;
end;

class function TnbTerminalControl.EnumThemes(
  const Folder: string): TGoghThemeInfoArray;
begin
  Result := TGoghThemeLoader.EnumThemes(Folder);
end;

end.
