unit nbCodeEditorFindBar;

interface

uses
  System.Classes, System.SysUtils, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Layouts, FMX.StdCtrls, FMX.Edit,
  FMX.Objects, nbCodeEditor, FMX.Controls.Presentation;

type
  TnbCodeEditorFindBar = class(TFrame)
    BackgroundRect: TRectangle;
    FindRow: TLayout;
    ReplaceRow: TLayout;
    FindEdit: TEdit;
    ReplaceEdit: TEdit;
    PrevButton: TButton;
    NextButton: TButton;
    ReplaceButton: TButton;
    ReplaceAllButton: TButton;
    CaseCheck: TCheckBox;
    WrapCheck: TCheckBox;
    CloseButton: TButton;
    StatusLabel: TLabel;
  private
    FEditor: TnbCodeEditor;
    FReplaceMode: Boolean;
    function Options: TnbCodeEditorFindOptions;
    function SearchText: string;
    procedure UpdateControls;
    procedure FindTextChanged(Sender: TObject);
    procedure FindKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char;
      Shift: TShiftState);
    procedure DoFindNext(Sender: TObject);
    procedure DoFindPrevious(Sender: TObject);
    procedure DoReplace(Sender: TObject);
    procedure DoReplaceAll(Sender: TObject);
    procedure DoClose(Sender: TObject);
    procedure SetEditor(const AValue: TnbCodeEditor);
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowFind;
    procedure ShowReplace;
    procedure Close;
    function TryHandleShortcut(var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState): Boolean;
    property Editor: TnbCodeEditor read FEditor write SetEditor;
  end;

implementation

{$R *.fmx}

constructor TnbCodeEditorFindBar.Create(AOwner: TComponent);
begin
  inherited;
  Align := TAlignLayout.Top;
  Height := 38;
  Visible := False;
  ClipChildren := True;

  FindEdit.OnChangeTracking := FindTextChanged;
  FindEdit.OnKeyDown := FindKeyDown;
  ReplaceEdit.OnChangeTracking := FindTextChanged;
  ReplaceEdit.OnKeyDown := FindKeyDown;
  CaseCheck.OnChange := FindTextChanged;
  WrapCheck.OnChange := FindTextChanged;
  PrevButton.OnClick := DoFindPrevious;
  NextButton.OnClick := DoFindNext;
  ReplaceButton.OnClick := DoReplace;
  ReplaceAllButton.OnClick := DoReplaceAll;
  CloseButton.OnClick := DoClose;
end;

procedure TnbCodeEditorFindBar.SetEditor(const AValue: TnbCodeEditor);
begin
  FEditor := AValue;
  UpdateControls;
end;

function TnbCodeEditorFindBar.Options: TnbCodeEditorFindOptions;
begin
  Result := [];
  if CaseCheck.IsChecked then
    Include(Result, cfoCaseSensitive);
  if WrapCheck.IsChecked then
    Include(Result, cfoWrapAround);
end;

function TnbCodeEditorFindBar.SearchText: string;
begin
  Result := FindEdit.Text;
end;

procedure TnbCodeEditorFindBar.UpdateControls;
var
  CanSearch, CanReplace: Boolean;
begin
  CanSearch := SearchText <> '';
  CanReplace := CanSearch and (FEditor <> nil) and not FEditor.ReadOnly;
  NextButton.Enabled := CanSearch;
  PrevButton.Enabled := CanSearch;
  ReplaceButton.Enabled := CanReplace;
  ReplaceAllButton.Enabled := CanReplace;
end;

procedure TnbCodeEditorFindBar.ShowFind;
begin
  FReplaceMode := False;
  Visible := True;
  Height := 38;
  ReplaceRow.Visible := False;
  if (FindEdit.Text = '') and (FEditor <> nil) and (FEditor.SelLength > 0) and
    (Pos(#10, FEditor.SelText) = 0) then
    FindEdit.Text := FEditor.SelText;
  StatusLabel.Text := '';
  UpdateControls;
  FindEdit.SetFocus;
  FindEdit.SelectAll;
end;

procedure TnbCodeEditorFindBar.ShowReplace;
begin
  FReplaceMode := True;
  Visible := True;
  Height := 72;
  ReplaceRow.Visible := True;
  if (FindEdit.Text = '') and (FEditor <> nil) and (FEditor.SelLength > 0) and
    (Pos(#10, FEditor.SelText) = 0) then
    FindEdit.Text := FEditor.SelText;
  StatusLabel.Text := '';
  UpdateControls;
  FindEdit.SetFocus;
  FindEdit.SelectAll;
end;

procedure TnbCodeEditorFindBar.Close;
begin
  Visible := False;
  StatusLabel.Text := '';
  if FEditor <> nil then
    FEditor.SetFocus;
end;

function TnbCodeEditorFindBar.TryHandleShortcut(var Key: Word;
  var KeyChar: WideChar; Shift: TShiftState): Boolean;
begin
  Result := True;
  if (Key = Ord('F')) and (ssCtrl in Shift) then
    ShowFind
  else if (Key = Ord('H')) and (ssCtrl in Shift) then
    ShowReplace
  else if Key = vkF3 then
  begin
    if ssShift in Shift then
      DoFindPrevious(Self)
    else
      DoFindNext(Self);
  end
  else if (Key = vkEscape) and Visible then
    Close
  else
    Exit(False);
  Key := 0;
  KeyChar := #0;
end;

procedure TnbCodeEditorFindBar.FindTextChanged(Sender: TObject);
begin
  StatusLabel.Text := '';
  UpdateControls;
end;

procedure TnbCodeEditorFindBar.FindKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: Char; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    if ssShift in Shift then
      DoFindPrevious(Sender)
    else
      DoFindNext(Sender);
    Key := 0;
  end
  else if Key = vkEscape then
  begin
    Close;
    Key := 0;
  end;
end;

procedure TnbCodeEditorFindBar.DoFindNext(Sender: TObject);
begin
  if (FEditor = nil) or (SearchText = '') then
    Exit;
  if FEditor.FindNext(SearchText, Options) then
    StatusLabel.Text := ''
  else
    StatusLabel.Text := 'No matches';
  UpdateControls;
end;

procedure TnbCodeEditorFindBar.DoFindPrevious(Sender: TObject);
begin
  if (FEditor = nil) or (SearchText = '') then
    Exit;
  if FEditor.FindPrevious(SearchText, Options) then
    StatusLabel.Text := ''
  else
    StatusLabel.Text := 'No matches';
  UpdateControls;
end;

procedure TnbCodeEditorFindBar.DoReplace(Sender: TObject);
begin
  if FEditor = nil then
    Exit;
  if FEditor.ReplaceCurrent(SearchText, ReplaceEdit.Text, Options) then
    StatusLabel.Text := ''
  else
    StatusLabel.Text := 'No matches';
  UpdateControls;
end;

procedure TnbCodeEditorFindBar.DoReplaceAll(Sender: TObject);
var
  Count: Integer;
begin
  if FEditor = nil then
    Exit;
  Count := FEditor.ReplaceAll(SearchText, ReplaceEdit.Text, Options);
  if Count = 0 then
    StatusLabel.Text := 'No matches'
  else
    StatusLabel.Text := Count.ToString + ' replaced';
  UpdateControls;
end;

procedure TnbCodeEditorFindBar.DoClose(Sender: TObject);
begin
  Close;
end;

end.

