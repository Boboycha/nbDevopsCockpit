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
  FMX.Objects,
  nbSFTPClient;

type
  TnbFilePane = class;

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
    FPathBox: TRectangle;
    FPathText: TText;
    FListHost: TRectangle;
    FList: TVertScrollBox;
    FListContent: TLayout;
    FScrollTrack: TRectangle;
    FScrollThumb: TRectangle;
    FSelectedIndex: Integer;
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
  FScrollDragging: Boolean;
  FScrollDragStartY: Single;
  FScrollDragStartViewportY: Single;

    class var FInstances: TList<TnbFilePane>;
    class var FDragSource: TnbFilePane;
    class var FDragTarget: TnbFilePane;

    class function PaneAtScreenPoint(const APoint: TPointF): TnbFilePane; static;
    class procedure ClearDropIndicator; static;
    class procedure SetDraggingCursor(AEnabled: Boolean); static;
    function AddButton(const AGlyph: string; AOnClick: TNotifyEvent;
      const AHint: string): TnbToolButton;
    procedure BuildUi;
    procedure PaintStyleTree(AObject: TFmxObject);
    procedure SetDropIndicatorVisible(AVisible: Boolean);
    procedure SelectIndex(AIndex: Integer);
    procedure EnsureSelectedVisible;
    procedure UpdateScrollThumb;
    procedure FillList;
    procedure HandleListViewportChanged(Sender: TObject;
      const OldViewportPosition, NewViewportPosition: TPointF;
      const ContentSizeChanged: Boolean);
    procedure HandleListResize(Sender: TObject);
    procedure HandleScrollMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
    procedure HandleScrollMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Single);
    procedure HandleScrollMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Single);
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
  System.Math, FMX.Dialogs, FMX.Forms;

type
  TControlAccess = class(TControl);

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
  if FInstances = nil then
    FInstances := TList<TnbFilePane>.Create;
  FInstances.Add(Self);
  FButtons := TList<TnbToolButton>.Create;
  FSelectedIndex := -1;
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
  I, J, K: Integer;
  Pane: TnbFilePane;
  C: TCursor;
  Obj, Child: TFmxObject;
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
      Pane.FList.Cursor := C;
    if Pane.FListContent <> nil then
    begin
      Pane.FListContent.Cursor := C;
      for J := 0 to Pane.FListContent.ChildrenCount - 1 do
      begin
        Obj := Pane.FListContent.Children[J];
        if Obj is TControl then
          TControl(Obj).Cursor := C;
        if Obj is TFmxObject then
          for K := 0 to TFmxObject(Obj).ChildrenCount - 1 do
          begin
            Child := TFmxObject(Obj).Children[K];
            if Child is TControl then
              TControl(Child).Cursor := C;
          end;
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

  FPathBox := TRectangle.Create(Self);
  FPathBox.Parent := Self;
  FPathBox.Align := TAlignLayout.Top;
  FPathBox.Position.Y := 100;
  FPathBox.Height := 28;
  FPathBox.Margins.Rect := RectF(4, 2, 4, 2);
  FPathBox.XRadius := 3;
  FPathBox.YRadius := 3;
  FPathBox.Stroke.Kind := TBrushKind.Solid;

  FPathText := TText.Create(FPathBox);
  FPathText.Parent := FPathBox;
  FPathText.Align := TAlignLayout.Client;
  FPathText.Margins.Rect := RectF(6, 0, 6, 0);
  FPathText.HitTest := False;
  FPathText.TextSettings.HorzAlign := TTextAlign.Leading;
  FPathText.TextSettings.VertAlign := TTextAlign.Center;

  FListHost := TRectangle.Create(Self);
  FListHost.Parent := Self;
  FListHost.Align := TAlignLayout.Client;
  FListHost.Margins.Rect := RectF(4, 0, 4, 4);
  FListHost.ClipChildren := True;
  FListHost.HitTest := True;
  FListHost.Fill.Kind := TBrushKind.None;
  FListHost.Stroke.Kind := TBrushKind.Solid;
  FListHost.Stroke.Color := FColBorder;
  FListHost.Stroke.Thickness := 1;
  FListHost.XRadius := 3;
  FListHost.YRadius := 3;
  FListHost.OnDragOver := HandleDragOver;
  FListHost.OnDragDrop := HandleDragDrop;

  FList := TVertScrollBox.Create(FListHost);
  FList.Parent := FListHost;
  FList.Align := TAlignLayout.Client;
  FList.Margins.Rect := RectF(1, 1, 9, 1);
  FList.ShowScrollBars := False;
  FList.ClipChildren := True;
  FList.HitTest := True;
  FList.OnDragOver := HandleDragOver;
  FList.OnDragDrop := HandleDragDrop;
  FList.OnViewportPositionChange := HandleListViewportChanged;
  FList.OnResize := HandleListResize;

  FListContent := TLayout.Create(FList);
  FListContent.Parent := FList;
  FListContent.Align := TAlignLayout.Top;
  FListContent.Height := 0;
  FListContent.HitTest := True;
  FListContent.OnDragOver := HandleDragOver;
  FListContent.OnDragDrop := HandleDragDrop;

  FScrollTrack := TRectangle.Create(FListHost);
  FScrollTrack.Parent := FListHost;
  FScrollTrack.Align := TAlignLayout.Right;
  FScrollTrack.Width := 7;
  FScrollTrack.Margins.Rect := RectF(0, 7, 2, 7);
  FScrollTrack.XRadius := 3;
  FScrollTrack.YRadius := 3;
  FScrollTrack.Stroke.Kind := TBrushKind.None;
  FScrollTrack.HitTest := True;
  FScrollTrack.OnMouseDown := HandleScrollMouseDown;
  FScrollTrack.OnMouseMove := HandleScrollMouseMove;
  FScrollTrack.OnMouseUp := HandleScrollMouseUp;
  FScrollTrack.BringToFront;

  FScrollThumb := TRectangle.Create(FScrollTrack);
  FScrollThumb.Parent := FScrollTrack;
  FScrollThumb.Align := TAlignLayout.None;
  FScrollThumb.Position.X := 1;
  FScrollThumb.Width := 5;
  FScrollThumb.Height := 24;
  FScrollThumb.XRadius := 3;
  FScrollThumb.YRadius := 3;
  FScrollThumb.Stroke.Kind := TBrushKind.None;
  FScrollThumb.HitTest := True;
  FScrollThumb.OnMouseDown := HandleScrollMouseDown;
  FScrollThumb.OnMouseMove := HandleScrollMouseMove;
  FScrollThumb.OnMouseUp := HandleScrollMouseUp;

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
  FPathText.Text := APath;
  FEntries := AEntries;
  FSelectedIndex := -1;
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
var
  ViewHeight, ContentHeight, TrackHeight: Single;
  ThumbHeight, MaxThumbTop, MaxScrollY: Single;
begin
  if (FList = nil) or (FListContent = nil)
    or (FScrollTrack = nil) or (FScrollThumb = nil) then Exit;

  ViewHeight := FList.Height;
  ContentHeight := FListContent.Height;
  TrackHeight := FScrollTrack.Height;
  if (ViewHeight <= 0) or (ContentHeight <= ViewHeight) or (TrackHeight <= 0) then
  begin
    FScrollTrack.Visible := False;
    Exit;
  end;

  FScrollTrack.Visible := True;
  ThumbHeight := TrackHeight * ViewHeight / ContentHeight;
  if ThumbHeight < 24 then
    ThumbHeight := 24;
  if ThumbHeight > TrackHeight then
    ThumbHeight := TrackHeight;

  MaxThumbTop := TrackHeight - ThumbHeight;
  MaxScrollY := ContentHeight - ViewHeight;
  FScrollThumb.Height := ThumbHeight;
  if MaxScrollY > 0 then
    FScrollThumb.Position.Y := MaxThumbTop * FList.ViewportPosition.Y / MaxScrollY
  else
    FScrollThumb.Position.Y := 0;
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
var
  RowTop, RowBottom, ViewTop, ViewBottom, MaxScrollY: Single;
begin
  if (FSelectedIndex < 0) or (FList = nil) or (FListContent = nil) then Exit;

  RowTop := FSelectedIndex * 22;
  RowBottom := RowTop + 22;
  ViewTop := FList.ViewportPosition.Y;
  ViewBottom := ViewTop + FList.Height;
  MaxScrollY := Max(0, FListContent.Height - FList.Height);

  if RowTop < ViewTop then
    FList.ViewportPosition := PointF(FList.ViewportPosition.X,
      EnsureRange(RowTop, 0, MaxScrollY))
  else if RowBottom > ViewBottom then
    FList.ViewportPosition := PointF(FList.ViewportPosition.X,
      EnsureRange(RowBottom - FList.Height, 0, MaxScrollY));

  UpdateScrollThumb;
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

procedure TnbFilePane.HandleScrollMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  TrackY, MaxThumbTop, MaxScrollY: Single;
  ScreenPt, TrackPt: TPointF;
begin
  if CanFocus then
    SetFocus;
  if Button <> TMouseButton.mbLeft then Exit;
  if (FList = nil) or (FListContent = nil)
    or (FScrollTrack = nil) or (FScrollThumb = nil) then Exit;
  if FListContent.Height <= FList.Height then Exit;

  ScreenPt := TControl(Sender).LocalToScreen(PointF(X, Y));
  TrackPt := FScrollTrack.ScreenToLocal(ScreenPt);
  if Sender = FScrollTrack then
  begin
    TrackY := TrackPt.Y - FScrollThumb.Height / 2;
    MaxThumbTop := FScrollTrack.Height - FScrollThumb.Height;
    MaxScrollY := FListContent.Height - FList.Height;
    if (MaxThumbTop > 0) and (MaxScrollY > 0) then
      FList.ViewportPosition := PointF(FList.ViewportPosition.X,
        EnsureRange(TrackY / MaxThumbTop * MaxScrollY, 0, MaxScrollY));
  end;

  FScrollDragging := True;
  FScrollDragStartY := ScreenPt.Y;
  FScrollDragStartViewportY := FList.ViewportPosition.Y;
  TControlAccess(TControl(Sender)).Capture;
  UpdateScrollThumb;
end;

procedure TnbFilePane.HandleScrollMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Single);
var
  ScreenPt: TPointF;
  DeltaY, MaxThumbTop, MaxScrollY: Single;
begin
  if not FScrollDragging then Exit;
  if not (ssLeft in Shift) then Exit;
  if (FList = nil) or (FListContent = nil)
    or (FScrollTrack = nil) or (FScrollThumb = nil) then Exit;

  MaxThumbTop := FScrollTrack.Height - FScrollThumb.Height;
  MaxScrollY := FListContent.Height - FList.Height;
  if (MaxThumbTop <= 0) or (MaxScrollY <= 0) then Exit;

  ScreenPt := TControl(Sender).LocalToScreen(PointF(X, Y));
  DeltaY := ScreenPt.Y - FScrollDragStartY;
  FList.ViewportPosition := PointF(FList.ViewportPosition.X,
    EnsureRange(FScrollDragStartViewportY + DeltaY / MaxThumbTop * MaxScrollY,
      0, MaxScrollY));
  UpdateScrollThumb;
end;

procedure TnbFilePane.HandleScrollMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Button = TMouseButton.mbLeft then
    FScrollDragging := False;
end;

procedure TnbFilePane.FillList;
var
  I: Integer;
  Row: TRectangle;
  Text: TText;
  Caption: string;
begin
  FList.BeginUpdate;
  try
    FListContent.DeleteChildren;
    FListContent.Height := 0;
    for I := 0 to High(FEntries) do
    begin
      if FEntries[I].IsDir then
        Caption := '[D] ' + FEntries[I].Name
      else
        Caption := FEntries[I].Name + '   ' + FormatSize(FEntries[I].Size);

      Row := TRectangle.Create(FListContent);
      Row.Parent := FListContent;
      Row.Align := TAlignLayout.Top;
      Row.Height := 22;
      Row.Tag := I;
      Row.HitTest := True;
      Row.Stroke.Kind := TBrushKind.None;
      Row.Fill.Kind := TBrushKind.Solid;
      Row.Fill.Color := FColBg;
      Row.OnMouseDown := HandleRowMouseDown;
      Row.OnMouseMove := HandleRowMouseMove;
      Row.OnMouseUp := HandleRowMouseUp;
      Row.OnDblClick := HandleRowDblClick;
      Row.OnDragEnd := HandleDragEnd;
      Row.OnDragOver := HandleDragOver;
      Row.OnDragDrop := HandleDragDrop;
      Row.DragMode := TDragMode.dmManual;

      Text := TText.Create(Row);
      Text.Parent := Row;
      Text.Align := TAlignLayout.Client;
      Text.Margins.Rect := RectF(6, 0, 6, 0);
      Text.HitTest := True;
      Text.Tag := I;
      Text.Text := Caption;
      Text.TextSettings.HorzAlign := TTextAlign.Leading;
      Text.TextSettings.VertAlign := TTextAlign.Center;
      Text.TextSettings.FontColor := FColText;
      Text.OnMouseDown := HandleRowMouseDown;
      Text.OnMouseMove := HandleRowMouseMove;
      Text.OnMouseUp := HandleRowMouseUp;
      Text.OnDblClick := HandleRowDblClick;
      Text.OnDragEnd := HandleDragEnd;
      Text.OnDragOver := HandleDragOver;
      Text.OnDragDrop := HandleDragDrop;
      Text.DragMode := TDragMode.dmManual;

      FListContent.Height := FListContent.Height + Row.Height;
    end;
  finally
    FList.EndUpdate;
  end;
  UpdateScrollThumb;
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
  end;
  UpdateRowSelection;
end;

procedure TnbFilePane.UpdateRowSelection;
var
  I: Integer;
  Row: TRectangle;
begin
  if FListContent = nil then Exit;
  for I := 0 to FListContent.ChildrenCount - 1 do
    if FListContent.Children[I] is TRectangle then
    begin
      Row := TRectangle(FListContent.Children[I]);
      if Row.Tag = FSelectedIndex then
        Row.Fill.Color := FSelectionColor
      else
        Row.Fill.Color := FColBg;
      Row.Repaint;
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
  FSelectionColor := TAlphaColor($FF000000)
    or ((Round(((ASurface shr 16) and $FF) * 0.70 + ((AText shr 16) and $FF) * 0.30) and $FF) shl 16)
    or ((Round(((ASurface shr 8) and $FF) * 0.70 + ((AText shr 8) and $FF) * 0.30) and $FF) shl 8)
    or (Round((ASurface and $FF) * 0.70 + (AText and $FF) * 0.30) and $FF);
  for I := 0 to FButtons.Count - 1 do
    FButtons[I].SetGlyphColor(AText);
  if FPathBox <> nil then
  begin
    FPathBox.Fill.Kind := TBrushKind.Solid;
    FPathBox.Fill.Color := ABg;
    FPathBox.Stroke.Color := ABorder;
  end;
  if FPathText <> nil then
    FPathText.TextSettings.FontColor := AText;
  if FListHost <> nil then
  begin
    FListHost.Fill.Kind := TBrushKind.None;
    FListHost.Stroke.Kind := TBrushKind.Solid;
    FListHost.Stroke.Color := ABorder;
    FListHost.Stroke.Thickness := 1;
  end;
  if FScrollTrack <> nil then
  begin
    FScrollTrack.Fill.Kind := TBrushKind.Solid;
    FScrollTrack.Fill.Color := ABg;
  end;
  if FScrollThumb <> nil then
  begin
    FScrollThumb.Fill.Kind := TBrushKind.Solid;
    FScrollThumb.Fill.Color := ABorder;
  end;
  UpdateRowSelection;
  UpdateScrollThumb;
end;

end.
