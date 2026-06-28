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
  FMX.Objects, FMX.Edit, FMX.ListBox,
  nbFileSources, nbFilePane.Controls, nbVectorIcons;

type
  TnbFilePane = class;

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
    FList: TListBox;
    FBusyOverlay: TLayout;
    FBusyShade: TRectangle;
    FBusyIndicator: TAniIndicator;
    FBusyLabel: TLabel;
    FBusy: Boolean;
    FSelectedIndex: Integer;
    FSelectedIndices: TList<Integer>;
    FSelectionAnchor: Integer;
    FSortColumn: Integer;
    FSortDescending: Boolean;
    FSelectionColor: TAlphaColor;
    FButtons: TList<TnbToolButton>;
    FTransferButton: TnbToolButton;
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
    FBtnMkdir:  TnbToolButton;
    FBtnRename: TnbToolButton;
    FBtnDelete: TnbToolButton;
    FLangNewFolderHint:  string;
    FLangRenameHint:     string;
    FLangDeleteHint:     string;
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
    procedure RebuildBreadcrumbs(const APath: string);
    procedure HandleBreadcrumbClick(Sender: TObject);
    class procedure SplitPathSegments(const APath: string;
      out ALabels, AFullPaths: TArray<string>); static;
    procedure SetBusy(AValue: Boolean);
    procedure SetBusyText(const AValue: string);
    function ScopedStyle(const ABaseStyle: string): string;
    procedure SetStyleLookupPrefix(const AValue: string);
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
    procedure SetCaptions(const AName, ASize, AModified, AKind, AFolder,
      AFile, AParentFolder: string);
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

{ TnbFilePane }

constructor TnbFilePane.Create(AOwner: TComponent);
begin
  inherited;
  if FInstances = nil then
    FInstances := TList<TnbFilePane>.Create;
  FInstances.Add(Self);
  FButtons := TList<TnbToolButton>.Create;
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
  FColumnNameCaption := 'Name';
  FColumnSizeCaption := 'Size';
  FColumnModifiedCaption := 'Date Modified';
  FColumnKindCaption := 'Kind';
  FFolderCaption := 'folder';
  FFileCaption := 'file';
  FParentFolderCaption := 'parent folder';
  FBusyText := 'Loading...';
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

var
  HeaderLine: TRectangle;
begin
  FToolBar := TLayout.Create(Self);
  MarkInternalControl(FToolBar);
  FToolBar.Parent := Self;
  FToolBar.Align := TAlignLayout.Top;
  FToolBar.Height := 34;
  FToolBar.Margins.Rect := RectF(0, 0, 0, 0);

  AddButton(#$2191, HandleUp,      'Up');
  AddButton('R',    HandleRefresh, 'Refresh');
  FLangNewFolderHint  := 'New folder';
  FLangRenameHint     := 'Rename';
  FLangDeleteHint     := 'Delete';
  FLangNewFolderTitle := 'New folder';
  FLangNewFolderLabel := 'Name';
  FLangRenameTitle    := 'Rename';
  FLangRenameLabel    := 'New name';
  FLangDeleteSingle   := 'Delete "%s"?';
  FLangDeleteMany     := 'Delete %d item(s)?';
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

  FHeader := TLayout.Create(FListHost);
  MarkInternalControl(FHeader);
  FHeader.Parent := FListHost;
  FHeader.Align := TAlignLayout.Top;
  FHeader.Height := FILE_HEADER_HEIGHT;
  FHeader.HitTest := False;

  HeaderLine := TRectangle.Create(FHeader);
  MarkInternalControl(HeaderLine);
  HeaderLine.Parent := FHeader;
  HeaderLine.Align := TAlignLayout.Bottom;
  HeaderLine.Height := 1;
  HeaderLine.StyleName := 'file-header-line';
  HeaderLine.HitTest := False;
  HeaderLine.Fill.Color := TAlphaColor($30000000) or (FColBorder and $00FFFFFF);
  HeaderLine.Stroke.Kind := TBrushKind.None;

  AddHeaderCell(HeaderCaption(FILE_SORT_SIZE), TAlignLayout.Right,
    FILE_COL_SIZE_WIDTH, FILE_SORT_SIZE);
  AddHeaderCell(HeaderCaption(FILE_SORT_DATE), TAlignLayout.Right,
    FILE_COL_DATE_WIDTH, FILE_SORT_DATE);
  AddHeaderCell(HeaderCaption(FILE_SORT_NAME), TAlignLayout.Client, 0,
    FILE_SORT_NAME);

  FList := TListBox.Create(FListHost);
  MarkInternalControl(FList);
  FList.Parent := FListHost;
  FList.Align := TAlignLayout.Client;
  FList.Margins.Rect := RectF(1, 1, 1, 1);
  FList.StyleLookup := ScopedStyle('listboxstyle');
  FList.ShowScrollBars := True;
  FList.ClipChildren := True;
  FList.HitTest := True;
  FList.ItemHeight := FILE_ROW_HEIGHT;
  FList.DefaultItemStyles.ItemStyle := 'listboxitemstyle';
  FList.OnDragOver := HandleDragOver;
  FList.OnDragDrop := HandleDragDrop;
  FList.OnViewportPositionChange := HandleListViewportChanged;
  FList.OnResize := HandleListResize;

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

end;

procedure TnbFilePane.SetDropIndicatorVisible(AVisible: Boolean);
begin
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
  if ItemIndex >= FList.Count then Exit;
  FList.ScrollToItem(FList.ListItems[ItemIndex]);
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
            FList.ScrollToItem(FList.ListItems[0]);
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
  Item: TListBoxItem;
  Entry: TnbFileEntry;
  RowBg, Line: TRectangle;
  Row, NameCell, TextStack: TLayout;
  NameText, DetailText, DateText, SizeText: TLabel;
  Icon: TnbVectorIcon;

  procedure AddRow(const AEntry: TnbFileEntry; ATag: Integer);
  begin
    Item := TListBoxItem.Create(FList);
    Item.Parent := FList;
    Item.Height := FILE_ROW_HEIGHT;
    Item.Tag := ATag;
    Item.Text := '';
    Item.StyleLookup := ScopedStyle('listboxitemstyle');
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

    SizeText := TLabel.Create(Row);
    SizeText.Parent := Row;
    SizeText.Align := TAlignLayout.Right;
    SizeText.Width := FILE_COL_SIZE_WIDTH;
    SizeText.Margins.Rect := RectF(6, 0, 8, 0);
    SizeText.HitTest := False;
    if ATag = PARENT_ENTRY_TAG then
      SizeText.Text := ''
    else if AEntry.IsDir then
      SizeText.Text := '--'
    else
      SizeText.Text := FormatFileSize(AEntry.Size);
    SizeText.StyledSettings := SizeText.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size];
    SizeText.TextSettings.FontColor := FColMuted;
    SizeText.TextSettings.Font.Size := 11;
    SizeText.TextSettings.VertAlign := TTextAlign.Center;
    SizeText.TextSettings.HorzAlign := TTextAlign.Trailing;

    DateText := TLabel.Create(Row);
    DateText.Parent := Row;
    DateText.Align := TAlignLayout.Right;
    DateText.Width := FILE_COL_DATE_WIDTH;
    DateText.Margins.Rect := RectF(6, 0, 12, 0);
    DateText.HitTest := False;
    if ATag = PARENT_ENTRY_TAG then
      DateText.Text := ''
    else
      DateText.Text := FormatFileModified(AEntry.Modified);
    DateText.StyledSettings := DateText.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size];
    DateText.TextSettings.FontColor := FColMuted;
    DateText.TextSettings.Font.Size := 11;
    DateText.TextSettings.VertAlign := TTextAlign.Center;
    DateText.TextSettings.HorzAlign := TTextAlign.Trailing;

    NameCell := TLayout.Create(Row);
    NameCell.Parent := Row;
    NameCell.Align := TAlignLayout.Client;
    NameCell.HitTest := False;

    Icon := TnbVectorIcon.Create(NameCell);
    Icon.Parent := NameCell;
    Icon.Align := TAlignLayout.Left;
    Icon.Width := 18;
    Icon.Margins.Rect := RectF(8, 9, 6, 9);
    Icon.HitTest := False;
    Icon.IconName := FILE_ICON_FOLDER;
    if not AEntry.IsDir then
      Icon.IconName := FILE_ICON_DOCUMENT;
    Icon.IconColor := FColAccent;
    Icon.StrokeWidth := 1.4;

    TextStack := TLayout.Create(NameCell);
    TextStack.Parent := NameCell;
    TextStack.Align := TAlignLayout.Client;
    TextStack.Margins.Rect := RectF(0, 4, 8, 3);
    TextStack.HitTest := False;

    NameText := TLabel.Create(TextStack);
    NameText.Parent := TextStack;
    NameText.Align := TAlignLayout.Top;
    NameText.Height := 18;
    NameText.HitTest := False;
    NameText.Text := AEntry.Name;
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
    DetailText.Text := EntryDetailCaption(AEntry, ATag);
    DetailText.StyledSettings := DetailText.StyledSettings - [TStyledSetting.FontColor, TStyledSetting.Size];
    DetailText.TextSettings.FontColor := FColMuted;
    DetailText.TextSettings.Font.Size := 9;
    DetailText.TextSettings.VertAlign := TTextAlign.Leading;
    DetailText.TextSettings.HorzAlign := TTextAlign.Leading;

    Line := TRectangle.Create(Item);
    Line.Parent := Item;
    Line.Align := TAlignLayout.Bottom;
    Line.Height := 1;
    Line.HitTest := False;
    Line.Fill.Color := TAlphaColor($18000000) or (FColBorder and $00FFFFFF);
    Line.Stroke.Kind := TBrushKind.None;
  end;
begin
  FList.BeginUpdate;
  try
    FList.Clear;
    Entry := Default(TnbFileEntry);
    Entry.Name := '..';
    Entry.IsDir := True;
    AddRow(Entry, PARENT_ENTRY_TAG);

    for I := 0 to High(FEntries) do
    begin
      Entry := FEntries[I];
      AddRow(Entry, I);
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

procedure TnbFilePane.HandleRowDblClick(Sender: TObject);
var
  Entry: TnbFileEntry;
begin
  SelectRowFromObject(Sender);
  if FSelectedIndex = PARENT_ENTRY_TAG then
  begin
    if FSource <> nil then
      Navigate(FSource.ParentDir(FPath));
    Exit;
  end;
  if not SelectedEntry(Entry) then Exit;
  if Entry.IsDir and (FSource <> nil) then
    Navigate(FSource.Combine(FPath, Entry.Name))
  else if (not Entry.IsDir) and (FSource <> nil) and Assigned(FOnOpenFile) then
    FOnOpenFile(Self, FSource.Combine(FPath, Entry.Name), Entry);
end;

procedure TnbFilePane.HandleRowMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Entry: TnbFileEntry;
  Ctrl: TControl;
  TagValue, Anchor, Lo, Hi, I: Integer;
begin
  if CanFocus then
    SetFocus;
  FDragSource := nil;
  FDragArmed := False;
  FDragging := False;

  TagValue := -1;
  if Sender is TFmxObject then
    TagValue := TFmxObject(Sender).Tag;

  if (ssCtrl in Shift) and (TagValue <> PARENT_ENTRY_TAG)
    and (TagValue >= 0) and (TagValue <= High(FEntries)) then
  begin
    TagValue := EnsureRange(TagValue, 0, High(FEntries));
    if FSelectedIndices.Contains(TagValue) then
    begin
      FSelectedIndices.Remove(TagValue);
      if FSelectedIndex = TagValue then
      begin
        if FSelectedIndices.Count > 0 then
          FSelectedIndex := FSelectedIndices[FSelectedIndices.Count - 1]
        else
          FSelectedIndex := -1;
      end;
    end
    else
    begin
      FSelectedIndices.Add(TagValue);
      FSelectedIndex := TagValue;
      FSelectionAnchor := TagValue;
    end;
    UpdateRowSelection;
  end
  else if (ssShift in Shift) and (TagValue <> PARENT_ENTRY_TAG)
    and (TagValue >= 0) and (TagValue <= High(FEntries)) then
  begin
    TagValue := EnsureRange(TagValue, 0, High(FEntries));
    Anchor := FSelectionAnchor;
    if Anchor < 0 then Anchor := 0;
    FSelectedIndices.Clear;
    Lo := Min(Anchor, TagValue);
    Hi := Max(Anchor, TagValue);
    for I := Lo to Hi do
      FSelectedIndices.Add(I);
    FSelectedIndex := TagValue;
    UpdateRowSelection;
  end
  else
    SelectRowFromObject(Sender);

  if FSelectedIndex = PARENT_ENTRY_TAG then
  begin
    if Assigned(FOnActivated) then
      FOnActivated(Self);
    Exit;
  end;
  if (Button = TMouseButton.mbLeft) and SelectedEntry(Entry) then
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
  TagValue: NativeInt;
begin
  if AObject is TFmxObject then
  begin
    Obj := TFmxObject(AObject);
    TagValue := Obj.Tag;
    if TagValue = PARENT_ENTRY_TAG then
    begin
      FSelectedIndex := PARENT_ENTRY_TAG;
      FSelectedIndices.Clear;
    end
    else
    begin
      FSelectedIndex := EnsureRange(TagValue, 0, High(FEntries));
      FSelectedIndices.Clear;
      FSelectedIndices.Add(FSelectedIndex);
      FSelectionAnchor := FSelectedIndex;
    end;
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
  for I := 0 to FList.Count - 1 do
  begin
    Item := FList.ListItems[I];
    Item.StyledSettings := Item.StyledSettings - [TStyledSetting.FontColor];
    Item.TextSettings.FontColor := FColText;
    Item.IsSelected := (Item.Tag = FSelectedIndex)
      or FSelectedIndices.Contains(Item.Tag);
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
  if FList <> nil then
    FList.StyleLookup := ScopedStyle('listboxstyle');
  FillList;
end;

procedure TnbFilePane.SetStyleLookupPrefix(const AValue: string);
begin
  if FStyleLookupPrefix = AValue then Exit;
  FStyleLookupPrefix := AValue;
  ApplyStyleLookups;
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
  if FBusyShade <> nil then
    FBusyShade.Fill.Color := ABg;
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

initialization
  RegisterFmxClasses([TnbFilePane]);

end.
