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
  System.Generics.Collections, System.Generics.Defaults,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Layouts, FMX.StdCtrls,
  FMX.Objects, FMX.Edit,
  UniList.Control, UniList.Items, UniList.Columns, UniList.Types,
  nbFileSources, nbFilePane.Controls, nbVectorIcons;

type
  TnbFilePane = class;

  TnbFileListView = class(TUniListView)
  private
    FPane: TnbFilePane;
    FMouseShift: TShiftState;
  protected
    procedure DoItemClick(const AItemIndex: Integer); override;
    procedure DoItemDoubleClick(const AItemIndex: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single); override;
  end;

  TnbFileEntry = nbFileSources.TnbFileEntry;
  TnbFileEntryArray = nbFileSources.TnbFileEntryArray;
  TnbFileListingEvent = nbFileSources.TnbFileListingEvent;
  TnbFileErrorEvent = nbFileSources.TnbFileErrorEvent;
  InbFileSource = nbFileSources.InbFileSource;
  TnbFileSourceBase = nbFileSources.TnbFileSourceBase;
  TnbLocalFileSource = nbFileSources.TnbLocalFileSource;
  TnbSFTPFileSource = nbFileSources.TnbSFTPFileSource;
  TnbToolButton = nbFilePane.Controls.TnbToolButton;

  TnbFilePaneDropEvent = procedure(Sender: TObject;
    ASourcePane: TnbFilePane) of object;
  TnbFilePaneOpenFileEvent = procedure(Sender: TObject;
    const AFullPath: string; const AEntry: TnbFileEntry) of object;
  TnbFilePanePromptEvent = reference to function(const ATitle,
    ALabel: string; var AValue: string): Boolean;

  TnbFilePane = class(TLayout)
  private
    FSource: InbFileSource;
    FPath: string;
    FEntries: TnbFileEntryArray;
    FToolBar: TLayout;
    FBreadcrumbBg: TRectangle;
    FBreadcrumbBar: TFlowLayout;
    FBreadcrumbPaths: TArray<string>;
    FListHost: TRectangle;
    FHeader: TLayout;
    FList: TnbFileListView;
    FBusyOverlay: TLayout;
    FBusyShade: TRectangle;
    FBusyIndicator: TAniIndicator;
    FBusyLabel: TLabel;
    FDropOverlay: TRectangle;
    FBusy: Boolean;
    FSelectedIndex: Integer;
    FSelectedIndices: TList<Integer>;
    FSelectionAnchor: Integer;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    FSelectionColor: TAlphaColor;
    FButtons: TList<TnbToolButton>;
    FTransferButton: TnbToolButton;
    FToolbarLeadingInset: Single;
    FToolbarVisible: Boolean;
    FStyleLookupPrefix: string;
    FColumnNameCaption: string;
    FColumnSizeCaption: string;
    FColumnModifiedCaption: string;
    FColumnKindCaption: string;
    FFolderCaption: string;
    FFileCaption: string;
    FParentFolderCaption: string;
    FBusyText: string;
    FColBg, FColSurface, FColBorder, FColText, FColMuted,
      FColAccent: TAlphaColor;
    FOnTransfer: TNotifyEvent;
    FOnActivated: TNotifyEvent;
    FOnError: TnbFileErrorEvent;
    FOnFileDrop: TnbFilePaneDropEvent;
    FOnOpenFile: TnbFilePaneOpenFileEvent;
    FOnConfirmDelete: TFunc<string, Boolean>;
    FOnPrompt: TnbFilePanePromptEvent;
    FBtnCreateFile: TnbToolButton;
    FBtnMkdir:  TnbToolButton;
    FBtnRename: TnbToolButton;
    FBtnDelete: TnbToolButton;
    FLangNewFileHint:    string;
    FLangNewFolderHint:  string;
    FLangRenameHint:     string;
    FLangDeleteHint:     string;
    FLangNewFileTitle:   string;
    FLangNewFileLabel:   string;
    FLangNewFolderTitle: string;
    FLangNewFolderLabel: string;
    FLangRenameTitle:    string;
    FLangRenameLabel:    string;
    FLangDeleteSingle:   string;
    FLangDeleteMany:     string;
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
    function HeaderCaption(AColumn: Integer): string;
    function EntryDetailCaption(const AEntry: TnbFileEntry;
      ATag: Integer): string;
    procedure HandleHeaderClick(Sender: TObject);
    procedure HandleNativeHeaderClick(AColumn: Integer);
    procedure HandleListResize(Sender: TObject);
    procedure HandleListItemClick(AItemIndex: Integer; AShift: TShiftState);
    procedure HandleListItemDoubleClick(AItemIndex: Integer);
    procedure HandleListMouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    procedure HandleListMouseMove(Shift: TShiftState; X, Y: Single);
    procedure HandleListMouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Single);
    procedure HandleListing(Sender: TObject; const APath: string;
      const AEntries: TnbFileEntryArray);
    procedure HandleSourceError(Sender: TObject; const AMsg: string);
    procedure HandleChanged(Sender: TObject);

    procedure HandleDragOver(Sender: TObject; const AData: TDragObject;
      const APoint: TPointF; var AOperation: TDragOperation);
    procedure HandleDragDrop(Sender: TObject; const AData: TDragObject;
      const APoint: TPointF);
    procedure UpdateRowSelection;
    procedure HandleUp(Sender: TObject);
    procedure HandleRefresh(Sender: TObject);
    procedure HandleCreateFile(Sender: TObject);
    procedure HandleMkdir(Sender: TObject);
    procedure HandleRename(Sender: TObject);
    procedure HandleDelete(Sender: TObject);
    procedure HandleTransfer(Sender: TObject);
    procedure RebuildBreadcrumbs(const APath: string);
    procedure HandleBreadcrumbClick(Sender: TObject);
    class procedure SplitPathSegments(const APath: string;
      out ALabels, AFullPaths: TArray<string>); static;
    procedure SetBusy(AValue: Boolean);
    procedure SetBusyText(const AValue: string);
    function ScopedStyle(const ABaseStyle: string): string;
    procedure SetStyleLookupPrefix(const AValue: string);
    procedure SetToolbarLeadingInset(const AValue: Single);
    procedure SetToolbarVisible(AValue: Boolean);
    procedure ApplyStyleLookups;
  protected
    procedure KeyDown(var Key: Word; var KeyChar: WideChar;
      Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure SetSource(const ASource: InbFileSource);
    procedure Navigate(const APath: string);
    procedure Refresh;
    procedure ClearBusy;
    function  SelectedEntry(out AEntry: TnbFileEntry): Boolean;
    function  SelectedEntries: TnbFileEntryArray;
    function  EntryExists(const AName: string; out AIsDir: Boolean): Boolean;
    function  CurrentPath: string;
    procedure ApplyColors(ABg, ASurface, ABorder, AText: TAlphaColor;
      AMuted: TAlphaColor = 0; AAccent: TAlphaColor = 0);
    procedure LoadThemeFromFile(const AFileName: string);
    procedure SetListFontSize(AFontSize: Single);
    procedure SetCaptions(const AName, ASize, AModified, AKind, AFolder,
      AFile, AParentFolder: string);
    procedure CommandUp;
    procedure CommandRefresh;
    procedure CommandCreateFile;
    procedure CommandNewFolder;
    procedure CommandRename;
    procedure CommandDelete;
    procedure CommandTransfer;
    procedure SetActionStrings(
      const AHintNewFolder, AHintRename, AHintDelete: string;
      const ANewFolderTitle, ANewFolderLabel: string;
      const ARenameTitle, ARenameLabel: string;
      const ADeleteSingle, ADeleteMany: string);
    property BusyText: string read FBusyText write SetBusyText;

    (* Glyph кнопки передачи; пусто — кнопка скрыта. Клик → OnTransfer. *)
    procedure SetTransferButton(const AGlyph, AHint: string);
    (* Добавить произвольную кнопку в тулбар (например «отправить на другой
       сервер»). Возвращает кнопку для дальнейшей настройки. *)
    function AddActionButton(const AGlyph, AHint: string;
      AOnClick: TNotifyEvent): TnbToolButton;
    property StyleLookupPrefix: string read FStyleLookupPrefix
      write SetStyleLookupPrefix;

  published
    property ToolbarLeadingInset: Single read FToolbarLeadingInset
      write SetToolbarLeadingInset;
    property ToolbarVisible: Boolean read FToolbarVisible write SetToolbarVisible;
    property OnTransfer: TNotifyEvent read FOnTransfer write FOnTransfer;
    property OnActivated: TNotifyEvent read FOnActivated write FOnActivated;
    property OnError: TnbFileErrorEvent read FOnError write FOnError;
    property OnFileDrop: TnbFilePaneDropEvent
      read FOnFileDrop write FOnFileDrop;
    property OnOpenFile: TnbFilePaneOpenFileEvent
      read FOnOpenFile write FOnOpenFile;
    property OnConfirmDelete: TFunc<string, Boolean>
      read FOnConfirmDelete write FOnConfirmDelete;
    property OnPrompt: TnbFilePanePromptEvent read FOnPrompt write FOnPrompt;
  end;

implementation

uses
  System.Math, FMX.Forms;

const
  PARENT_ENTRY_TAG = -1;

type
  TControlAccess = class(TControl);

procedure MarkInternalControl(AObject: TFmxObject);
begin
  if AObject = nil then Exit;
  AObject.Stored := False;
  if AObject is TControl then
    TControl(AObject).Locked := True;
end;

{ TnbFileListView }

procedure TnbFileListView.DoItemClick(const AItemIndex: Integer);
begin
  inherited;
  if FPane <> nil then
    FPane.HandleListItemClick(AItemIndex, FMouseShift);
end;

procedure TnbFileListView.DoItemDoubleClick(const AItemIndex: Integer);
begin
  inherited;
  if FPane <> nil then
    FPane.HandleListItemDoubleClick(AItemIndex);
end;

procedure TnbFileListView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  ItemIndex: Integer;
begin
  FMouseShift := Shift;
  inherited;
  if (FPane <> nil) and (Button = TMouseButton.mbLeft)
    and not (ssCtrl in Shift) and not (ssShift in Shift) then
  begin
    if Y <= ListHeaderHeight then
      ItemIndex := -1
    else
      ItemIndex := Floor((Y - ListHeaderHeight + ScrollY) / ListRowHeight);
    if (ItemIndex >= 0) and (ItemIndex < Items.Count)
      and (ItemIndex <> SelectedIndex) then
      FPane.HandleListItemClick(ItemIndex, []);
  end;
  if FPane <> nil then
    FPane.HandleListMouseDown(Button, Shift, X, Y);
end;

procedure TnbFileListView.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if FPane <> nil then
    FPane.HandleListMouseMove(Shift, X, Y);
end;

procedure TnbFileListView.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Single);
var
  Column: Integer;
begin
  if (FPane <> nil) and (Button = TMouseButton.mbLeft)
    and (Y >= 0) and (Y <= ListHeaderHeight) then
  begin
    if X >= Width - FILE_COL_DATE_WIDTH then
      Column := FILE_SORT_DATE
    else if X >= Width - FILE_COL_DATE_WIDTH - FILE_COL_SIZE_WIDTH then
      Column := FILE_SORT_SIZE
    else
      Column := FILE_SORT_NAME;
    FPane.HandleNativeHeaderClick(Column);
  end;
  if FPane <> nil then
    FPane.HandleListMouseUp(Button, Shift, X, Y);
  inherited;
end;
{ TnbFilePane }

constructor TnbFilePane.Create(AOwner: TComponent);
begin
  inherited;
  if FInstances = nil then
    FInstances := TList<TnbFilePane>.Create;
  FInstances.Add(Self);
  FButtons := TList<TnbToolButton>.Create;
  FToolbarVisible := True;
  FSelectedIndices := TList<Integer>.Create;
  FSelectedIndex := -1;
  FSelectionAnchor := -1;
  FSortColumn := FILE_SORT_NAME;
  FSortDescending := False;
  FColBg      := TAlphaColor($FF141820);
  FColSurface := TAlphaColor($FF1C2330);
  FColBorder  := TAlphaColor($FF344056);
  FColText    := TAlphaColor($FFCCD4DE);
  FColMuted   := FILE_MUTED_TEXT;
  FColAccent  := FILE_ICON_BLUE;
  FSelectionColor := TAlphaColor($FF263246);
  FColumnNameCaption := 'Имя';
  FColumnSizeCaption := 'Размер';
  FColumnModifiedCaption := 'Изменен';
  FColumnKindCaption := 'Тип';
  FFolderCaption := 'папка';
  FFileCaption := 'файл';
  FParentFolderCaption := 'родительская папка';
  FBusyText := 'Загрузка...';
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
  FSelectedIndices.Free;
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
  I: Integer;
  Pane: TnbFilePane;
  C: TCursor;
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
  MarkInternalControl(Result);
  Result.Parent := FToolBar;
  Result.StyleLookup := ScopedStyle('speedbuttonstyle');
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
    MarkInternalControl(Cell);
    Cell.Parent := FHeader;
    Cell.Align := AAlign;
    if AWidth > 0 then
      Cell.Width := AWidth;
    Cell.Tag := AColumn;
    Cell.HitTest := True;
    Cell.OnClick := HandleHeaderClick;
    Cell.Cursor := crHandPoint;

    Caption := TLabel.Create(Cell);
    MarkInternalControl(Caption);
    Caption.Parent := Cell;
    Caption.Align := TAlignLayout.Client;
    Caption.Margins.Rect := RectF(12, 0, 8, 0);
    Caption.HitTest := False;
    Caption.Tag := AColumn;
    Caption.Text := FileHeaderCaption(AText, AColumn, FSortColumn, FSortDescending);
    Caption.StyledSettings := Caption.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size, TStyledSetting.Style];
    Caption.TextSettings.FontColor := FColMuted;
    Caption.TextSettings.Font.Size := 10;
    Caption.TextSettings.Font.Style := [TFontStyle.fsBold];
    Caption.TextSettings.VertAlign := TTextAlign.Center;
    Caption.TextSettings.HorzAlign := TTextAlign.Leading;

    if AAlign <> TAlignLayout.Client then
    begin
      Divider := TRectangle.Create(Cell);
      MarkInternalControl(Divider);
      Divider.Parent := Cell;
      Divider.Align := TAlignLayout.Left;
      Divider.Width := 1;
      Divider.HitTest := False;
      Divider.StyleName := 'file-col-divider';
      Divider.Fill.Color := TAlphaColor($18000000) or (FColBorder and $00FFFFFF);
      Divider.Stroke.Kind := TBrushKind.None;
    end;
  end;

begin
  FToolBar := TLayout.Create(Self);
  MarkInternalControl(FToolBar);
  FToolBar.Parent := Self;
  FToolBar.Align := TAlignLayout.Top;
  FToolBar.Height := 34;
  FToolBar.Margins.Rect := RectF(0, 0, 0, 0);

  AddButton(#$2191, HandleUp,      'Up');
  AddButton('R',    HandleRefresh, 'Refresh');
  FLangNewFileHint    := 'New file';
  FLangNewFolderHint  := 'New folder';
  FLangRenameHint     := 'Rename';
  FLangDeleteHint     := 'Delete';
  FLangNewFileTitle   := 'New file';
  FLangNewFileLabel   := 'Name';
  FLangNewFolderTitle := 'New folder';
  FLangNewFolderLabel := 'Name';
  FLangRenameTitle    := 'Rename';
  FLangRenameLabel    := 'New name';
  FLangDeleteSingle   := 'Delete "%s"?';
  FLangDeleteMany     := 'Delete %d item(s)?';
  FBtnCreateFile := AddButton('F', HandleCreateFile, FLangNewFileHint);
  FBtnMkdir  := AddButton('+', HandleMkdir,  FLangNewFolderHint);
  FBtnRename := AddButton('N', HandleRename, FLangRenameHint);
  FBtnDelete := AddButton('X', HandleDelete, FLangDeleteHint);

  FBreadcrumbBg := TRectangle.Create(Self);
  MarkInternalControl(FBreadcrumbBg);
  FBreadcrumbBg.Parent := Self;
  FBreadcrumbBg.Align := TAlignLayout.Top;
  FBreadcrumbBg.Height := 30;
  FBreadcrumbBg.Margins.Rect := RectF(0, 0, 0, 0);
  FBreadcrumbBg.Fill.Kind := TBrushKind.Solid;
  FBreadcrumbBg.Fill.Color := FColBg;
  FBreadcrumbBg.Stroke.Kind := TBrushKind.Solid;
  FBreadcrumbBg.Stroke.Color := FColBorder;
  FBreadcrumbBg.Stroke.Thickness := 1;
  FBreadcrumbBg.XRadius := 0;
  FBreadcrumbBg.YRadius := 0;
  FBreadcrumbBg.ClipChildren := True;
  FBreadcrumbBg.HitTest := True;

  FBreadcrumbBar := TFlowLayout.Create(FBreadcrumbBg);
  MarkInternalControl(FBreadcrumbBar);
  FBreadcrumbBar.Parent := FBreadcrumbBg;
  FBreadcrumbBar.Align := TAlignLayout.Client;
  FBreadcrumbBar.Margins.Rect := RectF(8, 0, 8, 0);
  FBreadcrumbBar.HitTest := True;

  FListHost := TRectangle.Create(Self);
  MarkInternalControl(FListHost);
  FListHost.Parent := Self;
  FListHost.Align := TAlignLayout.Client;
  FListHost.Margins.Rect := RectF(0, 0, 0, 0);
  FListHost.ClipChildren := True;
  FListHost.HitTest := True;
  FListHost.Fill.Kind := TBrushKind.Solid;
  FListHost.Fill.Color := FColBg;
  FListHost.Stroke.Kind := TBrushKind.Solid;
  FListHost.Stroke.Color := FColBorder;
  FListHost.Stroke.Thickness := 1;
  FListHost.XRadius := 0;
  FListHost.YRadius := 0;
  FListHost.OnDragOver := HandleDragOver;
  FListHost.OnDragDrop := HandleDragDrop;

  FHeader := nil;


  FList := TnbFileListView.Create(FListHost);
  MarkInternalControl(FList);
  FList.FPane := Self;
  FList.Parent := FListHost;
  FList.Align := TAlignLayout.Client;
  FList.Margins.Rect := RectF(0, 0, 0, 0);
  FList.ViewMode := uvmList;
  FList.PanMode := upmTouch;
  FList.ListHeaderHeight := 36;
  FList.ListRowHeight := 34;
  FList.ListAutoRowHeight := False;
  FList.ListGridLines := True;
  FList.ListHorizontalGridLines := False;
  FList.ContentPadding := 0;
  FList.CornerRadius := 0;
  FList.FontSize := 12;
  FList.TitleFontSize := 15;
  FList.DetailFontSize := 12;
  FList.ShowCheckBoxes := True;
  FList.MultiCheck := True;
  FList.ClipChildren := True;
  FList.HitTest := True;
  FList.OnDragOver := HandleDragOver;
  FList.OnDragDrop := HandleDragDrop;
  FList.OnResize := HandleListResize;

  (* TUniListView creates demo columns and edit/delete actions by default. *)
  FList.Actions.Clear;
  FList.Columns.Clear;

  with FList.Columns.Add do
  begin
    FieldName := 'name';
    Caption := FColumnNameCaption;
    WidthMode := ucwmFill;
    MinWidth := 120;
    Sortable := False;
  end;
  with FList.Columns.Add do
  begin
    FieldName := 'size';
    Caption := FColumnSizeCaption;
    WidthMode := ucwmFixed;
    Width := FILE_COL_SIZE_WIDTH;
    Alignment := TTextAlign.Trailing;
    Sortable := False;
  end;
  with FList.Columns.Add do
  begin
    FieldName := 'modified';
    Caption := FColumnModifiedCaption;
    WidthMode := ucwmFixed;
    Width := FILE_COL_DATE_WIDTH;
    Alignment := TTextAlign.Trailing;
    Sortable := False;
  end;

  FBusyOverlay := TLayout.Create(FListHost);
  MarkInternalControl(FBusyOverlay);
  FBusyOverlay.Parent := FListHost;
  FBusyOverlay.Align := TAlignLayout.Contents;
  FBusyOverlay.HitTest := True;
  FBusyOverlay.Visible := False;
  FBusyOverlay.Opacity := 0.94;

  FBusyShade := TRectangle.Create(FBusyOverlay);
  MarkInternalControl(FBusyShade);
  FBusyShade.Parent := FBusyOverlay;
  FBusyShade.Align := TAlignLayout.Contents;
  FBusyShade.HitTest := True;
  FBusyShade.Fill.Kind := TBrushKind.Solid;
  FBusyShade.Fill.Color := FColBg;
  FBusyShade.Stroke.Kind := TBrushKind.None;
  FBusyShade.XRadius := 0;
  FBusyShade.YRadius := 0;

  FBusyIndicator := TAniIndicator.Create(FBusyOverlay);
  MarkInternalControl(FBusyIndicator);
  FBusyIndicator.Parent := FBusyOverlay;
  FBusyIndicator.Align := TAlignLayout.Center;
  FBusyIndicator.Width := 32;
  FBusyIndicator.Height := 32;
  FBusyIndicator.Enabled := False;

  FBusyLabel := TLabel.Create(FBusyOverlay);
  MarkInternalControl(FBusyLabel);
  FBusyLabel.Parent := FBusyOverlay;
  FBusyLabel.Align := TAlignLayout.Center;
  FBusyLabel.Margins.Top := 56;
  FBusyLabel.Width := 220;
  FBusyLabel.Height := 24;
  FBusyLabel.HitTest := False;
  FBusyLabel.StyledSettings :=
    FBusyLabel.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size];
  FBusyLabel.TextSettings.Font.Size := 12;
  FBusyLabel.TextSettings.FontColor := FColMuted;
  FBusyLabel.TextSettings.HorzAlign := TTextAlign.Center;
  FBusyLabel.TextSettings.VertAlign := TTextAlign.Center;
  FBusyLabel.Text := FBusyText;

  FDropOverlay := TRectangle.Create(FListHost);
  MarkInternalControl(FDropOverlay);
  FDropOverlay.Parent := FListHost;
  FDropOverlay.Align := TAlignLayout.Contents;
  FDropOverlay.HitTest := False;
  FDropOverlay.Visible := False;
  FDropOverlay.Fill.Kind := TBrushKind.Solid;
  FDropOverlay.Fill.Color := TAlphaColor($30000000) or
    (FColAccent and $00FFFFFF);
  FDropOverlay.Stroke.Kind := TBrushKind.None;
  FDropOverlay.XRadius := 0;
  FDropOverlay.YRadius := 0;

end;

procedure TnbFilePane.SetDropIndicatorVisible(AVisible: Boolean);
begin
  if FDropOverlay <> nil then
  begin
    FDropOverlay.Visible := AVisible;
    if AVisible then
      FDropOverlay.BringToFront;
  end;
  if FListHost <> nil then
  begin
    FListHost.Stroke.Kind := TBrushKind.Solid;
    if AVisible then
    begin
      FListHost.Stroke.Color := FColAccent;
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
  SetBusy(True);
  FSource.ListDir(APath);
end;

procedure TnbFilePane.Refresh;
begin
  if FSource <> nil then
  begin
    SetBusy(True);
    FSource.ListDir(FPath);
  end;
end;

procedure TnbFilePane.HandleListing(Sender: TObject; const APath: string;
  const AEntries: TnbFileEntryArray);
begin
  SetBusy(False);
  FPath := APath;
  RebuildBreadcrumbs(APath);
  FEntries := AEntries;
  FSelectedIndex := -1;
  FSelectedIndices.Clear;
  SortEntries;
  FillList;
end;

procedure TnbFilePane.HandleSourceError(Sender: TObject; const AMsg: string);
begin
  SetBusy(False);
  if Assigned(FOnError) then
    FOnError(Self, AMsg);
end;

procedure TnbFilePane.ClearBusy;
begin
  SetBusy(False);
end;

procedure TnbFilePane.SetBusy(AValue: Boolean);
begin
  if FBusy = AValue then Exit;
  FBusy := AValue;

  if FBusyOverlay <> nil then
  begin
    FBusyOverlay.Visible := FBusy;
    if FBusy then
      FBusyOverlay.BringToFront;
  end;
  if FBusyIndicator <> nil then
    FBusyIndicator.Enabled := FBusy;
end;

procedure TnbFilePane.SetBusyText(const AValue: string);
begin
  FBusyText := AValue;
  if FBusyText = '' then
    FBusyText := 'Loading...';
  if FBusyLabel <> nil then
    FBusyLabel.Text := FBusyText;
end;

procedure TnbFilePane.HandleChanged(Sender: TObject);
begin
  Refresh;
end;

procedure TnbFilePane.UpdateScrollThumb;
begin
  (* Native TVertScrollBox scrollbars are styled by FMX. *)
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
    FSelectedIndices.Clear;
    UpdateRowSelection;
    Exit;
  end;
  FSelectedIndex := EnsureRange(AIndex, 0, High(FEntries));
  FSelectedIndices.Clear;
  FSelectedIndices.Add(FSelectedIndex);
  FSelectionAnchor := FSelectedIndex;
  UpdateRowSelection;
  EnsureSelectedVisible;
end;

procedure TnbFilePane.EnsureSelectedVisible;
var
  ItemIndex: Integer;
begin
  if FList = nil then Exit;
  if FSelectedIndex = PARENT_ENTRY_TAG then
    ItemIndex := 0
  else if FSelectedIndex >= 0 then
    ItemIndex := FSelectedIndex + 1
  else
    Exit;
  if ItemIndex >= FList.Items.Count then Exit;
  FList.ScrollToItem(ItemIndex);
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
        if FSelectedIndex = PARENT_ENTRY_TAG then
          SelectIndex(0)
        else if FSelectedIndex < 0 then
          SelectIndex(0)
        else if FSelectedIndex = 0 then
        begin
          FSelectedIndex := PARENT_ENTRY_TAG;
          UpdateRowSelection;
          if FList <> nil then
            FList.ScrollToItem(0);
        end
        else
          SelectIndex(FSelectedIndex - 1);
        Key := 0;
      end;
    vkDown:
      begin
        if FSelectedIndex = PARENT_ENTRY_TAG then
          SelectIndex(0)
        else if FSelectedIndex < 0 then
          SelectIndex(0)
        else
          SelectIndex(FSelectedIndex + 1);
        Key := 0;
      end;
    vkReturn:
      begin
        if (FSelectedIndex = PARENT_ENTRY_TAG) and (FSource <> nil) then
          Navigate(FSource.ParentDir(FPath))
        else if SelectedEntry(Entry) and Entry.IsDir and (FSource <> nil) then
          Navigate(FSource.Combine(FPath, Entry.Name))
        else if SelectedEntry(Entry) and (not Entry.IsDir) and (FSource <> nil)
          and Assigned(FOnOpenFile) then
          FOnOpenFile(Self, FSource.Combine(FPath, Entry.Name), Entry);
        Key := 0;
      end;
    vkBack:
      begin
        HandleUp(Self);
        Key := 0;
      end;
    Ord('A'):
      if ssCtrl in Shift then
      begin
        FSelectedIndices.Clear;
        for var I := 0 to High(FEntries) do
          FSelectedIndices.Add(I);
        if FSelectedIndices.Count > 0 then
        begin
          FSelectedIndex := 0;
          FSelectionAnchor := 0;
        end;
        UpdateRowSelection;
        Key := 0;
      end;
  end;
end;

procedure TnbFilePane.FillList;
var
  I: Integer;
  Entry: TnbFileEntry;
  Item: TUniListItem;

  procedure AddRow(const AEntry: TnbFileEntry; AEntryIndex: Integer);
  begin
    Item := FList.Items.Add;
    Item.ID := IntToStr(AEntryIndex);
    Item.Title := AEntry.Name;
    Item.Text := EntryDetailCaption(AEntry, AEntryIndex);
    Item.Detail := '';
    Item.SetField('name', AEntry.Name);
    if AEntryIndex = PARENT_ENTRY_TAG then
    begin
      Item.SetField('size', '');
      Item.SetField('modified', '');
    end
    else
    begin
      if AEntry.IsDir then
        Item.SetField('size', '--')
      else
        Item.SetField('size', FormatFileSize(AEntry.Size));
      Item.SetField('modified', FormatFileModified(AEntry.Modified));
    end;
  end;
begin
  if FList = nil then Exit;
  FList.BeginUpdate;
  try
    FList.Clear;
    Entry := Default(TnbFileEntry);
    Entry.Name := '..';
    Entry.IsDir := True;
    AddRow(Entry, PARENT_ENTRY_TAG);
    for I := 0 to High(FEntries) do
      AddRow(FEntries[I], I);
  finally
    FList.EndUpdate;
  end;
  UpdateRowSelection;
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
            Result := CompareText(FileEntryKind(L), FileEntryKind(R));
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
  if (FList <> nil) and (FList.Columns.Count >= 3) then
  begin
    FList.Columns[0].Caption := FileHeaderCaption(FColumnNameCaption,
      FILE_SORT_NAME, FSortColumn, FSortDescending);
    FList.Columns[1].Caption := FileHeaderCaption(FColumnSizeCaption,
      FILE_SORT_SIZE, FSortColumn, FSortDescending);
    FList.Columns[2].Caption := FileHeaderCaption(FColumnModifiedCaption,
      FILE_SORT_DATE, FSortColumn, FSortDescending);
  end;
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
        TLabel(Child).Text := FileHeaderCaption(HeaderCaption(Column),
          Column, FSortColumn, FSortDescending);
    end;
  end;
end;

function TnbFilePane.HeaderCaption(AColumn: Integer): string;
begin
  case AColumn of
    FILE_SORT_DATE:
      Result := FColumnModifiedCaption;
    FILE_SORT_SIZE:
      Result := FColumnSizeCaption;
    FILE_SORT_KIND:
      Result := FColumnKindCaption;
  else
    Result := FColumnNameCaption;
  end;
end;

function TnbFilePane.EntryDetailCaption(const AEntry: TnbFileEntry;
  ATag: Integer): string;
begin
  if ATag = PARENT_ENTRY_TAG then
    Exit(FParentFolderCaption);

  if AEntry.Permissions <> 0 then
    Exit(FormatFilePermissions(AEntry.Permissions, AEntry.IsDir));

  if AEntry.IsDir then
    Result := FFolderCaption
  else
    Result := FFileCaption;
end;

procedure TnbFilePane.SetCaptions(const AName, ASize, AModified, AKind,
  AFolder, AFile, AParentFolder: string);
begin
  FColumnNameCaption := AName;
  FColumnSizeCaption := ASize;
  FColumnModifiedCaption := AModified;
  FColumnKindCaption := AKind;
  FFolderCaption := AFolder;
  FFileCaption := AFile;
  FParentFolderCaption := AParentFolder;

  UpdateHeaderCaptions;
  if FList <> nil then
    FillList;
end;

procedure TnbFilePane.SetActionStrings(
  const AHintNewFolder, AHintRename, AHintDelete: string;
  const ANewFolderTitle, ANewFolderLabel: string;
  const ARenameTitle, ARenameLabel: string;
  const ADeleteSingle, ADeleteMany: string);
begin
  FLangNewFolderHint  := AHintNewFolder;
  FLangRenameHint     := AHintRename;
  FLangDeleteHint     := AHintDelete;
  FLangNewFolderTitle := ANewFolderTitle;
  FLangNewFolderLabel := ANewFolderLabel;
  FLangRenameTitle    := ARenameTitle;
  FLangRenameLabel    := ARenameLabel;
  FLangDeleteSingle   := ADeleteSingle;
  FLangDeleteMany     := ADeleteMany;
  if FBtnMkdir  <> nil then FBtnMkdir.Hint  := AHintNewFolder;
  if FBtnRename <> nil then FBtnRename.Hint := AHintRename;
  if FBtnDelete <> nil then FBtnDelete.Hint := AHintDelete;
end;

procedure TnbFilePane.HandleHeaderClick(Sender: TObject);
begin
  if Sender is TFmxObject then
    HandleNativeHeaderClick(TFmxObject(Sender).Tag);
end;

procedure TnbFilePane.HandleNativeHeaderClick(AColumn: Integer);
var
  I: Integer;
  HadSelection: Boolean;
  SelectedName: string;
  SelectedIsDir: Boolean;
  Entry: TnbFileEntry;
begin
  if AColumn = FSortColumn then
    FSortDescending := not FSortDescending
  else
  begin
    FSortColumn := AColumn;
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
  FSelectedIndices.Clear;
  if HadSelection then
    for I := 0 to High(FEntries) do
      if (FEntries[I].IsDir = SelectedIsDir)
        and SameText(FEntries[I].Name, SelectedName) then
      begin
        FSelectedIndex := I;
        FSelectedIndices.Add(I);
        FSelectionAnchor := I;
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
  if Idx = PARENT_ENTRY_TAG then Exit;
  if (Idx < 0) or (Idx > High(FEntries)) then Exit;
  AEntry := FEntries[Idx];
  Result := True;
end;

function TnbFilePane.SelectedEntries: TnbFileEntryArray;
var
  I, Idx: Integer;
begin
  Result := nil;
  for I := 0 to FSelectedIndices.Count - 1 do
  begin
    Idx := FSelectedIndices[I];
    if (Idx >= 0) and (Idx <= High(FEntries)) then
      Result := Result + [FEntries[Idx]];
  end;
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

procedure TnbFilePane.HandleListItemClick(AItemIndex: Integer;
  AShift: TShiftState);
var
  EntryIndex, Anchor, Lo, Hi, I: Integer;
begin
  if CanFocus then SetFocus;
  EntryIndex := AItemIndex - 1;
  if AItemIndex = 0 then
  begin
    FSelectedIndex := PARENT_ENTRY_TAG;
    FSelectedIndices.Clear;
  end
  else if (EntryIndex >= 0) and (EntryIndex <= High(FEntries)) then
  begin
    if ssCtrl in AShift then
    begin
      if FSelectedIndices.Contains(EntryIndex) then
        FSelectedIndices.Remove(EntryIndex)
      else
        FSelectedIndices.Add(EntryIndex);
      FSelectedIndex := EntryIndex;
      FSelectionAnchor := EntryIndex;
    end
    else if ssShift in AShift then
    begin
      Anchor := FSelectionAnchor;
      if Anchor < 0 then Anchor := EntryIndex;
      FSelectedIndices.Clear;
      Lo := Min(Anchor, EntryIndex);
      Hi := Max(Anchor, EntryIndex);
      for I := Lo to Hi do
        FSelectedIndices.Add(I);
      FSelectedIndex := EntryIndex;
    end
    else
    begin
      FSelectedIndices.Clear;
      FSelectedIndices.Add(EntryIndex);
      FSelectedIndex := EntryIndex;
      FSelectionAnchor := EntryIndex;
    end;
  end;
  UpdateRowSelection;
  if Assigned(FOnActivated) then
    FOnActivated(Self);
end;

procedure TnbFilePane.HandleListItemDoubleClick(AItemIndex: Integer);
var
  Entry: TnbFileEntry;
begin
  HandleListItemClick(AItemIndex, []);
  if FSelectedIndex = PARENT_ENTRY_TAG then
  begin
    if FSource <> nil then Navigate(FSource.ParentDir(FPath));
    Exit;
  end;
  if not SelectedEntry(Entry) then Exit;
  if Entry.IsDir and (FSource <> nil) then
    Navigate(FSource.Combine(FPath, Entry.Name))
  else if (FSource <> nil) and Assigned(FOnOpenFile) then
    FOnOpenFile(Self, FSource.Combine(FPath, Entry.Name), Entry);
end;

procedure TnbFilePane.HandleListMouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  Entry: TnbFileEntry;
begin
  FDragSource := nil;
  FDragArmed := False;
  FDragging := False;
  if (Button = TMouseButton.mbLeft) and SelectedEntry(Entry) then
  begin
    FDragSource := Self;
    FDragArmed := True;
    FDragStartScreen := FList.LocalToScreen(PointF(X, Y));
    TControlAccess(FList).Capture;
  end;
end;

procedure TnbFilePane.HandleListMouseMove(Shift: TShiftState; X, Y: Single);
var
  ScreenPt: TPointF;
  Target: TnbFilePane;
begin
  if (FDragSource <> Self) or (not FDragArmed) or not (ssLeft in Shift) then Exit;
  ScreenPt := FList.LocalToScreen(PointF(X, Y));
  if not FDragging then
    FDragging := (Abs(ScreenPt.X - FDragStartScreen.X) > 4)
      or (Abs(ScreenPt.Y - FDragStartScreen.Y) > 4);
  if not FDragging then Exit;
  SetDraggingCursor(True);
  Target := PaneAtScreenPoint(ScreenPt);
  if Target = Self then Target := nil;
  if Target <> FDragTarget then
  begin
    ClearDropIndicator;
    FDragTarget := Target;
    if FDragTarget <> nil then
      FDragTarget.SetDropIndicatorVisible(True);
  end;
end;

procedure TnbFilePane.HandleListMouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Single);
var
  ScreenPt: TPointF;
  Target: TnbFilePane;
begin
  if (Button <> TMouseButton.mbLeft) or (FDragSource <> Self)
    or (not FDragArmed) then Exit;
  try
    if FDragging then
    begin
      ScreenPt := FList.LocalToScreen(PointF(X, Y));
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

procedure TnbFilePane.UpdateRowSelection;
var
  I: Integer;
begin
  if FList = nil then Exit;
  FList.BeginUpdate;
  try
    for I := 0 to FList.Items.Count - 1 do
      if I = 0 then
        FList.Items[I].Checked := False
      else
        FList.Items[I].Checked := FSelectedIndices.Contains(I - 1);
    if FSelectedIndex = PARENT_ENTRY_TAG then
      FList.SelectedIndex := 0
    else if FSelectedIndex >= 0 then
      FList.SelectedIndex := FSelectedIndex + 1
    else
      FList.SelectedIndex := -1;
  finally
    FList.EndUpdate;
  end;
  FList.Repaint;
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

procedure TnbFilePane.HandleCreateFile(Sender: TObject);
var
  Values: array of string;
begin
  if FSource = nil then Exit;
  SetLength(Values, 1);
  Values[0] := '';
  if Assigned(FOnPrompt) and
    FOnPrompt(FLangNewFileTitle, FLangNewFileLabel, Values[0])
    and (Trim(Values[0]) <> '') then
    FSource.CreateFile(FSource.Combine(FPath, Trim(Values[0])));
end;

procedure TnbFilePane.HandleMkdir(Sender: TObject);
var
  Values: array of string;
begin
  if FSource = nil then Exit;
  SetLength(Values, 1);
  Values[0] := '';
  if Assigned(FOnPrompt) and
    FOnPrompt(FLangNewFolderTitle, FLangNewFolderLabel, Values[0])
    and (Trim(Values[0]) <> '') then
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
  if Assigned(FOnPrompt) and
    FOnPrompt(FLangRenameTitle, FLangRenameLabel, Values[0])
    and (Trim(Values[0]) <> '') and (Trim(Values[0]) <> Entry.Name) then
    FSource.Rename(FSource.Combine(FPath, Entry.Name),
                   FSource.Combine(FPath, Trim(Values[0])));
end;

procedure TnbFilePane.HandleDelete(Sender: TObject);
var
  Entries: TnbFileEntryArray;
  Entry: TnbFileEntry;
  Msg: string;
begin
  if FSource = nil then Exit;
  Entries := SelectedEntries;
  if Length(Entries) = 0 then Exit;
  if Length(Entries) = 1 then
    Msg := Format(FLangDeleteSingle, [Entries[0].Name])
  else
    Msg := Format(FLangDeleteMany, [Length(Entries)]);
  var Confirmed: Boolean;
  if Assigned(FOnConfirmDelete) then
    Confirmed := FOnConfirmDelete(Msg)
  else
    Confirmed := False;
  if Confirmed then
    for Entry in Entries do
      FSource.Delete(FSource.Combine(FPath, Entry.Name), Entry.IsDir);
end;

procedure TnbFilePane.HandleTransfer(Sender: TObject);
begin
  if Assigned(FOnTransfer) then
    FOnTransfer(Self);
end;

procedure TnbFilePane.CommandUp;
begin
  HandleUp(Self);
end;

procedure TnbFilePane.CommandRefresh;
begin
  HandleRefresh(Self);
end;

procedure TnbFilePane.CommandCreateFile;
begin
  HandleCreateFile(Self);
end;

procedure TnbFilePane.CommandNewFolder;
begin
  HandleMkdir(Self);
end;

procedure TnbFilePane.CommandRename;
begin
  HandleRename(Self);
end;

procedure TnbFilePane.CommandDelete;
begin
  HandleDelete(Self);
end;

procedure TnbFilePane.CommandTransfer;
begin
  HandleTransfer(Self);
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

function TnbFilePane.ScopedStyle(const ABaseStyle: string): string;
begin
  if FStyleLookupPrefix = '' then
    Result := ABaseStyle
  else
    Result := FStyleLookupPrefix + ABaseStyle;
end;

procedure TnbFilePane.ApplyStyleLookups;
var
  I: Integer;
begin
  for I := 0 to FButtons.Count - 1 do
    FButtons[I].StyleLookup := ScopedStyle('speedbuttonstyle');
  FillList;
end;

procedure TnbFilePane.SetStyleLookupPrefix(const AValue: string);
begin
  if FStyleLookupPrefix = AValue then Exit;
  FStyleLookupPrefix := AValue;
  ApplyStyleLookups;
end;

procedure TnbFilePane.SetToolbarLeadingInset(const AValue: Single);
begin
  if SameValue(FToolbarLeadingInset, AValue) then
    Exit;
  FToolbarLeadingInset := Max(0, AValue);
  if FToolBar <> nil then
    FToolBar.Padding.Left := FToolbarLeadingInset;
end;

procedure TnbFilePane.SetToolbarVisible(AValue: Boolean);
begin
  if FToolbarVisible = AValue then
    Exit;
  FToolbarVisible := AValue;
  if FToolBar <> nil then
  begin
    FToolBar.Visible := AValue;
    if AValue then
      FToolBar.Height := 34
    else
      FToolBar.Height := 0;
  end;
end;

function TnbFilePane.AddActionButton(const AGlyph, AHint: string;
  AOnClick: TNotifyEvent): TnbToolButton;
begin
  Result := AddButton(AGlyph, AOnClick, AHint);
end;


class procedure TnbFilePane.SplitPathSegments(const APath: string;
  out ALabels, AFullPaths: TArray<string>);
var
  Parts: TArray<string>;
  I: Integer;
  Sep: Char;
  Accumulated: string;
  IsUnix: Boolean;
begin
  ALabels := [];
  AFullPaths := [];
  if APath = '' then Exit;

  IsUnix := APath.StartsWith('/');
  if IsUnix then
    Sep := '/'
  else
    Sep := '\';

  Parts := APath.Split([Sep], TStringSplitOptions.ExcludeEmpty);

  if IsUnix then
  begin
    SetLength(ALabels, Length(Parts) + 1);
    SetLength(AFullPaths, Length(Parts) + 1);
    ALabels[0] := '/';
    AFullPaths[0] := '/';
    Accumulated := '';
    for I := 0 to High(Parts) do
    begin
      Accumulated := Accumulated + '/' + Parts[I];
      ALabels[I + 1] := Parts[I];
      AFullPaths[I + 1] := Accumulated;
    end;
  end
  else
  begin
    SetLength(ALabels, Length(Parts));
    SetLength(AFullPaths, Length(Parts));
    if Length(Parts) = 0 then Exit;
    ALabels[0] := Parts[0] + '\';
    AFullPaths[0] := Parts[0] + '\';
    Accumulated := Parts[0] + '\';
    for I := 1 to High(Parts) do
    begin
      Accumulated := Accumulated + Parts[I] + '\';
      ALabels[I] := Parts[I];
      AFullPaths[I] := Accumulated;
    end;
  end;
end;

procedure TnbFilePane.RebuildBreadcrumbs(const APath: string);
const
  BAR_H   = 30;
  SEP_W   = 16;
  FONT_SZ = 12;
var
  Labels, Paths: TArray<string>;
  I: Integer;
  Lbl: TLabel;
  Sep: TLabel;
  IsLast: Boolean;
  Obj: TFmxObject;
  TxtW: Integer;
begin
  if FBreadcrumbBar = nil then Exit;

  while FBreadcrumbBar.ChildrenCount > 0 do
  begin
    Obj := FBreadcrumbBar.Children[0];
    Obj.Parent := nil;
    Obj.Free;
  end;

  SplitPathSegments(APath, Labels, Paths);
  FBreadcrumbPaths := Paths;

  for I := 0 to High(Labels) do
  begin
    IsLast := (I = High(Labels));

    if I > 0 then
    begin
      Sep := TLabel.Create(FBreadcrumbBar);
      Sep.Parent := FBreadcrumbBar;
      Sep.Width := SEP_W;
      Sep.Height := BAR_H;
      Sep.Text := '›';
      Sep.StyledSettings := [];
      Sep.TextSettings.FontColor := FColMuted;
      Sep.TextSettings.Font.Size := FONT_SZ;
      Sep.TextSettings.HorzAlign := TTextAlign.Center;
      Sep.TextSettings.VertAlign := TTextAlign.Center;
      Sep.HitTest := False;
    end;

    TxtW := Length(Labels[I]) * 7 + 10;
    if TxtW < 16 then TxtW := 16;

    Lbl := TLabel.Create(FBreadcrumbBar);
    Lbl.Parent := FBreadcrumbBar;
    Lbl.Width := TxtW;
    Lbl.Height := BAR_H;
    Lbl.Text := Labels[I];
    Lbl.StyledSettings := [];
    Lbl.TextSettings.Font.Size := FONT_SZ;
    Lbl.TextSettings.HorzAlign := TTextAlign.Leading;
    Lbl.TextSettings.VertAlign := TTextAlign.Center;
    if IsLast then
    begin
      Lbl.TextSettings.FontColor := FColText;
      Lbl.TextSettings.Font.Style := [TFontStyle.fsBold];
      Lbl.HitTest := False;
    end
    else
    begin
      Lbl.TextSettings.FontColor := FColMuted;
      Lbl.Tag := I;
      Lbl.HitTest := True;
      Lbl.Cursor := crHandPoint;
      Lbl.OnClick := HandleBreadcrumbClick;
    end;
  end;
end;

procedure TnbFilePane.HandleBreadcrumbClick(Sender: TObject);
var
  Idx: Integer;
begin
  if not (Sender is TLabel) then Exit;
  Idx := TLabel(Sender).Tag;
  if (Idx >= 0) and (Idx < Length(FBreadcrumbPaths)) then
    Navigate(FBreadcrumbPaths[Idx]);
end;

procedure TnbFilePane.ApplyColors(ABg, ASurface, ABorder, AText,
  AMuted, AAccent: TAlphaColor);
var
  I, J: Integer;
  Child, GrandChild: TFmxObject;
begin
  FColBg := ABg;
  FColSurface := ASurface;
  FColBorder := ABorder;
  FColText := AText;
  if AMuted <> 0 then
    FColMuted := AMuted
  else
    FColMuted := TAlphaColor($FF000000)
      or ((Round(((AText shr 16) and $FF) * 0.58 + ((ABg shr 16) and $FF) * 0.42) and $FF) shl 16)
      or ((Round(((AText shr 8) and $FF) * 0.58 + ((ABg shr 8) and $FF) * 0.42) and $FF) shl 8)
      or (Round((AText and $FF) * 0.58 + (ABg and $FF) * 0.42) and $FF);
  if AAccent <> 0 then
    FColAccent := AAccent
  else
    FColAccent := AText;
  FSelectionColor := TAlphaColor($FF000000)
    or ((Round(((ASurface shr 16) and $FF) * 0.82 + ((FColAccent shr 16) and $FF) * 0.18) and $FF) shl 16)
    or ((Round(((ASurface shr 8) and $FF) * 0.82 + ((FColAccent shr 8) and $FF) * 0.18) and $FF) shl 8)
    or (Round((ASurface and $FF) * 0.82 + (FColAccent and $FF) * 0.18) and $FF);
  for I := 0 to FButtons.Count - 1 do
    FButtons[I].ApplyLocalChrome(ABg, ABorder, AText);
  if FBreadcrumbBg <> nil then
  begin
    FBreadcrumbBg.Fill.Color := ABg;
    FBreadcrumbBg.Stroke.Color := ABorder;
    RebuildBreadcrumbs(FPath);
  end;
  if FListHost <> nil then
  begin
    FListHost.Fill.Kind := TBrushKind.Solid;
    FListHost.Fill.Color := ABg;
    FListHost.Stroke.Kind := TBrushKind.Solid;
    FListHost.Stroke.Color := ABorder;
    FListHost.Stroke.Thickness := 1;
  end;
  if FList <> nil then
  begin
    FList.BackgroundColor := ABg;
    FList.CardColor := ABg;
    FList.CardHotColor := ASurface;
    FList.CardSelectedColor := FSelectionColor;
    FList.TextColor := AText;
    FList.SecondaryTextColor := FColMuted;
    FList.AccentColor := FColAccent;
    FList.HeaderColor := ASurface;
    FList.AlternateRowColor := ABg;
    FList.GridColor := TAlphaColor($30000000) or (ABorder and $00FFFFFF);
  end;
  if FBusyShade <> nil then
    FBusyShade.Fill.Color := ABg;
  if FDropOverlay <> nil then
    FDropOverlay.Fill.Color := TAlphaColor($30000000) or
      (FColAccent and $00FFFFFF);
  if FBusyLabel <> nil then
    FBusyLabel.TextSettings.FontColor := FColMuted;
  if FHeader <> nil then
    for I := 0 to FHeader.ChildrenCount - 1 do
    begin
      Child := FHeader.Children[I];
      if (Child is TRectangle) and SameText(Child.StyleName, 'file-header-line') then
        TRectangle(Child).Fill.Color := TAlphaColor($30000000) or
          (ABorder and $00FFFFFF);
      for J := 0 to Child.ChildrenCount - 1 do
      begin
        GrandChild := Child.Children[J];
        if GrandChild is TLabel then
          TLabel(GrandChild).TextSettings.FontColor := FColMuted
        else if (GrandChild is TRectangle)
          and SameText(GrandChild.StyleName, 'file-col-divider') then
          TRectangle(GrandChild).Fill.Color := TAlphaColor($18000000) or
            (ABorder and $00FFFFFF);
      end;
    end;
  FillList;
  UpdateRowSelection;
end;

procedure TnbFilePane.LoadThemeFromFile(const AFileName: string);
begin
  if (FList = nil) or (AFileName = '') or not FileExists(AFileName) then
    Exit;
  FList.LoadThemeFromFile(AFileName);
  FList.Repaint;
end;

procedure TnbFilePane.SetListFontSize(AFontSize: Single);
begin
  if (FList = nil) or (AFontSize <= 0) then
    Exit;
  FList.FontSize := AFontSize;
  FList.TitleFontSize := AFontSize;
  FList.DetailFontSize := AFontSize;
  FList.Repaint;
end;

initialization
  RegisterFmxClasses([TnbFilePane]);

end.
