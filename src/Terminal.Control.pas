unit Terminal.Control;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Math, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Dialogs,
  FMX.Skia, Skia, FMX.Consts, FMX.Platform,
  Terminal.Types, Terminal.Buffer, Terminal.AnsiParser, Terminal.Renderer,
  Terminal.Theme, Terminal.Input, Terminal.SSHBridge, ModernSSHClient,
  GoghThemeLoader;

type
  TTerminalDataEvent = procedure(const S: string) of object;
  TTerminalHostOutputEvent = procedure(var S: string) of object;

  TSyntaxRule = record
    Keyword: string;
    AnsiColor: string;
    IgnoreCase: Boolean;
  end;

  TnbTerminalControl = class(TSkPaintBox)
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

    FSyntaxRules: TList<TSyntaxRule>;
    FEnableSyntaxHighlighting: Boolean;

    // Для выделения
    FIsSelecting: Boolean;
    FSelectionStartAbs: TPoint;
    FAutoCopySelection: Boolean;
    FPasteOnRightClick: Boolean;
    FSSHBridge: TTerminalSSHBridge;
    FLastHostCols: Integer;
    FLastHostRows: Integer;

    function GetSSHClient: TnbSSHClient;
    procedure SetSSHClient(const Value: TnbSSHClient);
    procedure HandleSSHConnected(Sender: TObject);
    procedure HandleSSHError(Sender: TObject; const ErrorMessage: string);
    procedure HandleSSHReadData(Sender: TObject; const Data: string);
    procedure HandleOwnResize(Sender: TObject);
    procedure HandleBufferResponse(const S: string);

    procedure CursorTimerProc(Sender: TObject);
    procedure RenderTimerProc(Sender: TObject);

    function GetCols: Integer;
    function GetRows: Integer;
    function GetFontSize: Single;
    procedure SetFontSize(const Value: Single);
    function GetFontFamily: string;
    procedure SetFontFamily(const Value: string);
    function GetFontBold: Boolean;
    procedure SetFontBold(Value: Boolean);
    function GetFontItalic: Boolean;
    procedure SetFontItalic(Value: Boolean);
    function GetTheme: TTerminalTheme;
    procedure SetTheme(const Value: TTerminalTheme);

    procedure UpdateTerminalSize(NotifyHost: Boolean);
    procedure ApplyTerminalSize(NewCols, NewRows: Integer;
      NotifyHost: Boolean);
    procedure SendMouseReport(AButton, ACol, ARow: Integer; AShift: TShiftState;
      AState: TMouseButtonState);

    function ApplyHighlighting(const Input: string): string;
    procedure ResetViewportToBottom;

    // Буфер обмена
    procedure CopyToClipboard;
    procedure PasteFromClipboard;

protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Draw(const Canvas: ISkCanvas; const Dest: TRectF; const Opacity: Single); override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;

    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure WriteText(const Text: string);
    procedure Clear;

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
    property OnData: TTerminalDataEvent read FOnData write FOnData;
    (* OnUserInput — только ввод пользователя (клавиатура и вставка из буфера),
       без авто-ответов терминала и mouse-tracking. Предназначено для
       зеркалирования ввода (broadcast) во внешних приложениях. *)
    property OnUserInput: TTerminalDataEvent read FOnUserInput write FOnUserInput;
    property OnHostOutput: TTerminalHostOutputEvent
      read FOnHostOutput write FOnHostOutput;
    property Cols: Integer read GetCols;
    property Rows: Integer read GetRows;

    property EnableSyntaxHighlighting: Boolean read FEnableSyntaxHighlighting write FEnableSyntaxHighlighting;
    property AutoCopySelection: Boolean read FAutoCopySelection write FAutoCopySelection;
    property PasteOnRightClick: Boolean read FPasteOnRightClick write FPasteOnRightClick;

  published
    property FontSize: Single read GetFontSize write SetFontSize;
    property FontFamily: string read GetFontFamily write SetFontFamily;
    property FontBold: Boolean read GetFontBold write SetFontBold;
    property FontItalic: Boolean read GetFontItalic write SetFontItalic;
    property Theme: TTerminalTheme read GetTheme write SetTheme;
    property SSHClient: TnbSSHClient read GetSSHClient write SetSSHClient;
  end;


implementation

uses
  System.Rtti;


{ TnbTerminalControl }

constructor TnbTerminalControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FTheme := TTerminalTheme.Create;

  FBuffer := TTerminalBuffer.Create(80, 24, FTheme);
  FBuffer.OnResponse := HandleBufferResponse;
  FParser := TAnsiParser.Create(FTheme);
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

  FSyntaxRules := TList<TSyntaxRule>.Create;
  FEnableSyntaxHighlighting := False;

  FIsSelecting := False;
  FAutoCopySelection := True;
  FPasteOnRightClick := True;
  FLastHostCols := 0;
  FLastHostRows := 0;

  FSSHBridge := TTerminalSSHBridge.Create(Self);
  FSSHBridge.OnConnected := HandleSSHConnected;
  FSSHBridge.OnError := HandleSSHError;
  FSSHBridge.OnReadData := HandleSSHReadData;

  TabStop := False;
  CanFocus := True;
  HitTest := True;

  DrawCacheKind := TSkDrawCacheKind.Never;
end;

destructor TnbTerminalControl.Destroy;
begin
  SetSSHClient(nil);  (* отписаться от старого клиента *)
  FSyntaxRules.Free;
  FRenderTimer.Free;
  FTheme.Free;
  FCursorTimer.Free;
  FSSHBridge.Free;
  FRenderer.Free;
  FParser.Free;
  FBuffer.Free;
  inherited;
end;

function TnbTerminalControl.GetTheme: TTerminalTheme;
begin
  Result := FTheme;
end;

procedure TnbTerminalControl.SetTheme(const Value: TTerminalTheme);
begin
  FBuffer.SetTheme(Value);
  FParser.SetTheme(FTheme);
  FRenderer.SetTheme(FTheme);

  FNeedRedraw := True;
  Redraw;
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
  FRenderer.ToggleCursorBlink;
  FNeedRedraw := True;
end;

procedure TnbTerminalControl.RenderTimerProc(Sender: TObject);
begin
  if FNeedRedraw then
  begin
    FNeedRedraw := False;
    Redraw;
  end;
end;

procedure TnbTerminalControl.Draw(const Canvas: ISkCanvas; const Dest: TRectF; const Opacity: Single);
var
  ScreenSvc: IFMXScreenService;
  DPIScale: Single;
begin
  inherited;
  DPIScale := 1.0;
  if TPlatformServices.Current.SupportsPlatformService(IFMXScreenService, ScreenSvc) then
    DPIScale := ScreenSvc.GetScreenScale;

  FRenderer.Scale := DPIScale;
  UpdateTerminalSize(True);

  FRenderer.Render(Canvas, Dest);
end;

procedure TnbTerminalControl.Resize;
begin
  inherited;

  UpdateTerminalSize(True);

  Redraw;
  FNeedRedraw := False;
end;

procedure TnbTerminalControl.UpdateTerminalSize(NotifyHost: Boolean);
var
  NewCols, NewRows: Integer;
begin
  if not Assigned(FRenderer) or not Assigned(FBuffer) then
    Exit;

  FRenderer.MeasureChar;

  if (FRenderer.CharWidth = 0) or (FRenderer.CharHeight = 0) then
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

  if NotifyHost and Assigned(FSSHBridge) and
    ((NewCols <> FLastHostCols) or (NewRows <> FLastHostRows)) then
  begin
    FSSHBridge.ResizePTY(NewCols, NewRows);
    FLastHostCols := NewCols;
    FLastHostRows := NewRows;
  end;
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
  I: Integer;
  Rule: TSyntaxRule;
  Flags: TReplaceFlags;
  Replacement: string;
begin
  Result := Input;

  for I := 0 to FSyntaxRules.Count - 1 do
  begin
    Rule := FSyntaxRules[I];
    if Rule.Keyword = '' then Continue;

    Flags := [rfReplaceAll];
    if Rule.IgnoreCase then Include(Flags, rfIgnoreCase);

    Replacement := Rule.AnsiColor + Rule.Keyword + #27'[0m';

    Result := StringReplace(Result, Rule.Keyword, Replacement, Flags);
  end;
end;

procedure TnbTerminalControl.WriteText(const Text: string);
var
  Commands: TArray<TAnsiCommand>;
  I: Integer;
  ProcessedText: string;
begin
  if FEnableSyntaxHighlighting and (FSyntaxRules.Count > 0) and (not FBuffer.IsAlternateBuffer) then
    ProcessedText := ApplyHighlighting(Text)
  else
    ProcessedText := Text;

  if FParser.Parse(ProcessedText, Commands) then
  begin
    for I := 0 to High(Commands) do
      FBuffer.ProcessCommand(Commands[I]);

    FNeedRedraw := True;
  end;
end;

  procedure TnbTerminalControl.Clear;
begin
  FBuffer.Clear;
  FParser.Reset;
  FNeedRedraw := True;
end;

procedure TnbTerminalControl.CopyToClipboard;
var
  ClipboardService: IFMXClipboardService;
  Text: string;
begin
  if not FBuffer.HasSelection then Exit;

  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, ClipboardService) then
  begin
    Text := FBuffer.GetSelectedText;
    if Text <> '' then
      ClipboardService.SetClipboard(Text);
  end;
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
  ClipboardService: IFMXClipboardService;
  Value: TValue;
  Text: string;
begin
  ResetViewportToBottom;

  if FBuffer.HasSelection then
  begin
    FBuffer.ClearSelection;
    FNeedRedraw := True;
  end;

  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, ClipboardService) then
  begin
    Value := ClipboardService.GetClipboard;
    if not Value.IsEmpty then
    begin
      Text := Value.ToString;
      if (Text <> '') and Assigned(FOnData) then
      begin
        // Bracketed Paste Mode
        if FBuffer.BracketedPaste then
          Text := #27'[200~' + Text + #27'[201~';
        FOnData(Text);
        if Assigned(FOnUserInput) then
          FOnUserInput(Text);
      end;
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

  ResetViewportToBottom;

  S := TTerminalInput.TranslateKey(Key, KeyChar, Shift, FBuffer.AppCursorKeys);
  if (S <> '') and Assigned(FOnData) then
  begin
    FOnData(S);
    if Assigned(FOnUserInput) then
      FOnUserInput(S);
    Key := 0;
    KeyChar := #0;
    FNeedRedraw := True;
  end;
end;

procedure TnbTerminalControl.SendMouseReport(AButton, ACol, ARow: Integer;
  AShift: TShiftState; AState: TMouseButtonState);
var
  S: string;
begin
  S := TTerminalInput.BuildMouseReport(AButton, ACol, ARow, AShift,
    AState, FBuffer.MouseModes);

  if (S <> '') and Assigned(FOnData) then
    FOnData(S);
end;

procedure TnbTerminalControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  Col, Row, Cb, AbsY: Integer;
  IsMouseReporting: Boolean;
  OverrideSelection: Boolean;
begin
  inherited;
  SetFocus;
  if (FRenderer.CharWidth = 0) or (FRenderer.CharHeight = 0) then Exit;

  if (FBuffer.ViewportOffset <> 0) and not (ssShift in Shift) then
  begin
    ResetViewportToBottom;
    Exit;
  end;

  Col := Trunc(X / FRenderer.CharWidth);
  Row := Trunc(Y / FRenderer.CharHeight);

  var RepCol := Col + 1;
  var RepRow := Row + 1;

  IsMouseReporting := FBuffer.MouseModes <> [];
  OverrideSelection := (ssShift in Shift);

  // Логика выделения и вставки
  if (not IsMouseReporting) or OverrideSelection then
  begin
    if Button = TMouseButton.mbLeft then
    begin
      AbsY := FBuffer.ScreenYToAbsolute(Row);
      FSelectionStartAbs := TPoint.Create(Col, AbsY);
      FBuffer.SetSelection(Col, AbsY, Col, AbsY);
      FIsSelecting := True;
      FNeedRedraw := True;
    end
    else if (Button = TMouseButton.mbRight) and FPasteOnRightClick then
    begin
      PasteFromClipboard;
    end;
    Exit;
  end;

  case Button of
    TMouseButton.mbLeft: Cb := 0;
    TMouseButton.mbMiddle: Cb := 1;
    TMouseButton.mbRight: Cb := 2;
  else
    Exit;
  end;

  SendMouseReport(Cb, RepCol, RepRow, Shift, mbsDown);
  FBuffer.LastMouseCol := RepCol;
  FBuffer.LastMouseRow := RepRow;
end;

procedure TnbTerminalControl.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  Col, Row, Cb: Integer;
  IsMouseReporting: Boolean;
  OverrideSelection: Boolean;
begin
  // Завершение выделения
  if FIsSelecting then
  begin
    FIsSelecting := False;
    if FAutoCopySelection and FBuffer.HasSelection then
      CopyToClipboard;
    Exit;
  end;

  IsMouseReporting := FBuffer.MouseModes <> [];
  OverrideSelection := (ssShift in Shift);

  if OverrideSelection then Exit;

  if not IsMouseReporting then
    Exit;

  if not (mtm1006_SGR in FBuffer.MouseModes) and
     not (mtm1003_Any in FBuffer.MouseModes) then
       Exit;

  if (FRenderer.CharWidth = 0) or (FRenderer.CharHeight = 0) then Exit;

  Col := Trunc(X / FRenderer.CharWidth) + 1;
  Row := Trunc(Y / FRenderer.CharHeight) + 1;

  case Button of
    TMouseButton.mbLeft: Cb := 0;
    TMouseButton.mbMiddle: Cb := 1;
    TMouseButton.mbRight: Cb := 2;
  else
    Exit;
  end;

  SendMouseReport(Cb, Col, Row, Shift, mbsUp);
  FBuffer.LastMouseCol := Col;
  FBuffer.LastMouseRow := Row;
end;

procedure TnbTerminalControl.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Col, Row, Cb, AbsY: Integer;
  OverrideSelection: Boolean;
begin
  if (FRenderer.CharWidth = 0) or (FRenderer.CharHeight = 0) then Exit;

  Col := Trunc(X / FRenderer.CharWidth);
  Row := Trunc(Y / FRenderer.CharHeight);

  // Обновление выделения
  if FIsSelecting then
  begin
    Col := Max(0, Min(Col, FBuffer.Width - 1));
    Row := Max(0, Min(Row, FBuffer.Height - 1));

    AbsY := FBuffer.ScreenYToAbsolute(Row);

    FBuffer.SetSelection(FSelectionStartAbs.X, FSelectionStartAbs.Y, Col, AbsY);
    FNeedRedraw := True;
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
          ((mtm1006_SGR in FBuffer.MouseModes) and (Shift * [ssLeft, ssRight, ssMiddle] <> []))) then
  begin
    if FBuffer.MouseModes <> [] then
      Cursor := crHandPoint
    else
      Cursor := crIBeam;
    Exit;
  end;

  Cursor := crHandPoint;

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

procedure TnbTerminalControl.MouseWheel(Shift: TShiftState; WheelDelta: Integer;
  var Handled: Boolean);
var
  Col, Row, Cb: Integer;
  LocalPos: TPointF;
  MouseService: IFMXMouseService;
  MousePos: TPointF;
begin
  // Случай 1: Мышь НЕ отслеживается
  if not (mtm1002_Wheel in FBuffer.MouseModes) and
     not (mtm1006_SGR in FBuffer.MouseModes) then
  begin
    ResetViewportToBottom;
    if FBuffer.HasSelection then
    begin
      FBuffer.ClearSelection;
      FNeedRedraw := True;
    end;

    Handled := True;
    Exit;
  end;

  // Случай 2: Мышь отслеживается
  if (FRenderer.CharWidth = 0) or (FRenderer.CharHeight = 0) then Exit;

  if not TPlatformServices.Current.SupportsPlatformService(IFMXMouseService, MouseService) then
  begin
     Handled := False;
     Exit;
  end;

  MousePos := MouseService.GetMousePos;
  LocalPos := AbsoluteToLocal(MousePos);

  Col := Trunc(LocalPos.X / FRenderer.CharWidth) + 1;
  Row := Trunc(LocalPos.Y / FRenderer.CharHeight) + 1;

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
  if GetSSHClient = Value then Exit;

  FSSHBridge.Client := Value;

  if Assigned(Value) then
  begin
    (* Подписываем терминал на свои собственные события - чтобы пробрасывать в SSH *)
    OnData := FSSHBridge.SendTerminalData;
    OnResized := HandleOwnResize;
    FLastHostCols := 0;
    FLastHostRows := 0;
    UpdateTerminalSize(True);
  end
  else
  begin
    (* Без SSH-клиента терминал работает как пассивный отображатель *)
    OnData := nil;
    OnResized := nil;
  end;
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
  UpdateTerminalSize(True);
  FSSHBridge.ResizePTY(Cols, Rows);
  FLastHostCols := Cols;
  FLastHostRows := Rows;
end;

procedure TnbTerminalControl.HandleSSHError(Sender: TObject;
  const ErrorMessage: string);
begin
  (* Пишем сообщение об ошибке прямо в терминал, красным *)
  if ErrorMessage <> '' then
    WriteText(#13#10 + #27'[1;31m' +
      'SSH error: ' + ErrorMessage +
      #27'[0m'#13#10);
end;

procedure TnbTerminalControl.HandleSSHReadData(Sender: TObject; const Data: string);
var
  Filtered: string;
begin
  Filtered := Data;
  if Assigned(FOnHostOutput) then
    FOnHostOutput(Filtered);
  if Filtered <> '' then
    WriteText(Filtered);
end;

procedure TnbTerminalControl.HandleOwnResize(Sender: TObject);
begin
  FSSHBridge.ResizePTY(Cols, Rows);
end;

procedure TnbTerminalControl.HandleBufferResponse(const S: string);
begin
  (* Ответы терминала на запросы хоста (DA, DSR) уходят в тот же канал,
     что и пользовательский ввод *)
  if Assigned(FOnData) then
    FOnData(S);
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
    begin
      NewTheme.Free;
      Exit;
    end;

    (* Применяем тему - это сделает SetAllDirty внутри *)
    Self.Theme := NewTheme;
    Result := True;

    (* Триггерим SIGWINCH чтобы mc/htop/vim перерисовались с новой темой.
       Если SSH не подключён - просто пропускаем. *)
    if FSSHBridge.Connected then
    begin
      FSSHBridge.ResizePTY(Cols, Rows + 1);
      FSSHBridge.ResizePTY(Cols, Rows);
    end;
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

    if FSSHBridge.Connected then
    begin
      FSSHBridge.ResizePTY(Cols, Rows + 1);
      FSSHBridge.ResizePTY(Cols, Rows);
    end;
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
