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
  System.Generics.Collections, System.Generics.Defaults, System.IOUtils,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Layouts, FMX.StdCtrls,
  FMX.Objects, FMX.Edit, FMX.ListBox,
  nbSFTPClient;

type
  TnbFilePane = class;

  (* Единая запись о файле/папке для локального и удалённого источника. *)
  TnbFileEntry = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    Modified: TDateTime;
    Permissions: Cardinal;
  end;
  TnbFileEntryArray = array of TnbFileEntry;

  TnbFileListingEvent = procedure(Sender: TObject; const APath: string;
    const AEntries: TnbFileEntryArray) of object;
  TnbFileErrorEvent = procedure(Sender: TObject; const AMsg: string) of object;
  TnbFilePaneDropEvent = procedure(Sender: TObject;
    ASourcePane: TnbFilePane) of object;

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

  (* Компактная FMX-кнопка тулбара: вид приходит из активного StyleBook. *)
  TnbToolButton = class(TSpeedButton)
  private
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
    FListHost: TRectangle;
    FHeader: TLayout;
    FList: TListBox;
    FSelectedIndex: Integer;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    FSelectionColor: TAlphaColor;
    FButtons: TList<TnbToolButton>;
    FTransferButton: TnbToolButton;
    FColBg, FColSurface, FColBorder, FColText: TAlphaColor;
    FOnTransfer: TNotifyEvent;
    FOnActivated: TNotifyEvent;
    FOnError: TnbFileErrorEvent;
    FOnFileDrop: TnbFilePaneDropEvent;
    FDragArmed: Boolean;
    FDragging: Boolean;
    FDragStartScreen: TPointF;
    class var FInstances: TList<TnbFilePane>;
    class var FDragSource: TnbFilePane;
    class var FDragTarget: TnbFilePane;

    class function PaneAtScreenPoint(const APoint: TPointF): TnbFilePane; static;
    class procedure ClearDropIndicator; static;
    class procedure SetDraggingCursor(AEnabled: Boolean); static;
    function AddButton(const AGlyph: string; AOnClick: TNotifyEvent;
      const AHint: string): TnbToolButton;
    procedure BuildUi;
    procedure SetDropIndicatorVisible(AVisible: Boolean);
    procedure SelectIndex(AIndex: Integer);
    procedure EnsureSelectedVisible;
    procedure UpdateScrollThumb;
    procedure FillList;
    procedure SortEntries;
    procedure UpdateHeaderCaptions;
    procedure HandleHeaderClick(Sender: TObject);
    procedure HandleListViewportChanged(Sender: TObject;
      const OldViewportPosition, NewViewportPosition: TPointF;
      const ContentSizeChanged: Boolean);
    procedure HandleListResize(Sender: TObject);
    procedure HandleListing(Sender: TObject; const APath: string;
      const AEntries: TnbFileEntryArray);
    procedure HandleSourceError(Sender: TObject; const AMsg: string);
    procedure HandleChanged(Sender: TObject);
    procedure HandleRowDblClick(Sender: TObject);
    procedure HandleRowMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HandleRowMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Single);
    procedure HandleRowMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HandleDragEnd(Sender: TObject);
    procedure HandleDragOver(Sender: TObject; const AData: TDragObject;
      const APoint: TPointF; var AOperation: TDragOperation);
    procedure HandleDragDrop(Sender: TObject; const AData: TDragObject;
      const APoint: TPointF);
    procedure SelectRowFromObject(AObject: TObject);
    procedure UpdateRowSelection;
    procedure HandleUp(Sender: TObject);
    procedure HandleRefresh(Sender: TObject);
    procedure HandleMkdir(Sender: TObject);
    procedure HandleRename(Sender: TObject);
    procedure HandleDelete(Sender: TObject);
    procedure HandleTransfer(Sender: TObject);
  protected
    procedure KeyDown(var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure SetSource(const ASource: InbFileSource);
    procedure Navigate(const APath: string);
    procedure Refresh;
    function  SelectedEntry(out AEntry: TnbFileEntry): Boolean;
    function  EntryExists(const AName: string; out AIsDir: Boolean): Boolean;
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
    property OnFileDrop: TnbFilePaneDropEvent
      read FOnFileDrop write FOnFileDrop;
  end;

implementation

uses
  System.Math, System.StrUtils, FMX.Dialogs, FMX.Forms;

const
  FILE_ICON_FONT       = 'Segoe MDL2 Assets';
  FILE_ICON_UP         = #$E74A;
  FILE_ICON_REFRESH    = #$E72C;
  FILE_ICON_NEW_FOLDER = #$E8F4;
  FILE_ICON_RENAME     = #$E8AC;
  FILE_ICON_DELETE     = #$E74D;
  FILE_ICON_UPLOAD     = #$E898;
  FILE_ICON_DOWNLOAD   = #$E896;
  FILE_ICON_TRANSFER   = #$E8AB;
  FILE_ICON_FOLDER     = #$E8B7;
  FILE_ICON_DOCUMENT   = #$E8A5;

  FILE_ROW_HEIGHT      = 44;
  FILE_HEADER_HEIGHT   = 36;
  FILE_COL_DATE_WIDTH  = 150;
  FILE_COL_SIZE_WIDTH  = 78;
  FILE_COL_KIND_WIDTH  = 92;
  FILE_MUTED_TEXT      = TAlphaColor($FF8B98AA);
  FILE_ICON_BLUE       = TAlphaColor($FF6EC8F2);
  FILE_ROW_LINE        = TAlphaColor($222F3A4A);

  FILE_SORT_NAME       = 0;
  FILE_SORT_DATE       = 1;
  FILE_SORT_SIZE       = 2;
  FILE_SORT_KIND       = 3;

type
  TControlAccess = class(TControl);

function FileToolIconFor(const AGlyph, AHint: string): string;
begin
  if ContainsText(AHint, 'вверх') or (AGlyph = #$2191) then
    Exit(FILE_ICON_UP);
  if ContainsText(AHint, 'обнов') or SameText(AGlyph, 'R') then
    Exit(FILE_ICON_REFRESH);
  if ContainsText(AHint, 'новая папка') or (AGlyph = '+') then
    Exit(FILE_ICON_NEW_FOLDER);
  if ContainsText(AHint, 'переимен') or SameText(AGlyph, 'N') then
    Exit(FILE_ICON_RENAME);
  if ContainsText(AHint, 'удал') or SameText(AGlyph, 'X') then
    Exit(FILE_ICON_DELETE);
  if ContainsText(AHint, 'загруз') then
    Exit(FILE_ICON_UPLOAD);
  if ContainsText(AHint, 'скач') then
    Exit(FILE_ICON_DOWNLOAD);
  if (AGlyph = #$2192) or (AGlyph = #$2190) then
    Exit(FILE_ICON_TRANSFER);

  Result := AGlyph;
end;

function FormatSize(ASize: Int64): string;
begin
  if ASize < 1024 then
    Result := ASize.ToString + ' Б'
  else if ASize < 1024 * 1024 then
    Result := Format('%.1f КБ', [ASize / 1024])
  else
    Result := Format('%.1f МБ', [ASize / 1024 / 1024]);
end;

function FormatModified(ADate: TDateTime): string;
begin
  if ADate <= 0 then
    Exit('');
  Result := FormatDateTime('m/d/yyyy, h:nn AM/PM', ADate);
end;

function FormatPermissions(APermissions: Cardinal; AIsDir: Boolean): string;

  function PermissionChar(AMask: Cardinal; AChar: Char): Char;
  begin
    if (APermissions and AMask) <> 0 then
      Result := AChar
    else
      Result := '-';
  end;

begin
  if APermissions = 0 then
  begin
    if AIsDir then
      Exit('folder');
    Exit('file');
  end;

  if AIsDir then
    Result := 'd'
  else
    Result := '-';
  Result := Result
    + PermissionChar($100, 'r') + PermissionChar($080, 'w') + PermissionChar($040, 'x')
    + PermissionChar($020, 'r') + PermissionChar($010, 'w') + PermissionChar($008, 'x')
    + PermissionChar($004, 'r') + PermissionChar($002, 'w') + PermissionChar($001, 'x');
end;

function EntryKind(const AEntry: TnbFileEntry): string;
begin
  if AEntry.IsDir then
    Result := 'folder'
  else
    Result := 'file';
end;

function HeaderBaseCaption(AColumn: Integer): string;
begin
  case AColumn of
    FILE_SORT_DATE: Result := 'Date Modified';
    FILE_SORT_SIZE: Result := 'Size';
    FILE_SORT_KIND: Result := 'Kind';
  else
    Result := 'Name';
  end;
end;

function HeaderCaption(const AText: string; AColumn, ASortColumn: Integer;
  ASortDescending: Boolean): string;
begin
  Result := AText;
  if AColumn <> ASortColumn then
    Exit;
  if ASortDescending then
    Result := Result + ' v'
  else
    Result := Result + ' ^';
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
  if Trim(APath) = '' then
  begin
    Dirs := TDirectory.GetLogicalDrives;
    SetLength(Entries, Length(Dirs));
    for I := 0 to High(Dirs) do
    begin
      Entries[I].Name := IncludeTrailingPathDelimiter(Dirs[I]);
      Entries[I].IsDir := True;
      Entries[I].Size := 0;
      Entries[I].Modified := 0;
      Entries[I].Permissions := 0;
    end;
    DoListing('', Entries);
    Exit;
  end;

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
    Entries[N].Permissions := 0;
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
    Entries[N].Permissions := 0;
    Inc(N);
  end;

  DoListing(APath, Entries);
end;

function TnbLocalFileSource.ParentDir(const APath: string): string;
begin
  if Trim(APath) = '' then
    Exit('');

  if SameText(IncludeTrailingPathDelimiter(APath),
    IncludeTrailingPathDelimiter(ExtractFileDrive(APath))) then
    Exit('');

  Result := TDirectory.GetParent(ExcludeTrailingPathDelimiter(APath));
end;

function TnbLocalFileSource.Combine(const ADir, AName: string): string;
begin
  if Trim(ADir) = '' then
    Result := AName
  else
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
    Entries[I].Permissions := AEntries[I].Permissions;
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
  Width := 30;
  Margins.Rect := RectF(0, 2, 4, 2);
  StyledSettings := StyledSettings - [TStyledSetting.Family,
    TStyledSetting.Size, TStyledSetting.FontColor];
  TextSettings.Font.Family := FILE_ICON_FONT;
  TextSettings.Font.Size := 16;
  TextSettings.FontColor := TAlphaColor($FFCCD4DE);
  TextSettings.HorzAlign := TTextAlign.Center;
  TextSettings.VertAlign := TTextAlign.Center;
  TextSettings.Trimming := TTextTrimming.None;
end;

procedure TnbToolButton.SetGlyphText(const AValue: string);
begin
  Text := AValue;
end;

procedure TnbToolButton.SetGlyphColor(AColor: TAlphaColor);
begin
  StyledSettings := StyledSettings - [TStyledSetting.FontColor];
  TextSettings.FontColor := AColor;
end;

{ TnbFilePane }

constructor TnbFilePane.Create(AOwner: TComponent);
begin
  inherited;
  if FInstances = nil then
    FInstances := TList<TnbFilePane>.Create;
  FInstances.Add(Self);
  FButtons := TList<TnbToolButton>.Create;
  FSelectedIndex := -1;
  FSortColumn := FILE_SORT_NAME;
  FSortDescending := False;
  FColBg      := TAlphaColor($FF141820);
  FColSurface := TAlphaColor($FF1C2330);
  FColBorder  := TAlphaColor($FF344056);
  FColText    := TAlphaColor($FFCCD4DE);
  FSelectionColor := TAlphaColor($FF263246);
  CanFocus := True;
  TabStop := True;
  HitTest := True;
  BuildUi;
end;

destructor TnbFilePane.Destroy;
begin
  if FDragSource = Self then
    FDragSource := nil;
  if FDragTarget = Self then
    FDragTarget := nil;
  if FInstances <> nil then
  begin
    FInstances.Remove(Self);
    if FInstances.Count = 0 then
    begin
      FInstances.Free;
      FInstances := nil;
    end;
  end;
  FButtons.Free;
  inherited;
end;

class procedure TnbFilePane.ClearDropIndicator;
var
  I: Integer;
begin
  if FInstances <> nil then
    for I := 0 to FInstances.Count - 1 do
      if FInstances[I] <> nil then
        FInstances[I].SetDropIndicatorVisible(False);
  if FDragTarget <> nil then
  begin
    FDragTarget.SetDropIndicatorVisible(False);
    FDragTarget := nil;
  end;
  FDragTarget := nil;
end;

class procedure TnbFilePane.SetDraggingCursor(AEnabled: Boolean);
var
  I, J: Integer;
  Pane: TnbFilePane;
  C: TCursor;
  Item: TListBoxItem;
begin
  if AEnabled then
    C := crDrag
  else
    C := crDefault;

  if FInstances = nil then Exit;
  for I := 0 to FInstances.Count - 1 do
  begin
    Pane := FInstances[I];
    if Pane = nil then Continue;
    Pane.Cursor := C;
    if Pane.FListHost <> nil then
      Pane.FListHost.Cursor := C;
    if Pane.FList <> nil then
    begin
      Pane.FList.Cursor := C;
      for J := 0 to Pane.FList.Count - 1 do
      begin
        Item := Pane.FList.ListItems[J];
        if Item <> nil then
          Item.Cursor := C;
      end;
    end;
  end;
end;

class function TnbFilePane.PaneAtScreenPoint(const APoint: TPointF): TnbFilePane;
var
  I: Integer;
  Pane: TnbFilePane;
  TopLeft: TPointF;
  Bounds: TRectF;
begin
  Result := nil;
  if FInstances = nil then Exit;
  for I := FInstances.Count - 1 downto 0 do
  begin
    Pane := FInstances[I];
    if (Pane = nil) or (not Pane.Visible) then
      Continue;
    TopLeft := Pane.LocalToScreen(PointF(0, 0));
    Bounds := RectF(TopLeft.X, TopLeft.Y,
      TopLeft.X + Pane.Width, TopLeft.Y + Pane.Height);
    if Bounds.Contains(APoint) then
      Exit(Pane);
  end;
end;

function TnbFilePane.AddButton(const AGlyph: string; AOnClick: TNotifyEvent;
  const AHint: string): TnbToolButton;
begin
  Result := TnbToolButton.Create(Self);
  Result.Parent := FToolBar;
  Result.Glyph := FileToolIconFor(AGlyph, AHint);
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

  procedure AddHeaderCell(const AText: string; AAlign: TAlignLayout;
    AWidth: Single; AColumn: Integer);
  var
    Cell: TLayout;
    Caption: TLabel;
    Divider: TRectangle;
  begin
    Cell := TLayout.Create(FHeader);
    Cell.Parent := FHeader;
    Cell.Align := AAlign;
    if AWidth > 0 then
      Cell.Width := AWidth;
    Cell.Tag := AColumn;
    Cell.HitTest := True;
    Cell.OnClick := HandleHeaderClick;
    Cell.Cursor := crHandPoint;

    Caption := TLabel.Create(Cell);
    Caption.Parent := Cell;
    Caption.Align := TAlignLayout.Client;
    Caption.Margins.Rect := RectF(10, 0, 8, 0);
    Caption.HitTest := False;
    Caption.Tag := AColumn;
    Caption.Text := HeaderCaption(AText, AColumn, FSortColumn, FSortDescending);
    Caption.StyledSettings := Caption.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size, TStyledSetting.Style];
    Caption.TextSettings.FontColor := FColText;
    Caption.TextSettings.Font.Size := 12;
    Caption.TextSettings.Font.Style := [TFontStyle.fsBold];
    Caption.TextSettings.VertAlign := TTextAlign.Center;
    Caption.TextSettings.HorzAlign := TTextAlign.Leading;

    if AAlign <> TAlignLayout.Client then
    begin
      Divider := TRectangle.Create(Cell);
      Divider.Parent := Cell;
      Divider.Align := TAlignLayout.Left;
      Divider.Width := 1;
      Divider.HitTest := False;
      Divider.Fill.Color := FColBorder;
      Divider.Stroke.Kind := TBrushKind.None;
    end;
  end;

var
  HeaderLine: TRectangle;
begin
  FToolBar := TLayout.Create(Self);
  FToolBar.Parent := Self;
  FToolBar.Align := TAlignLayout.Top;
  FToolBar.Height := 36;
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
  FPathEdit.StyleLookup := 'editstyle';
  FPathEdit.ReadOnly := True;
  FPathEdit.TextSettings.HorzAlign := TTextAlign.Leading;
  FPathEdit.TextSettings.VertAlign := TTextAlign.Center;

  FListHost := TRectangle.Create(Self);
  FListHost.Parent := Self;
  FListHost.Align := TAlignLayout.Client;
  FListHost.Margins.Rect := RectF(4, 0, 4, 4);
  FListHost.ClipChildren := True;
  FListHost.HitTest := True;
  FListHost.Fill.Kind := TBrushKind.Solid;
  FListHost.Fill.Color := FColBg;
  FListHost.Stroke.Kind := TBrushKind.Solid;
  FListHost.Stroke.Color := FColBorder;
  FListHost.Stroke.Thickness := 1;
  FListHost.XRadius := 3;
  FListHost.YRadius := 3;
  FListHost.OnDragOver := HandleDragOver;
  FListHost.OnDragDrop := HandleDragDrop;

  FHeader := TLayout.Create(FListHost);
  FHeader.Parent := FListHost;
  FHeader.Align := TAlignLayout.Top;
  FHeader.Height := FILE_HEADER_HEIGHT;
  FHeader.HitTest := False;

  HeaderLine := TRectangle.Create(FHeader);
  HeaderLine.Parent := FHeader;
  HeaderLine.Align := TAlignLayout.Bottom;
  HeaderLine.Height := 1;
  HeaderLine.HitTest := False;
  HeaderLine.Fill.Color := FColBorder;
  HeaderLine.Stroke.Kind := TBrushKind.None;

  AddHeaderCell('Kind', TAlignLayout.Right, FILE_COL_KIND_WIDTH, FILE_SORT_KIND);
  AddHeaderCell('Size', TAlignLayout.Right, FILE_COL_SIZE_WIDTH, FILE_SORT_SIZE);
  AddHeaderCell('Date Modified', TAlignLayout.Right, FILE_COL_DATE_WIDTH, FILE_SORT_DATE);
  AddHeaderCell('Name', TAlignLayout.Client, 0, FILE_SORT_NAME);

  FList := TListBox.Create(FListHost);
  FList.Parent := FListHost;
  FList.Align := TAlignLayout.Client;
  FList.Margins.Rect := RectF(1, 0, 1, 1);
  FList.StyleLookup := 'listboxstyle';
  FList.ShowScrollBars := True;
  FList.ClipChildren := True;
  FList.HitTest := True;
  FList.ItemHeight := FILE_ROW_HEIGHT;
  FList.DefaultItemStyles.ItemStyle := 'listboxitemstyle';
  FList.OnDragOver := HandleDragOver;
  FList.OnDragDrop := HandleDragDrop;
  FList.OnViewportPositionChange := HandleListViewportChanged;
  FList.OnResize := HandleListResize;

end;

procedure TnbFilePane.SetDropIndicatorVisible(AVisible: Boolean);
begin
  if FListHost <> nil then
  begin
    FListHost.Stroke.Kind := TBrushKind.Solid;
    if AVisible then
    begin
      FListHost.Stroke.Color := TAlphaColor($FF7DDBFF);
      FListHost.Stroke.Thickness := 2;
    end
    else
    begin
      FListHost.Stroke.Color := FColBorder;
      FListHost.Stroke.Thickness := 1;
    end;
    FListHost.Repaint;
  end;
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
  FSelectedIndex := -1;
  SortEntries;
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

procedure TnbFilePane.UpdateScrollThumb;
begin
  (* Native TVertScrollBox scrollbars are styled by FMX. *)
end;

procedure TnbFilePane.HandleListViewportChanged(Sender: TObject;
  const OldViewportPosition, NewViewportPosition: TPointF;
  const ContentSizeChanged: Boolean);
begin
  UpdateScrollThumb;
end;

procedure TnbFilePane.HandleListResize(Sender: TObject);
begin
  UpdateScrollThumb;
end;

procedure TnbFilePane.SelectIndex(AIndex: Integer);
begin
  if Length(FEntries) = 0 then
  begin
    FSelectedIndex := -1;
    UpdateRowSelection;
    Exit;
  end;

  FSelectedIndex := EnsureRange(AIndex, 0, High(FEntries));
  UpdateRowSelection;
  EnsureSelectedVisible;
end;

procedure TnbFilePane.EnsureSelectedVisible;
begin
  if (FSelectedIndex < 0) or (FList = nil)
    or (FSelectedIndex >= FList.Count) then Exit;
  FList.ScrollToItem(FList.ListItems[FSelectedIndex]);
end;

procedure TnbFilePane.KeyDown(var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
var
  Entry: TnbFileEntry;
begin
  inherited;
  case Key of
    vkUp:
      begin
        if FSelectedIndex < 0 then
          SelectIndex(0)
        else
          SelectIndex(FSelectedIndex - 1);
        Key := 0;
      end;
    vkDown:
      begin
        if FSelectedIndex < 0 then
          SelectIndex(0)
        else
          SelectIndex(FSelectedIndex + 1);
        Key := 0;
      end;
    vkReturn:
      begin
        if SelectedEntry(Entry) and Entry.IsDir and (FSource <> nil) then
          Navigate(FSource.Combine(FPath, Entry.Name));
        Key := 0;
      end;
    vkBack:
      begin
        HandleUp(Self);
        Key := 0;
      end;
  end;
end;

procedure TnbFilePane.FillList;
var
  I: Integer;
  Item: TListBoxItem;
  Entry: TnbFileEntry;
  RowBg, Line: TRectangle;
  Row, NameCell, TextStack: TLayout;
  Icon, NameText, DetailText, DateText, SizeText, KindText: TLabel;
begin
  FList.BeginUpdate;
  try
    FList.Clear;
    for I := 0 to High(FEntries) do
    begin
      Entry := FEntries[I];

      Item := TListBoxItem.Create(FList);
      Item.Parent := FList;
      Item.Height := FILE_ROW_HEIGHT;
      Item.Tag := I;
      Item.Text := '';
      Item.StyleLookup := 'listboxitemstyle';
      Item.StyledSettings := Item.StyledSettings - [TStyledSetting.FontColor];
      Item.TextSettings.FontColor := FColText;
      Item.TextSettings.HorzAlign := TTextAlign.Leading;
      Item.TextSettings.VertAlign := TTextAlign.Center;
      Item.HitTest := True;
      Item.Selectable := True;
      Item.OnMouseDown := HandleRowMouseDown;
      Item.OnMouseMove := HandleRowMouseMove;
      Item.OnMouseUp := HandleRowMouseUp;
      Item.OnDblClick := HandleRowDblClick;
      Item.OnDragEnd := HandleDragEnd;
      Item.OnDragOver := HandleDragOver;
      Item.OnDragDrop := HandleDragDrop;
      Item.DragMode := TDragMode.dmManual;

      RowBg := TRectangle.Create(Item);
      RowBg.Parent := Item;
      RowBg.Align := TAlignLayout.Contents;
      RowBg.StyleName := 'file-row-bg';
      RowBg.HitTest := False;
      RowBg.Fill.Color := FColBg;
      RowBg.Stroke.Kind := TBrushKind.None;
      RowBg.SendToBack;

      Row := TLayout.Create(Item);
      Row.Parent := Item;
      Row.Align := TAlignLayout.Client;
      Row.Margins.Rect := RectF(0, 0, 0, 0);
      Row.HitTest := False;

      KindText := TLabel.Create(Row);
      KindText.Parent := Row;
      KindText.Align := TAlignLayout.Right;
      KindText.Width := FILE_COL_KIND_WIDTH;
      KindText.Margins.Rect := RectF(8, 0, 10, 0);
      KindText.HitTest := False;
      KindText.Text := EntryKind(Entry);
      KindText.StyledSettings := KindText.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size];
      KindText.TextSettings.FontColor := FILE_MUTED_TEXT;
      KindText.TextSettings.Font.Size := 12;
      KindText.TextSettings.VertAlign := TTextAlign.Center;
      KindText.TextSettings.HorzAlign := TTextAlign.Leading;

      SizeText := TLabel.Create(Row);
      SizeText.Parent := Row;
      SizeText.Align := TAlignLayout.Right;
      SizeText.Width := FILE_COL_SIZE_WIDTH;
      SizeText.Margins.Rect := RectF(8, 0, 8, 0);
      SizeText.HitTest := False;
      if Entry.IsDir then
        SizeText.Text := '--'
      else
        SizeText.Text := FormatSize(Entry.Size);
      SizeText.StyledSettings := SizeText.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size];
      SizeText.TextSettings.FontColor := FILE_MUTED_TEXT;
      SizeText.TextSettings.Font.Size := 12;
      SizeText.TextSettings.VertAlign := TTextAlign.Center;
      SizeText.TextSettings.HorzAlign := TTextAlign.Leading;

      DateText := TLabel.Create(Row);
      DateText.Parent := Row;
      DateText.Align := TAlignLayout.Right;
      DateText.Width := FILE_COL_DATE_WIDTH;
      DateText.Margins.Rect := RectF(8, 0, 8, 0);
      DateText.HitTest := False;
      DateText.Text := FormatModified(Entry.Modified);
      DateText.StyledSettings := DateText.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size];
      DateText.TextSettings.FontColor := FILE_MUTED_TEXT;
      DateText.TextSettings.Font.Size := 12;
      DateText.TextSettings.VertAlign := TTextAlign.Center;
      DateText.TextSettings.HorzAlign := TTextAlign.Leading;

      NameCell := TLayout.Create(Row);
      NameCell.Parent := Row;
      NameCell.Align := TAlignLayout.Client;
      NameCell.HitTest := False;

      Icon := TLabel.Create(NameCell);
      Icon.Parent := NameCell;
      Icon.Align := TAlignLayout.Left;
      Icon.Width := 34;
      Icon.Margins.Rect := RectF(8, 0, 0, 0);
      Icon.HitTest := False;
      if Entry.IsDir then
        Icon.Text := FILE_ICON_FOLDER
      else
        Icon.Text := FILE_ICON_DOCUMENT;
      Icon.StyledSettings := Icon.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Family, TStyledSetting.Size];
      Icon.TextSettings.Font.Family := FILE_ICON_FONT;
      Icon.TextSettings.Font.Size := 18;
      Icon.TextSettings.FontColor := FILE_ICON_BLUE;
      Icon.TextSettings.VertAlign := TTextAlign.Center;
      Icon.TextSettings.HorzAlign := TTextAlign.Center;

      TextStack := TLayout.Create(NameCell);
      TextStack.Parent := NameCell;
      TextStack.Align := TAlignLayout.Client;
      TextStack.Margins.Rect := RectF(0, 5, 8, 4);
      TextStack.HitTest := False;

      NameText := TLabel.Create(TextStack);
      NameText.Parent := TextStack;
      NameText.Align := TAlignLayout.Top;
      NameText.Height := 18;
      NameText.HitTest := False;
      NameText.Text := Entry.Name;
      NameText.StyledSettings := NameText.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size, TStyledSetting.Style];
      NameText.TextSettings.FontColor := FColText;
      NameText.TextSettings.Font.Size := 12;
      NameText.TextSettings.Font.Style := [TFontStyle.fsBold];
      NameText.TextSettings.VertAlign := TTextAlign.Center;
      NameText.TextSettings.HorzAlign := TTextAlign.Leading;

      DetailText := TLabel.Create(TextStack);
      DetailText.Parent := TextStack;
      DetailText.Align := TAlignLayout.Client;
      DetailText.HitTest := False;
      DetailText.Text := FormatPermissions(Entry.Permissions, Entry.IsDir);
      DetailText.StyledSettings := DetailText.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size];
      DetailText.TextSettings.FontColor := FILE_MUTED_TEXT;
      DetailText.TextSettings.Font.Size := 10;
      DetailText.TextSettings.VertAlign := TTextAlign.Leading;
      DetailText.TextSettings.HorzAlign := TTextAlign.Leading;

      Line := TRectangle.Create(Item);
      Line.Parent := Item;
      Line.Align := TAlignLayout.Bottom;
      Line.Height := 1;
      Line.HitTest := False;
      Line.Fill.Color := FILE_ROW_LINE;
      Line.Stroke.Kind := TBrushKind.None;
    end;
  finally
    FList.EndUpdate;
  end;
  UpdateScrollThumb;
end;

procedure TnbFilePane.SortEntries;
begin
  TArray.Sort<TnbFileEntry>(FEntries,
    TComparer<TnbFileEntry>.Construct(
      function(const L, R: TnbFileEntry): Integer
      begin
        if L.IsDir <> R.IsDir then
        begin
          if L.IsDir then
            Exit(-1);
          Exit(1);
        end;

        case FSortColumn of
          FILE_SORT_DATE:
            Result := CompareValue(L.Modified, R.Modified);
          FILE_SORT_SIZE:
            Result := CompareValue(L.Size, R.Size);
          FILE_SORT_KIND:
            Result := CompareText(EntryKind(L), EntryKind(R));
        else
          Result := CompareText(L.Name, R.Name);
        end;

        if FSortDescending then
          Result := -Result;
        if Result = 0 then
          Result := CompareText(L.Name, R.Name);
      end));
end;

procedure TnbFilePane.UpdateHeaderCaptions;
var
  I, J, Column: Integer;
  Cell, Child: TFmxObject;
begin
  if FHeader = nil then Exit;
  for I := 0 to FHeader.ChildrenCount - 1 do
  begin
    Cell := FHeader.Children[I];
    if not (Cell is TLayout) then
      Continue;
    Column := Cell.Tag;
    for J := 0 to Cell.ChildrenCount - 1 do
    begin
      Child := Cell.Children[J];
      if Child is TLabel then
        TLabel(Child).Text := HeaderCaption(HeaderBaseCaption(Column),
          Column, FSortColumn, FSortDescending);
    end;
  end;
end;

procedure TnbFilePane.HandleHeaderClick(Sender: TObject);
var
  Column, I: Integer;
  HadSelection: Boolean;
  SelectedName: string;
  SelectedIsDir: Boolean;
  Entry: TnbFileEntry;
begin
  if not (Sender is TFmxObject) then Exit;

  Column := TFmxObject(Sender).Tag;
  if Column = FSortColumn then
    FSortDescending := not FSortDescending
  else
  begin
    FSortColumn := Column;
    FSortDescending := False;
  end;

  HadSelection := SelectedEntry(Entry);
  SelectedName := '';
  SelectedIsDir := False;
  if HadSelection then
  begin
    SelectedName := Entry.Name;
    SelectedIsDir := Entry.IsDir;
  end;

  SortEntries;
  FSelectedIndex := -1;
  if HadSelection then
    for I := 0 to High(FEntries) do
      if (FEntries[I].IsDir = SelectedIsDir)
        and SameText(FEntries[I].Name, SelectedName) then
      begin
        FSelectedIndex := I;
        Break;
      end;

  UpdateHeaderCaptions;
  FillList;
  UpdateRowSelection;
  EnsureSelectedVisible;
end;

function TnbFilePane.SelectedEntry(out AEntry: TnbFileEntry): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  Idx := FSelectedIndex;
  if (Idx < 0) or (Idx > High(FEntries)) then Exit;
  AEntry := FEntries[Idx];
  Result := True;
end;

function TnbFilePane.EntryExists(const AName: string;
  out AIsDir: Boolean): Boolean;
var
  I: Integer;
begin
  Result := False;
  AIsDir := False;
  for I := 0 to High(FEntries) do
    if SameText(FEntries[I].Name, AName) then
    begin
      AIsDir := FEntries[I].IsDir;
      Exit(True);
    end;
end;

function TnbFilePane.CurrentPath: string;
begin
  Result := FPath;
end;

procedure TnbFilePane.HandleRowDblClick(Sender: TObject);
var
  Entry: TnbFileEntry;
begin
  SelectRowFromObject(Sender);
  if not SelectedEntry(Entry) then Exit;
  if Entry.IsDir and (FSource <> nil) then
    Navigate(FSource.Combine(FPath, Entry.Name));
end;

procedure TnbFilePane.HandleRowMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Entry: TnbFileEntry;
  Ctrl: TControl;
begin
  if CanFocus then
    SetFocus;
  FDragSource := nil;
  FDragArmed := False;
  FDragging := False;
  SelectRowFromObject(Sender);
  if (Button = TMouseButton.mbLeft) and SelectedEntry(Entry)
    and (not Entry.IsDir) then
  begin
    FDragSource := Self;
    FDragArmed := True;
    if Sender is TControl then
    begin
      Ctrl := TControl(Sender);
      FDragStartScreen := Ctrl.LocalToScreen(PointF(X, Y));
      TControlAccess(Ctrl).Capture;
    end;
  end;
  if Assigned(FOnActivated) then
    FOnActivated(Self);
end;

procedure TnbFilePane.HandleRowMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
var
  Ctrl: TControl;
  ScreenPt: TPointF;
  Target: TnbFilePane;
begin
  if (FDragSource <> Self) or (not FDragArmed) then Exit;
  if not (ssLeft in Shift) then Exit;
  if not (Sender is TControl) then Exit;

  Ctrl := TControl(Sender);
  ScreenPt := Ctrl.LocalToScreen(PointF(X, Y));
  if not FDragging then
    FDragging := (Abs(ScreenPt.X - FDragStartScreen.X) > 4)
      or (Abs(ScreenPt.Y - FDragStartScreen.Y) > 4);
  if FDragging then
  begin
    SetDraggingCursor(True);
    Target := PaneAtScreenPoint(ScreenPt);
    if Target = Self then
      Target := nil;
    if Target <> FDragTarget then
    begin
      ClearDropIndicator;
      FDragTarget := Target;
      if FDragTarget <> nil then
        FDragTarget.SetDropIndicatorVisible(True);
    end;
  end;
end;

procedure TnbFilePane.HandleRowMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Ctrl: TControl;
  ScreenPt: TPointF;
  Target: TnbFilePane;
begin
  if Button <> TMouseButton.mbLeft then Exit;
  if (FDragSource <> Self) or (not FDragArmed) then Exit;
  try
    if FDragging and (Sender is TControl) then
    begin
      Ctrl := TControl(Sender);
      ScreenPt := Ctrl.LocalToScreen(PointF(X, Y));
      Target := PaneAtScreenPoint(ScreenPt);
      if (Target <> nil) and (Target <> Self) and Assigned(Target.FOnFileDrop) then
      begin
        Target.SetDropIndicatorVisible(False);
        ClearDropIndicator;
        SetDraggingCursor(False);
        Application.ProcessMessages;
        Target.FOnFileDrop(Target, Self);
      end;
    end;
  finally
    ClearDropIndicator;
    SetDraggingCursor(False);
    FDragArmed := False;
    FDragging := False;
    FDragSource := nil;
  end;
end;

procedure TnbFilePane.HandleDragEnd(Sender: TObject);
begin
  ClearDropIndicator;
  SetDraggingCursor(False);
  FDragSource := nil;
  FDragArmed := False;
  FDragging := False;
end;

procedure TnbFilePane.HandleDragOver(Sender: TObject; const AData: TDragObject;
  const APoint: TPointF; var AOperation: TDragOperation);
begin
  if (FDragSource <> nil) and (FDragSource <> Self) then
    AOperation := TDragOperation.Copy
  else
    AOperation := TDragOperation.None;
end;

procedure TnbFilePane.HandleDragDrop(Sender: TObject; const AData: TDragObject;
  const APoint: TPointF);
var
  Source: TnbFilePane;
begin
  Source := FDragSource;
  FDragSource := nil;
  if (Source <> nil) and (Source <> Self) and Assigned(FOnFileDrop) then
    FOnFileDrop(Self, Source);
end;

procedure TnbFilePane.SelectRowFromObject(AObject: TObject);
var
  Obj: TFmxObject;
begin
  if AObject is TFmxObject then
  begin
    Obj := TFmxObject(AObject);
    FSelectedIndex := Obj.Tag;
    if (FList <> nil) and (FSelectedIndex >= 0) and (FSelectedIndex < FList.Count) then
      FList.ItemIndex := FSelectedIndex;
  end;
  UpdateRowSelection;
end;

procedure TnbFilePane.UpdateRowSelection;
var
  I, J: Integer;
  Item: TListBoxItem;
  Child: TFmxObject;
  RowBg: TRectangle;
begin
  if FList = nil then Exit;
  FList.ItemIndex := FSelectedIndex;
  for I := 0 to FList.Count - 1 do
  begin
    Item := FList.ListItems[I];
    Item.StyledSettings := Item.StyledSettings - [TStyledSetting.FontColor];
    Item.TextSettings.FontColor := FColText;
    Item.IsSelected := Item.Tag = FSelectedIndex;
    RowBg := nil;
    for J := 0 to Item.ChildrenCount - 1 do
    begin
      Child := Item.Children[J];
      if (Child is TRectangle) and SameText(Child.StyleName, 'file-row-bg') then
      begin
        RowBg := TRectangle(Child);
        Break;
      end;
    end;
    if RowBg <> nil then
    begin
      if Item.IsSelected then
        RowBg.Fill.Color := FSelectionColor
      else
        RowBg.Fill.Color := FColBg;
    end;
  end;
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
    FTransferButton.Glyph := FileToolIconFor(AGlyph, AHint);
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
  FSelectionColor := TAlphaColor($FF000000)
    or ((Round(((ASurface shr 16) and $FF) * 0.70 + ((AText shr 16) and $FF) * 0.30) and $FF) shl 16)
    or ((Round(((ASurface shr 8) and $FF) * 0.70 + ((AText shr 8) and $FF) * 0.30) and $FF) shl 8)
    or (Round((ASurface and $FF) * 0.70 + (AText and $FF) * 0.30) and $FF);
  for I := 0 to FButtons.Count - 1 do
    FButtons[I].SetGlyphColor(AText);
  if FPathEdit <> nil then
  begin
    FPathEdit.StyledSettings := FPathEdit.StyledSettings - [TStyledSetting.FontColor];
    FPathEdit.TextSettings.FontColor := AText;
    FPathEdit.ApplyStyleLookup;
  end;
  if FListHost <> nil then
  begin
    FListHost.Fill.Kind := TBrushKind.Solid;
    FListHost.Fill.Color := ABg;
    FListHost.Stroke.Kind := TBrushKind.Solid;
    FListHost.Stroke.Color := ABorder;
    FListHost.Stroke.Thickness := 1;
  end;
  FillList;
  UpdateRowSelection;
end;

end.
