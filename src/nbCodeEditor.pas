unit nbCodeEditor;

interface

uses
  System.Classes, System.SysUtils, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Memo,
  nbTextDocument;

type
  TnbCodeEditorFindOptions = set of (cfoCaseSensitive, cfoWrapAround);

  TnbCodeEditorPalette = record
    Background: TAlphaColor;
    Text: TAlphaColor;
    MutedText: TAlphaColor;
    Selection: TAlphaColor;
    CurrentLine: TAlphaColor;
    GutterBackground: TAlphaColor;
    GutterBorder: TAlphaColor;
    LineNumber: TAlphaColor;
    ActiveLineNumber: TAlphaColor;
    Caret: TAlphaColor;
    Keyword: TAlphaColor;
    KeywordAlt: TAlphaColor;
    KeywordControl: TAlphaColor;
    StringColor: TAlphaColor;
    NumberColor: TAlphaColor;
    CommentColor: TAlphaColor;
    DirectiveColor: TAlphaColor;
    FieldColor: TAlphaColor;
    FunctionColor: TAlphaColor;
    PunctuationColor: TAlphaColor;
    SelectorColor: TAlphaColor;
    AttributeColor: TAlphaColor;
    ErrorColor: TAlphaColor;
    class function Default: TnbCodeEditorPalette; static;
  end;

  TnbCodeEditor = class(TMemo)
  private
    FDocument: TnbTextDocument;
    FUpdating: Boolean;
    FPushing: Boolean;
    FPalette: TnbCodeEditorPalette;
    FUserOnChange: TNotifyEvent;
    FUserOnChangeTracking: TNotifyEvent;
    procedure SetDocument(const AValue: TnbTextDocument);
    procedure HandleMemoChange(Sender: TObject);
    procedure HandleMemoChangeTracking(Sender: TObject);
    procedure HandleDocumentChanged(Sender: TObject;
      AChanges: TnbTextDocumentChanges);
    procedure PullDocument;
    procedure ConfigurePresentation;
    procedure PushSyntaxPalette;
    procedure ApplySyntax;
  protected
    function DefinePresentationName: string; override;
    procedure ApplyStyle; override;
    procedure Notification(AComponent: TComponent;
      Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyPalette(const APalette: TnbCodeEditorPalette);
    procedure RefreshDocument;
    procedure EnsureCaretVisible;
    function FindNext(const ASearchText: string;
      AOptions: TnbCodeEditorFindOptions): Boolean;
    function FindPrevious(const ASearchText: string;
      AOptions: TnbCodeEditorFindOptions): Boolean;
    function ReplaceCurrent(const ASearchText, AReplaceText: string;
      AOptions: TnbCodeEditorFindOptions): Boolean;
    function ReplaceAll(const ASearchText, AReplaceText: string;
      AOptions: TnbCodeEditorFindOptions): Integer;
    property Palette: TnbCodeEditorPalette read FPalette;
  published
    property Document: TnbTextDocument read FDocument write SetDocument;
    property OnChange: TNotifyEvent read FUserOnChange write FUserOnChange;
    property OnChangeTracking: TNotifyEvent read FUserOnChangeTracking
      write FUserOnChangeTracking;
  end;

implementation

uses
  System.StrUtils, FMX.Objects, FMX.RichEdit.Style, Syntax.Code,
  Syntax.Code.Pascal, Syntax.Code.JSON, Syntax.Code.SQL, Syntax.Code.Python,
  Syntax.Code.HTML, Syntax.Code.CSS, Syntax.Code.MarkDown, Syntax.Code.Shell;

class function TnbCodeEditorPalette.Default: TnbCodeEditorPalette;
begin
  Result.Background := $FF10151E;
  Result.Text := $FFD8DEE9;
  Result.MutedText := $FF7F8A9A;
  Result.Selection := $FF3A557A;
  Result.CurrentLine := $FF182231;
  Result.GutterBackground := $FF10151E;
  Result.GutterBorder := $FF2B3545;
  Result.LineNumber := $FF687486;
  Result.ActiveLineNumber := $FF62B8FF;
  Result.Caret := $FF62B8FF;
  Result.Keyword := $FF81A1C1;
  Result.KeywordAlt := $FFB48EAD;
  Result.KeywordControl := $FF88C0D0;
  Result.StringColor := $FFA3BE8C;
  Result.NumberColor := $FFD08770;
  Result.CommentColor := $FF616E88;
  Result.DirectiveColor := $FFEBCB8B;
  Result.FieldColor := $FF8FBCBB;
  Result.FunctionColor := $FF88C0D0;
  Result.PunctuationColor := $FFD8DEE9;
  Result.SelectorColor := $FF81A1C1;
  Result.AttributeColor := $FFEBCB8B;
  Result.ErrorColor := $FFBF616A;
end;

constructor TnbCodeEditor.Create(AOwner: TComponent);
begin
  inherited;
  FPalette := TnbCodeEditorPalette.Default;
  inherited OnChange := HandleMemoChange;
  inherited OnChangeTracking := HandleMemoChangeTracking;
  WordWrap := False;
  StyledSettings := [];
  TextSettings.Font.Family := 'Cascadia Mono';
  TextSettings.Font.Size := 12;
end;

destructor TnbCodeEditor.Destroy;
begin
  SetDocument(nil);
  inherited;
end;

function TnbCodeEditor.DefinePresentationName: string;
begin
  Result := 'RichEditStyled';
end;

procedure TnbCodeEditor.ApplyStyle;
begin
  inherited;
  ConfigurePresentation;
end;

procedure TnbCodeEditor.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FDocument) then
  begin
    if FDocument <> nil then
      FDocument.Unsubscribe(HandleDocumentChanged);
    FDocument := nil;
  end;
end;

procedure TnbCodeEditor.SetDocument(const AValue: TnbTextDocument);
begin
  if FDocument = AValue then
    Exit;
  if FDocument <> nil then
  begin
    FDocument.Unsubscribe(HandleDocumentChanged);
    FDocument.RemoveFreeNotification(Self);
  end;
  FDocument := AValue;
  if FDocument <> nil then
  begin
    FDocument.FreeNotification(Self);
    FDocument.Subscribe(HandleDocumentChanged);
  end;
  PullDocument;
end;

procedure TnbCodeEditor.HandleMemoChange(Sender: TObject);
begin
  if Assigned(FUserOnChange) then
    FUserOnChange(Self);
end;

procedure TnbCodeEditor.HandleMemoChangeTracking(Sender: TObject);
begin
  if not FUpdating and (FDocument <> nil) and not FDocument.ReadOnly then
  begin
    (* Ввод пользователя уже отображён в memo: документ обновляем,
       но его dcContent-эхо не проецируем обратно — иначе текст
       перезаписывается целиком и каретка сбрасывается в начало *)
    FPushing := True;
    try
      FDocument.Text := Text;
    finally
      FPushing := False;
    end;
  end;
  if Assigned(FUserOnChangeTracking) then
    FUserOnChangeTracking(Self);
end;

procedure TnbCodeEditor.HandleDocumentChanged(Sender: TObject;
  AChanges: TnbTextDocumentChanges);
begin
  if (dcContent in AChanges) and not FPushing then
    PullDocument
  else
  begin
    if dcState in AChanges then
      ReadOnly := FDocument.ReadOnly;
    if dcMetadata in AChanges then
      ApplySyntax;
  end;
end;

procedure TnbCodeEditor.PullDocument;
begin
  FUpdating := True;
  try
    if FDocument = nil then
    begin
      Text := '';
      ReadOnly := False;
    end
    else
    begin
      Text := FDocument.Text;
      ReadOnly := FDocument.ReadOnly;
    end;
  finally
    FUpdating := False;
  end;
  (* Presentation создаётся позже ApplyStyle, поэтому конфигурацию
     повторяем здесь: к моменту загрузки документа она уже существует *)
  ConfigurePresentation;
end;

procedure TnbCodeEditor.ConfigurePresentation;
  function FindBackground(AObject: TFmxObject): TRectangle;
  var
    I: Integer;
  begin
    Result := nil;
    if AObject = nil then
      Exit;
    for I := 0 to AObject.ChildrenCount - 1 do
    begin
      if SameText(AObject.Children[I].StyleName, 'background') and
        (AObject.Children[I] is TRectangle) then
        Exit(TRectangle(AObject.Children[I]));
      Result := FindBackground(AObject.Children[I]);
      if Result <> nil then
        Exit;
    end;
  end;

  function FindStyleObject(AObject: TFmxObject;
    const AName: string): TFmxObject;
  var
    I: Integer;
  begin
    Result := nil;
    if AObject = nil then
      Exit;
    for I := 0 to AObject.ChildrenCount - 1 do
    begin
      if SameText(AObject.Children[I].StyleName, AName) then
        Exit(AObject.Children[I]);
      Result := FindStyleObject(AObject.Children[I], AName);
      if Result <> nil then
        Exit;
    end;
  end;

  (* В кастомных стилях 'background' может быть TActiveStyleObject —
     перекрасить его нельзя. Тогда вставляем внутрь собственный
     TRectangle на задний план; при пересоздании стиля он погибает
     вместе с ним и создаётся здесь заново. *)
  function EnsureBackgroundRect(ARichEdit: TRichEditStyled): TRectangle;
  const
    RECT_NAME = 'nbEditorBackground';
  var
    Host: TFmxObject;
    I: Integer;
  begin
    Result := nil;
    Host := FindStyleObject(ARichEdit, 'background');
    if Host = nil then
      Exit;
    for I := 0 to Host.ChildrenCount - 1 do
      if SameText(Host.Children[I].StyleName, RECT_NAME) then
        Exit(TRectangle(Host.Children[I]));
    Result := TRectangle.Create(Host);
    Result.StyleName := RECT_NAME;
    Result.Parent := Host;
    Result.Align := TAlignLayout.Contents;
    Result.HitTest := False;
    Result.SendToBack;
  end;
var
  RichEdit: TRichEditStyled;
  Background: TRectangle;
begin
  TextSettings.FontColor := FPalette.Text;
  SelectionFill.Color := FPalette.Selection;
  if not (Presentation is TRichEditStyled) then
    Exit;
  RichEdit := TRichEditStyled(Presentation);
  Background := FindBackground(RichEdit);
  if Background = nil then
    Background := EnsureBackgroundRect(RichEdit);
  if Background <> nil then
  begin
    Background.Fill.Kind := TBrushKind.Solid;
    Background.Fill.Color := FPalette.Background;
    Background.Stroke.Kind := TBrushKind.None;
  end;
  RichEdit.ShowGutter := True;
  RichEdit.GutterNumberAllLines := True;
  RichEdit.ShowCurrentLine := True;
  RichEdit.SyntaxSameFontFamily := True;
  RichEdit.SyntaxSameFontSize := True;
  RichEdit.UseSelectedTextColor := True;
  RichEdit.ColorSelectedText := FPalette.Text;
  RichEdit.ColorCurrentLine := FPalette.CurrentLine;
  RichEdit.ColorGutterLine := FPalette.GutterBorder;
  RichEdit.ColorLineNumberNormal := FPalette.LineNumber;
  RichEdit.ColorLineNumberActive := FPalette.ActiveLineNumber;
  RichEdit.ColorCaret := FPalette.Caret;
  RichEdit.GutterFont.Assign(Font);
  RichEdit.GutterFont.Size := 11;
  ApplySyntax;
end;

procedure TnbCodeEditor.PushSyntaxPalette;
var
  SyntaxPalette: TCodeSyntaxPalette;
begin
  SyntaxPalette.Keyword := FPalette.Keyword;
  SyntaxPalette.KeywordAlt := FPalette.KeywordAlt;
  SyntaxPalette.KeywordControl := FPalette.KeywordControl;
  SyntaxPalette.StringColor := FPalette.StringColor;
  SyntaxPalette.NumberColor := FPalette.NumberColor;
  SyntaxPalette.CommentColor := FPalette.CommentColor;
  SyntaxPalette.DirectiveColor := FPalette.DirectiveColor;
  SyntaxPalette.FieldColor := FPalette.FieldColor;
  SyntaxPalette.FunctionColor := FPalette.FunctionColor;
  SyntaxPalette.PunctuationColor := FPalette.PunctuationColor;
  SyntaxPalette.SelectorColor := FPalette.SelectorColor;
  SyntaxPalette.AttributeColor := FPalette.AttributeColor;
  SyntaxPalette.ErrorColor := FPalette.ErrorColor;
  TCodeSyntax.SetPalette(SyntaxPalette);
end;

procedure TnbCodeEditor.ApplySyntax;
var
  LanguageId: string;
begin
  if not (Presentation is TRichEditStyled) then
    Exit;
  (* Глобальная палитра Syntax.Code по умолчанию рассчитана на тёмный фон;
     перед созданием syntax-инстанса синхронизируем её с палитрой редактора *)
  PushSyntaxPalette;
  if FDocument <> nil then
    LanguageId := FDocument.LanguageId
  else
    LanguageId := '';
  TRichEditStyled(Presentation).SetCodeSyntaxName(LanguageId, Font,
    FPalette.Text);
end;

procedure TnbCodeEditor.ApplyPalette(const APalette: TnbCodeEditorPalette);
begin
  FPalette := APalette;
  PushSyntaxPalette;
  ConfigurePresentation;
  Repaint;
end;

procedure TnbCodeEditor.RefreshDocument;
begin
  PullDocument;
end;

procedure TnbCodeEditor.EnsureCaretVisible;
begin
  Model.Caret.Visible := True;
  Model.Caret.Show;
  Repaint;
end;
function SameSearchText(const ALeft, ARight: string;
  ACaseSensitive: Boolean): Boolean;
begin
  if ACaseSensitive then
    Result := ALeft = ARight
  else
    Result := SameText(ALeft, ARight);
end;

function TnbCodeEditor.FindNext(const ASearchText: string;
  AOptions: TnbCodeEditorFindOptions): Boolean;
var
  Source, Needle: string;
  StartPos, FoundPos: Integer;
begin
  Result := False;
  if ASearchText = '' then
    Exit;

  Source := Text;
  Needle := ASearchText;
  if not (cfoCaseSensitive in AOptions) then
  begin
    Source := LowerCase(Source);
    Needle := LowerCase(Needle);
  end;

  StartPos := SelStart + SelLength + 1;
  if StartPos < 1 then
    StartPos := 1;
  if StartPos > Length(Source) then
    StartPos := Length(Source) + 1;

  FoundPos := PosEx(Needle, Source, StartPos);
  if (FoundPos = 0) and (cfoWrapAround in AOptions) then
    FoundPos := PosEx(Needle, Source, 1);

  if FoundPos > 0 then
  begin
    SelStart := FoundPos - 1;
    SelLength := Length(ASearchText);
    SetFocus;
    EnsureCaretVisible;
    Result := True;
  end;
end;

function TnbCodeEditor.FindPrevious(const ASearchText: string;
  AOptions: TnbCodeEditorFindOptions): Boolean;
var
  Source, Needle: string;
  SearchLimit, ScanPos, FoundPos, NextPos: Integer;
begin
  Result := False;
  if ASearchText = '' then
    Exit;

  Source := Text;
  Needle := ASearchText;
  if not (cfoCaseSensitive in AOptions) then
  begin
    Source := LowerCase(Source);
    Needle := LowerCase(Needle);
  end;

  SearchLimit := SelStart;
  FoundPos := 0;
  ScanPos := 1;
  while ScanPos <= SearchLimit do
  begin
    NextPos := PosEx(Needle, Source, ScanPos);
    if (NextPos = 0) or (NextPos > SearchLimit) then
      Break;
    FoundPos := NextPos;
    ScanPos := NextPos + 1;
  end;

  if (FoundPos = 0) and (cfoWrapAround in AOptions) then
  begin
    ScanPos := 1;
    while ScanPos <= Length(Source) do
    begin
      NextPos := PosEx(Needle, Source, ScanPos);
      if NextPos = 0 then
        Break;
      FoundPos := NextPos;
      ScanPos := NextPos + 1;
    end;
  end;

  if FoundPos > 0 then
  begin
    SelStart := FoundPos - 1;
    SelLength := Length(ASearchText);
    SetFocus;
    EnsureCaretVisible;
    Result := True;
  end;
end;

function TnbCodeEditor.ReplaceCurrent(const ASearchText,
  AReplaceText: string; AOptions: TnbCodeEditorFindOptions): Boolean;
var
  Source, NewText: string;
  ReplaceStart: Integer;
begin
  Result := False;
  if (ASearchText = '') or ReadOnly then
    Exit;

  if (SelLength <> Length(ASearchText)) or
    not SameSearchText(SelText, ASearchText, cfoCaseSensitive in AOptions) then
    if not FindNext(ASearchText, AOptions) then
      Exit;

  Source := Text;
  ReplaceStart := SelStart + 1;
  NewText := Copy(Source, 1, ReplaceStart - 1) + AReplaceText +
    Copy(Source, ReplaceStart + SelLength, MaxInt);
  if FDocument <> nil then
    FDocument.Text := NewText
  else
    Text := NewText;
  SelStart := ReplaceStart - 1 + Length(AReplaceText);
  SelLength := 0;
  Result := True;
  FindNext(ASearchText, AOptions);
end;

function TnbCodeEditor.ReplaceAll(const ASearchText, AReplaceText: string;
  AOptions: TnbCodeEditorFindOptions): Integer;
var
  Source, ScanSource, Needle, Replacement, NewText: string;
  SearchPos, FoundPos, LastCopyPos: Integer;
begin
  Result := 0;
  if (ASearchText = '') or ReadOnly then
    Exit;

  Source := Text;
  ScanSource := Source;
  Needle := ASearchText;
  if not (cfoCaseSensitive in AOptions) then
  begin
    ScanSource := LowerCase(ScanSource);
    Needle := LowerCase(Needle);
  end;

  Replacement := AReplaceText;
  NewText := '';
  SearchPos := 1;
  LastCopyPos := 1;
  while SearchPos <= Length(ScanSource) do
  begin
    FoundPos := PosEx(Needle, ScanSource, SearchPos);
    if FoundPos = 0 then
      Break;
    NewText := NewText + Copy(Source, LastCopyPos, FoundPos - LastCopyPos) +
      Replacement;
    Inc(Result);
    SearchPos := FoundPos + Length(ASearchText);
    LastCopyPos := SearchPos;
  end;

  if Result = 0 then
    Exit;

  NewText := NewText + Copy(Source, LastCopyPos, MaxInt);
  if FDocument <> nil then
    FDocument.Text := NewText
  else
    Text := NewText;
  SelStart := 0;
  SelLength := 0;
  FindNext(ASearchText, AOptions);
end;
initialization
  RegisterFmxClasses([TnbCodeEditor]);

  (* Явная регистрация highlighters вместо initialization-секций языковых
     юнитов: те юниты нигде не референсятся напрямую (только через
     строковый language id в реестре TCodeSyntax), и cross-platform
     smart-linker (в частности на Linux) может посчитать их
     неиспользуемыми и выбросить из сборки вместе с регистрацией. Этот
     юнит гарантированно слинкован (TnbCodeEditor используется во всём
     приложении), поэтому вызов отсюда безопасен на любой платформе. *)
  Syntax.Code.Pascal.RegisterPascalSyntax;
  Syntax.Code.JSON.RegisterJsonSyntax;
  Syntax.Code.SQL.RegisterSqlSyntax;
  Syntax.Code.Python.RegisterPythonSyntax;
  Syntax.Code.HTML.RegisterHtmlSyntax;
  Syntax.Code.CSS.RegisterCssSyntax;
  Syntax.Code.MarkDown.RegisterMarkDownSyntax;
  Syntax.Code.Shell.RegisterShellSyntax;

end.