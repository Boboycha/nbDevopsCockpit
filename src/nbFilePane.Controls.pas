unit nbFilePane.Controls;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes,
  FMX.Controls, FMX.StdCtrls, FMX.Graphics, FMX.Objects,
  nbFileSources, nbVectorIcons;

const
  FILE_ICON_UP         = 'up';
  FILE_ICON_REFRESH    = 'refresh';
  FILE_ICON_NEW_FOLDER = 'plus';
  FILE_ICON_RENAME     = 'rename';
  FILE_ICON_DELETE     = 'delete';
  FILE_ICON_UPLOAD     = 'upload';
  FILE_ICON_DOWNLOAD   = 'download';
  FILE_ICON_TRANSFER   = 'transfer';
  FILE_ICON_FOLDER     = 'folder';
  FILE_ICON_DOCUMENT   = 'file';

  FILE_ROW_HEIGHT      = 42;
  FILE_HEADER_HEIGHT   = 34;
  FILE_COL_DATE_WIDTH  = 104;
  FILE_COL_SIZE_WIDTH  = 74;
  FILE_COL_KIND_WIDTH  = 92;
  FILE_MUTED_TEXT      = TAlphaColor($FF78949B);
  FILE_ICON_BLUE       = TAlphaColor($FF29C7B7);
  FILE_ROW_LINE        = TAlphaColor($1F2B4A51);

  FILE_SORT_NAME       = 0;
  FILE_SORT_DATE       = 1;
  FILE_SORT_SIZE       = 2;
  FILE_SORT_KIND       = 3;

type
  TnbToolButton = class(TSpeedButton)
  private
    FIcon: TnbVectorIcon;
    FLocalBg: TAlphaColor;
    FLocalBorder: TAlphaColor;
    FLocalText: TAlphaColor;
    procedure HandleApplyStyleLookup(Sender: TObject);
    procedure HandleMouseEnter(Sender: TObject);
    procedure HandleMouseLeave(Sender: TObject);
    procedure PaintLocalChrome;
    procedure SetGlyphText(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    procedure ApplyLocalChrome(ABg, ABorder, AText: TAlphaColor);
    procedure SetGlyphColor(AColor: TAlphaColor);
    property Glyph: string write SetGlyphText;
  end;

function FileToolIconFor(const AGlyph, AHint: string): string;
function FormatFileSize(ASize: Int64): string;
function FormatFileModified(ADate: TDateTime): string;
function FormatFilePermissions(APermissions: Cardinal; AIsDir: Boolean): string;
function FileEntryKind(const AEntry: TnbFileEntry): string;
function FileHeaderBaseCaption(AColumn: Integer): string;
function FileHeaderCaption(const AText: string; AColumn, ASortColumn: Integer;
  ASortDescending: Boolean): string;

implementation

uses
  System.StrUtils, FMX.Types;

function FileToolIconFor(const AGlyph, AHint: string): string;
begin
  if ContainsText(AHint, 'вверх') or (AGlyph = #$2191) then
    Exit(FILE_ICON_UP);
  if ContainsText(AHint, 'обнов') or SameText(AGlyph, 'R') then
    Exit(FILE_ICON_REFRESH);
  if ContainsText(AHint, 'новый файл') or ContainsText(AHint, 'new file')
    or SameText(AGlyph, 'F') then
    Exit(FILE_ICON_DOCUMENT);
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

  Result := nbIconNameFor('', AGlyph, AHint);
end;

function FormatFileSize(ASize: Int64): string;
begin
  if ASize < 1024 then
    Result := ASize.ToString + ' B'
  else if ASize < 1024 * 1024 then
    Result := Format('%.1f KB', [ASize / 1024])
  else
    Result := Format('%.1f MB', [ASize / 1024 / 1024]);
end;

function FormatFileModified(ADate: TDateTime): string;
begin
  if ADate <= 0 then
    Exit('');
  Result := FormatDateTime('m/d/yyyy, h:nn AM/PM', ADate);
end;

function FormatFilePermissions(APermissions: Cardinal; AIsDir: Boolean): string;

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

function FileEntryKind(const AEntry: TnbFileEntry): string;
begin
  if AEntry.IsDir then
    Result := 'folder'
  else
    Result := 'file';
end;

function FileHeaderBaseCaption(AColumn: Integer): string;
begin
  case AColumn of
    FILE_SORT_DATE: Result := 'MODIFIED';
    FILE_SORT_SIZE: Result := 'SIZE';
    FILE_SORT_KIND: Result := 'KIND';
  else
    Result := 'NAME';
  end;
end;

function FileHeaderCaption(const AText: string; AColumn, ASortColumn: Integer;
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

{ TnbToolButton }

constructor TnbToolButton.Create(AOwner: TComponent);
begin
  inherited;
  Align := TAlignLayout.Left;
  Width := 30;
  Margins.Rect := RectF(0, 3, 6, 3);
  Text := '';
  StyledSettings := StyledSettings - [TStyledSetting.FontColor];
  FLocalBg := TAlphaColor($FF141820);
  FLocalBorder := TAlphaColor($FF344056);
  FLocalText := TAlphaColor($FFCCD4DE);
  FIcon := TnbVectorIcon.Create(Self);
  FIcon.Parent := Self;
  FIcon.Align := TAlignLayout.Client;
  FIcon.Margins.Rect := RectF(7, 7, 7, 7);
  FIcon.IconColor := FLocalText;
  FIcon.HitTest := False;
  OnApplyStyleLookup := HandleApplyStyleLookup;
  OnMouseEnter := HandleMouseEnter;
  OnMouseLeave := HandleMouseLeave;
end;

procedure TnbToolButton.HandleApplyStyleLookup(Sender: TObject);
begin
  PaintLocalChrome;
end;

procedure TnbToolButton.HandleMouseEnter(Sender: TObject);
begin
  Opacity := 1.0;
  PaintLocalChrome;
end;

procedure TnbToolButton.HandleMouseLeave(Sender: TObject);
begin
  Opacity := 1.0;
  PaintLocalChrome;
end;

procedure TnbToolButton.PaintLocalChrome;
var
  Obj: TFmxObject;
  Shape: TShape;

  procedure PaintShape(const AName: string);
  begin
    Obj := FindStyleResource(AName);
    if Obj is TShape then
    begin
      Shape := TShape(Obj);
      Shape.Fill.Kind := TBrushKind.Solid;
      Shape.Fill.Color := FLocalBg;
      Shape.Stroke.Kind := TBrushKind.Solid;
      Shape.Stroke.Color := FLocalBorder;
    end;
  end;

begin
  StyledSettings := StyledSettings - [TStyledSetting.FontColor];
  Text := '';
  if FIcon <> nil then
    FIcon.IconColor := FLocalText;
  PaintShape('background');
  PaintShape('bg');
end;

procedure TnbToolButton.ApplyLocalChrome(ABg, ABorder, AText: TAlphaColor);
begin
  FLocalBg := ABg;
  FLocalBorder := ABorder;
  FLocalText := AText;
  PaintLocalChrome;
end;

procedure TnbToolButton.SetGlyphText(const AValue: string);
begin
  Text := '';
  if FIcon <> nil then
    FIcon.IconName := nbIconNameFor('', AValue, Hint);
end;

procedure TnbToolButton.SetGlyphColor(AColor: TAlphaColor);
begin
  FLocalText := AColor;
  StyledSettings := StyledSettings - [TStyledSetting.FontColor];
  Text := '';
  if FIcon <> nil then
    FIcon.IconColor := AColor;
  PaintLocalChrome;
end;

end.
