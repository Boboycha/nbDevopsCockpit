unit nbFilePane;

(*
  TnbFilePane — одна сторона двухпанельного файлового менеджера: строка
  пути, тулбар (вверх / обновить / новая папка / переименовать / удалить /
  передача) и список файлов. Источник файлов абстрагирован интерфейсом
  InbFileSource — одна и та же панель работает и с локальной ФС
  (TnbLocalFileSource), и с удалённой по SFTP (TnbSFTPFileSource).

  ListDir трактуется как асинхронный: результат приходит через OnListing.
  Локальный источник эмитит его сразу (синхронно), SFTP — из фонового
  потока TnbSFTPClient. Панель одинаково обрабатывает оба случая.

  Палитра задаётся снаружи через ApplyColors — компонент не зависит от
  тем nbFleet и может использоваться в любом приложении.
*)

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes,
  System.Generics.Collections, System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Layouts, FMX.StdCtrls,
  FMX.Edit, FMX.ListBox, FMX.Objects,
  nbSFTPClient;

type
  (* Единая запись о файле/папке для локального и удалённого источника. *)
  TnbFileEntry = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    Modified: TDateTime;
  end;
  TnbFileEntryArray = array of TnbFileEntry;

  TnbFileListingEvent = procedure(Sender: TObject; const APath: string;
    const AEntries: TnbFileEntryArray) of object;
  TnbFileErrorEvent = procedure(Sender: TObject; const AMsg: string) of object;

  (* Абстракция источника файлов. ListDir асинхронный — результат через
     OnListing. OnChanged — после mkdir/rename/delete (панель перечитывает). *)
  InbFileSource = interface
    ['{6F1B6A20-2C44-4E2C-9E51-1B8D7F2A9C01}']
    procedure ListDir(const APath: string);
    function  ParentDir(const APath: string): string;
    function  Combine(const ADir, AName: string): string;
    procedure MakeDir(const APath: string);
    procedure Rename(const AOldPath, ANewPath: string);
    procedure Delete(const APath: string; AIsDir: Boolean);

    function  GetOnListing: TnbFileListingEvent;
    procedure SetOnListing(const AValue: TnbFileListingEvent);
    function  GetOnError: TnbFileErrorEvent;
    procedure SetOnError(const AValue: TnbFileErrorEvent);
    function  GetOnChanged: TNotifyEvent;
    procedure SetOnChanged(const AValue: TNotifyEvent);

    property OnListing: TnbFileListingEvent read GetOnListing write SetOnListing;
    property OnError: TnbFileErrorEvent read GetOnError write SetOnError;
    property OnChanged: TNotifyEvent read GetOnChanged write SetOnChanged;
  end;

  (* Базовая реализация хранения событий — общая для local/remote. *)
  TnbFileSourceBase = class(TInterfacedObject, InbFileSource)
  protected
    FOnListing: TnbFileListingEvent;
    FOnError: TnbFileErrorEvent;
    FOnChanged: TNotifyEvent;
    procedure DoListing(const APath: string; const AEntries: TnbFileEntryArray);
    procedure DoError(const AMsg: string);
    procedure DoChanged;
  public
    procedure ListDir(const APath: string); virtual; abstract;
    function  ParentDir(const APath: string): string; virtual; abstract;
    function  Combine(const ADir, AName: string): string; virtual; abstract;
    procedure MakeDir(const APath: string); virtual; abstract;
    procedure Rename(const AOldPath, ANewPath: string); virtual; abstract;
    procedure Delete(const APath: string; AIsDir: Boolean); virtual; abstract;

    function  GetOnListing: TnbFileListingEvent;
    procedure SetOnListing(const AValue: TnbFileListingEvent);
    function  GetOnError: TnbFileErrorEvent;
    procedure SetOnError(const AValue: TnbFileErrorEvent);
    function  GetOnChanged: TNotifyEvent;
    procedure SetOnChanged(const AValue: TNotifyEvent);
  end;

  (* Локальная ФС через System.IOUtils — синхронная. *)
  TnbLocalFileSource = class(TnbFileSourceBase)
  public
    procedure ListDir(const APath: string); override;
    function  ParentDir(const APath: string): string; override;
    function  Combine(const ADir, AName: string): string; override;
    procedure MakeDir(const APath: string); override;
    procedure Rename(const AOldPath, ANewPath: string); override;
    procedure Delete(const APath: string; AIsDir: Boolean); override;
  end;

  (* Удалённая ФС поверх TnbSFTPClient. Источник НЕ владеет клиентом —
     перехватывает только OnDirListing/OnOpDone/OnError. Передачу
     (Upload/Download/Progress) держит у себя владелец клиента. *)
  TnbSFTPFileSource = class(TnbFileSourceBase)
  private
    FClient: TnbSFTPClient;
    FPendingPath: string;
    procedure HandleDirListing(Sender: TObject; const APath: string;
      const AEntries: TSFTPEntryArray);
    procedure HandleOpDone(Sender: TObject);
    procedure HandleError(Sender: TObject; const AMsg: string);
  public
    constructor Create(AClient: TnbSFTPClient);
    procedure ListDir(const APath: string); override;
    function  ParentDir(const APath: string): string; override;
    function  Combine(const ADir, AName: string): string; override;
    procedure MakeDir(const APath: string); override;
    procedure Rename(const AOldPath, ANewPath: string); override;
    procedure Delete(const APath: string; AIsDir: Boolean); override;
  end;

  (* Компактная плоская glyph-кнопка тулбара (без зависимости от nbFleet). *)
  TnbToolButton = class(TRectangle)
  private
    FGlyph: TText;
    procedure SetGlyphText(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetGlyphColor(AColor: TAlphaColor);
    property Glyph: string write SetGlyphText;
  end;

  TnbFilePane = class(TLayout)
  private
    FSource: InbFileSource;
    FPath: string;
    FEntries: TnbFileEntryArray;
    FToolBar: TLayout;
    FPathEdit: TEdit;
    FList: TListBox;
    FButtons: TList<TnbToolButton>;
    FTransferButton: TnbToolButton;
    FColBg, FColSurface, FColBorder, FColText: TAlphaColor;
    FOnTransfer: TNotifyEvent;
    FOnActivated: TNotifyEvent;
    FOnError: TnbFileErrorEvent;

    function AddButton(const AGlyph: string; AOnClick: TNotifyEvent;
      const AHint: string): TnbToolButton;
    procedure BuildUi;
    procedure PaintStyleTree(AObject: TFmxObject);
    procedure HandleControlApplyStyle(Sender: TObject);
    procedure FillList;
    procedure HandleListing(Sender: TObject; const APath: string;
      const AEntries: TnbFileEntryArray);
    procedure HandleSourceError(Sender: TObject; const AMsg: string);
    procedure HandleChanged(Sender: TObject);
    procedure HandleListDblClick(Sender: TObject);
    procedure HandleListMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HandleUp(Sender: TObject);
    procedure HandleRefresh(Sender: TObject);
    procedure HandleMkdir(Sender: TObject);
    procedure HandleRename(Sender: TObject);
    procedure HandleDelete(Sender: TObject);
    procedure HandleTransfer(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure SetSource(const ASource: InbFileSource);
    procedure Navigate(const APath: string);
    procedure Refresh;
    function  SelectedEntry(out AEntry: TnbFileEntry): Boolean;
    function  CurrentPath: string;
    procedure ApplyColors(ABg, ASurface, ABorder, AText: TAlphaColor);

    (* Glyph кнопки передачи; пусто — кнопка скрыта. Клик → OnTransfer. *)
    procedure SetTransferButton(const AGlyph, AHint: string);
    (* Добавить произвольную кнопку в тулбар (например «отправить на другой
       сервер»). Возвращает кнопку для дальнейшей настройки. *)
    function AddActionButton(const AGlyph, AHint: string;
      AOnClick: TNotifyEvent): TnbToolButton;

    property OnTransfer: TNotifyEvent read FOnTransfer write FOnTransfer;
    property OnActivated: TNotifyEvent read FOnActivated write FOnActivated;
    property OnError: TnbFileErrorEvent read FOnError write FOnError;
  end;

implementation

uses
  System.Math, FMX.Dialogs;

function FormatSize(ASize: Int64): string;
begin
  if ASize < 1024 then
    Result := ASize.ToString + ' Б'
  else if ASize < 1024 * 1024 then
    Result := Format('%.1f КБ', [ASize / 1024])
  else
    Result := Format('%.1f МБ', [ASize / 1024 / 1024]);
end;

{ TnbFileSourceBase }

procedure TnbFileSourceBase.DoListing(const APath: string;
  const AEntries: TnbFileEntryArray);
begin
  if Assigned(FOnListing) then
    FOnListing(Self, APath, AEntries);
end;

procedure TnbFileSourceBase.DoError(const AMsg: string);
begin
  if Assigned(FOnError) then
    FOnError(Self, AMsg);
end;

procedure TnbFileSourceBase.DoChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TnbFileSourceBase.GetOnListing: TnbFileListingEvent;
begin
  Result := FOnListing;
end;

procedure TnbFileSourceBase.SetOnListing(const AValue: TnbFileListingEvent);
begin
  FOnListing := AValue;
end;

function TnbFileSourceBase.GetOnError: TnbFileErrorEvent;
begin
  Result := FOnError;
end;

procedure TnbFileSourceBase.SetOnError(const AValue: TnbFileErrorEvent);
begin
  FOnError := AValue;
end;

function TnbFileSourceBase.GetOnChanged: TNotifyEvent;
begin
  Result := FOnChanged;
end;

procedure TnbFileSourceBase.SetOnChanged(const AValue: TNotifyEvent);
begin
  FOnChanged := AValue;
end;

{ TnbLocalFileSource }

procedure TnbLocalFileSource.ListDir(const APath: string);
var
  Dirs, Files: TStringDynArray;
  Entries: TnbFileEntryArray;
  I, N: Integer;
begin
  try
    Dirs := TDirectory.GetDirectories(APath);
    Files := TDirectory.GetFiles(APath);
  except
    on E: Exception do
    begin
      DoError(E.Message);
      Exit;
    end;
  end;

  (* TPath квалифицируем полностью: FMX.Objects тоже экспортирует TPath
     (графический контрол) и перекрывает System.IOUtils.TPath. *)
  SetLength(Entries, Length(Dirs) + Length(Files));
  N := 0;
  for I := 0 to High(Dirs) do
  begin
    Entries[N].Name := System.IOUtils.TPath.GetFileName(Dirs[I]);
    Entries[N].IsDir := True;
    Entries[N].Size := 0;
    Entries[N].Modified := 0;
    Inc(N);
  end;
  for I := 0 to High(Files) do
  begin
    Entries[N].Name := System.IOUtils.TPath.GetFileName(Files[I]);
    Entries[N].IsDir := False;
    try
      Entries[N].Size := TFile.GetSize(Files[I]);
    except
      Entries[N].Size := 0;
    end;
    Entries[N].Modified := 0;
    Inc(N);
  end;

  DoListing(APath, Entries);
end;

function TnbLocalFileSource.ParentDir(const APath: string): string;
begin
  Result := TDirectory.GetParent(ExcludeTrailingPathDelimiter(APath));
  if Result = '' then
    Result := APath;
end;

function TnbLocalFileSource.Combine(const ADir, AName: string): string;
begin
  Result := System.IOUtils.TPath.Combine(ADir, AName);
end;

procedure TnbLocalFileSource.MakeDir(const APath: string);
begin
  try
    TDirectory.CreateDirectory(APath);
    DoChanged;
  except
    on E: Exception do DoError(E.Message);
  end;
end;

procedure TnbLocalFileSource.Rename(const AOldPath, ANewPath: string);
begin
  try
    if TDirectory.Exists(AOldPath) then
      TDirectory.Move(AOldPath, ANewPath)
    else
      TFile.Move(AOldPath, ANewPath);
    DoChanged;
  except
    on E: Exception do DoError(E.Message);
  end;
end;

procedure TnbLocalFileSource.Delete(const APath: string; AIsDir: Boolean);
begin
  try
    if AIsDir then
      TDirectory.Delete(APath, True)
    else
      TFile.Delete(APath);
    DoChanged;
  except
    on E: Exception do DoError(E.Message);
  end;
end;

{ TnbSFTPFileSource }

constructor TnbSFTPFileSource.Create(AClient: TnbSFTPClient);
begin
  inherited Create;
  FClient := AClient;
  FClient.OnDirListing := HandleDirListing;
  FClient.OnOpDone := HandleOpDone;
  FClient.OnError := HandleError;
end;

procedure TnbSFTPFileSource.HandleDirListing(Sender: TObject;
  const APath: string; const AEntries: TSFTPEntryArray);
var
  Entries: TnbFileEntryArray;
  I: Integer;
begin
  SetLength(Entries, Length(AEntries));
  for I := 0 to High(AEntries) do
  begin
    Entries[I].Name := AEntries[I].Name;
    Entries[I].IsDir := AEntries[I].IsDir;
    Entries[I].Size := AEntries[I].Size;
    Entries[I].Modified := AEntries[I].Modified;
  end;
  DoListing(APath, Entries);
end;

procedure TnbSFTPFileSource.HandleOpDone(Sender: TObject);
begin
  DoChanged;
end;

procedure TnbSFTPFileSource.HandleError(Sender: TObject; const AMsg: string);
begin
  DoError(AMsg);
end;

procedure TnbSFTPFileSource.ListDir(const APath: string);
begin
  FPendingPath := APath;
  FClient.ListDir(APath);
end;

function TnbSFTPFileSource.ParentDir(const APath: string): string;
var
  P: Integer;
  S: string;
begin
  S := APath;
  if (Length(S) > 1) and (S[High(S)] = '/') then
    SetLength(S, Length(S) - 1);
  P := S.LastDelimiter('/');
  if P <= 0 then
    Result := '/'
  else
    Result := Copy(S, 1, P);  (* включая '/' *)
  if Result = '' then
    Result := '/';
end;

function TnbSFTPFileSource.Combine(const ADir, AName: string): string;
begin
  if (ADir = '') or (ADir = '/') then
    Result := '/' + AName
  else if ADir[High(ADir)] = '/' then
    Result := ADir + AName
  else
    Result := ADir + '/' + AName;
end;

procedure TnbSFTPFileSource.MakeDir(const APath: string);
begin
  FClient.MakeDir(APath);
end;

procedure TnbSFTPFileSource.Rename(const AOldPath, ANewPath: string);
begin
  FClient.Rename(AOldPath, ANewPath);
end;

procedure TnbSFTPFileSource.Delete(const APath: string; AIsDir: Boolean);
begin
  if AIsDir then
    FClient.RemoveDir(APath)
  else
    FClient.Delete(APath);
end;

{ TnbToolButton }

constructor TnbToolButton.Create(AOwner: TComponent);
begin
  inherited;
  Align := TAlignLayout.Left;
  Width := 28;
  Margins.Rect := RectF(0, 2, 4, 2);
  Fill.Kind := TBrushKind.None;
  Stroke.Kind := TBrushKind.None;
  XRadius := 3;
  YRadius := 3;
  HitTest := True;

  FGlyph := TText.Create(Self);
  FGlyph.Parent := Self;
  FGlyph.Align := TAlignLayout.Client;
  FGlyph.TextSettings.HorzAlign := TTextAlign.Center;
  FGlyph.TextSettings.VertAlign := TTextAlign.Center;
  FGlyph.TextSettings.Font.Size := 12;
  FGlyph.HitTest := False;
end;

procedure TnbToolButton.SetGlyphText(const AValue: string);
begin
  if FGlyph <> nil then
    FGlyph.Text := AValue;
end;

procedure TnbToolButton.SetGlyphColor(AColor: TAlphaColor);
begin
  if FGlyph <> nil then
    FGlyph.TextSettings.FontColor := AColor;
end;

{ TnbFilePane }

constructor TnbFilePane.Create(AOwner: TComponent);
begin
  inherited;
  FButtons := TList<TnbToolButton>.Create;
  FColBg      := TAlphaColor($FF141820);
  FColSurface := TAlphaColor($FF1C2330);
  FColBorder  := TAlphaColor($FF344056);
  FColText    := TAlphaColor($FFCCD4DE);
  BuildUi;
end;

destructor TnbFilePane.Destroy;
begin
  FButtons.Free;
  inherited;
end;

function TnbFilePane.AddButton(const AGlyph: string; AOnClick: TNotifyEvent;
  const AHint: string): TnbToolButton;
begin
  Result := TnbToolButton.Create(Self);
  Result.Parent := FToolBar;
  Result.Glyph := AGlyph;
  Result.SetGlyphColor(FColText);
  Result.OnClick := AOnClick;
  if AHint <> '' then
  begin
    Result.Hint := AHint;
    Result.ShowHint := True;
  end;
  FButtons.Add(Result);
end;

procedure TnbFilePane.BuildUi;
begin
  FToolBar := TLayout.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Align := TAlignLayout.Top;
  FToolBar.Height := 26;
  FToolBar.Margins.Rect := RectF(4, 2, 4, 0);

  AddButton(#$2191, HandleUp,      'Вверх');
  AddButton('R',    HandleRefresh, 'Обновить');
  AddButton('+',    HandleMkdir,   'Новая папка');
  AddButton('N',    HandleRename,  'Переименовать');
  AddButton('X',    HandleDelete,  'Удалить');

  FPathEdit := TEdit.Create(Self);
  FPathEdit.Parent := Self;
  FPathEdit.Align := TAlignLayout.Top;
  FPathEdit.Position.Y := 100;
  FPathEdit.Height := 28;
  FPathEdit.Margins.Rect := RectF(4, 2, 4, 2);

  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := TAlignLayout.Client;
  FList.Margins.Rect := RectF(4, 0, 4, 4);
  FList.OnDblClick := HandleListDblClick;
  FList.OnMouseDown := HandleListMouseDown;
  FList.OnApplyStyleLookup := HandleControlApplyStyle;
  FPathEdit.OnApplyStyleLookup := HandleControlApplyStyle;
end;

procedure TnbFilePane.PaintStyleTree(AObject: TFmxObject);
var
  I: Integer;
begin
  if AObject = nil then Exit;
  if AObject is TnbToolButton then Exit;  (* glyph-кнопки красятся отдельно *)

  if AObject is TShape then
  begin
    TShape(AObject).Fill.Kind := TBrushKind.Solid;
    TShape(AObject).Fill.Color := FColSurface;
    TShape(AObject).Stroke.Kind := TBrushKind.Solid;
    TShape(AObject).Stroke.Color := FColBorder;
  end
  else if AObject is TText then
    TText(AObject).TextSettings.FontColor := FColText
  else if AObject is TTextControl then
  begin
    TTextControl(AObject).StyledSettings :=
      TTextControl(AObject).StyledSettings - [TStyledSetting.FontColor];
    TTextControl(AObject).TextSettings.FontColor := FColText;
  end;

  for I := 0 to AObject.ChildrenCount - 1 do
    PaintStyleTree(AObject.Children[I]);
end;

procedure TnbFilePane.HandleControlApplyStyle(Sender: TObject);
begin
  if Sender is TFmxObject then
    PaintStyleTree(TFmxObject(Sender));
end;

procedure TnbFilePane.SetSource(const ASource: InbFileSource);
begin
  FSource := ASource;
  if FSource <> nil then
  begin
    FSource.OnListing := HandleListing;
    FSource.OnError := HandleSourceError;
    FSource.OnChanged := HandleChanged;
  end;
end;

procedure TnbFilePane.Navigate(const APath: string);
begin
  if FSource = nil then Exit;
  FSource.ListDir(APath);
end;

procedure TnbFilePane.Refresh;
begin
  if FSource <> nil then
    FSource.ListDir(FPath);
end;

procedure TnbFilePane.HandleListing(Sender: TObject; const APath: string;
  const AEntries: TnbFileEntryArray);
begin
  FPath := APath;
  FPathEdit.Text := APath;
  FEntries := AEntries;
  FillList;
end;

procedure TnbFilePane.HandleSourceError(Sender: TObject; const AMsg: string);
begin
  if Assigned(FOnError) then
    FOnError(Self, AMsg);
end;

procedure TnbFilePane.HandleChanged(Sender: TObject);
begin
  Refresh;
end;

procedure TnbFilePane.FillList;
var
  I: Integer;
  Item: TListBoxItem;
  Caption: string;
begin
  FList.BeginUpdate;
  try
    FList.Clear;
    for I := 0 to High(FEntries) do
    begin
      Item := TListBoxItem.Create(FList);
      Item.Parent := FList;
      if FEntries[I].IsDir then
        Caption := '[D] ' + FEntries[I].Name
      else
        Caption := FEntries[I].Name + '   ' + FormatSize(FEntries[I].Size);
      Item.Text := Caption;
      Item.Tag := I;
    end;
  finally
    FList.EndUpdate;
  end;
end;

function TnbFilePane.SelectedEntry(out AEntry: TnbFileEntry): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if FList.ItemIndex < 0 then Exit;
  Idx := FList.ListItems[FList.ItemIndex].Tag;
  if (Idx < 0) or (Idx > High(FEntries)) then Exit;
  AEntry := FEntries[Idx];
  Result := True;
end;

function TnbFilePane.CurrentPath: string;
begin
  Result := FPath;
end;

procedure TnbFilePane.HandleListDblClick(Sender: TObject);
var
  Entry: TnbFileEntry;
begin
  if not SelectedEntry(Entry) then Exit;
  if Entry.IsDir and (FSource <> nil) then
    Navigate(FSource.Combine(FPath, Entry.Name));
end;

procedure TnbFilePane.HandleListMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Assigned(FOnActivated) then
    FOnActivated(Self);
end;

procedure TnbFilePane.HandleUp(Sender: TObject);
begin
  if FSource <> nil then
    Navigate(FSource.ParentDir(FPath));
end;

procedure TnbFilePane.HandleRefresh(Sender: TObject);
begin
  Refresh;
end;

procedure TnbFilePane.HandleMkdir(Sender: TObject);
var
  Values: array of string;
begin
  if FSource = nil then Exit;
  SetLength(Values, 1);
  Values[0] := '';
  if InputQuery('Новая папка', ['Имя'], Values) and (Trim(Values[0]) <> '') then
    FSource.MakeDir(FSource.Combine(FPath, Trim(Values[0])));
end;

procedure TnbFilePane.HandleRename(Sender: TObject);
var
  Entry: TnbFileEntry;
  Values: array of string;
begin
  if (FSource = nil) or (not SelectedEntry(Entry)) then Exit;
  SetLength(Values, 1);
  Values[0] := Entry.Name;
  if InputQuery('Переименовать', ['Новое имя'], Values)
    and (Trim(Values[0]) <> '') and (Trim(Values[0]) <> Entry.Name) then
    FSource.Rename(FSource.Combine(FPath, Entry.Name),
                   FSource.Combine(FPath, Trim(Values[0])));
end;

procedure TnbFilePane.HandleDelete(Sender: TObject);
var
  Entry: TnbFileEntry;
begin
  if (FSource = nil) or (not SelectedEntry(Entry)) then Exit;
  if MessageDlg(Format('Удалить "%s"?', [Entry.Name]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrYes then
    FSource.Delete(FSource.Combine(FPath, Entry.Name), Entry.IsDir);
end;

procedure TnbFilePane.HandleTransfer(Sender: TObject);
begin
  if Assigned(FOnTransfer) then
    FOnTransfer(Self);
end;

procedure TnbFilePane.SetTransferButton(const AGlyph, AHint: string);
begin
  if AGlyph = '' then
  begin
    if FTransferButton <> nil then
      FTransferButton.Visible := False;
    Exit;
  end;
  if FTransferButton = nil then
    FTransferButton := AddButton(AGlyph, HandleTransfer, AHint)
  else
  begin
    FTransferButton.Glyph := AGlyph;
    FTransferButton.Hint := AHint;
    FTransferButton.Visible := True;
  end;
end;

function TnbFilePane.AddActionButton(const AGlyph, AHint: string;
  AOnClick: TNotifyEvent): TnbToolButton;
begin
  Result := AddButton(AGlyph, AOnClick, AHint);
end;

procedure TnbFilePane.ApplyColors(ABg, ASurface, ABorder, AText: TAlphaColor);
var
  I: Integer;
begin
  FColBg := ABg;
  FColSurface := ASurface;
  FColBorder := ABorder;
  FColText := AText;
  for I := 0 to FButtons.Count - 1 do
    FButtons[I].SetGlyphColor(AText);
  (* Перекрасить уже разложенные стили списка и поля пути. *)
  if FList <> nil then PaintStyleTree(FList);
  if FPathEdit <> nil then PaintStyleTree(FPathEdit);
end;

end.
