unit nbFilePane.Controls;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes,
  FMX.Controls, FMX.StdCtrls,
  nbFileSources;

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
  TnbToolButton = class(TSpeedButton)
  private
    procedure SetGlyphText(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
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

function FormatFileSize(ASize: Int64): string;
begin
  if ASize < 1024 then
    Result := ASize.ToString + ' Б'
  else if ASize < 1024 * 1024 then
    Result := Format('%.1f КБ', [ASize / 1024])
  else
    Result := Format('%.1f МБ', [ASize / 1024 / 1024]);
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
    FILE_SORT_DATE: Result := 'Date Modified';
    FILE_SORT_SIZE: Result := 'Size';
    FILE_SORT_KIND: Result := 'Kind';
  else
    Result := 'Name';
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

end.
