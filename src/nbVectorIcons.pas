unit nbVectorIcons;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes,
  FMX.Controls, FMX.Graphics;

type
  TnbVectorIcon = class(TControl)
  private
    FIconColor: TAlphaColor;
    FIconName: string;
    FStrokeWidth: Single;
    procedure SetIconColor(const AValue: TAlphaColor);
    procedure SetIconName(const AValue: string);
    procedure SetStrokeWidth(const AValue: Single);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property IconName: string read FIconName write SetIconName;
    property IconColor: TAlphaColor read FIconColor write SetIconColor default TAlphaColors.White;
    property StrokeWidth: Single read FStrokeWidth write SetStrokeWidth;
  end;

function nbIconNameFor(const AId, AGlyph, AHint: string): string;

implementation

uses
  System.Math, System.StrUtils;

function CleanText(const AValue: string): string;
begin
  Result := LowerCase(Trim(AValue));
end;

function nbIconNameFor(const AId, AGlyph, AHint: string): string;
var
  S, H: string;
begin
  S := CleanText(AId + ' ' + AGlyph);
  H := CleanText(AHint);

  if ContainsText(S, 'close') or ContainsText(S, 'cancel') or
    ContainsText(H, 'закры') or ContainsText(H, 'отмен') then
    Exit('close');
  if ContainsText(S, 'save') or ContainsText(H, 'сохран') then
    Exit('save');
  if ContainsText(S, 'delete') or ContainsText(H, 'удал') then
    Exit('delete');
  if ContainsText(S, 'edit') or ContainsText(S, 'rename') or
    ContainsText(H, 'редакт') or ContainsText(H, 'переимен') then
    Exit('edit');
  if ContainsText(S, 'copy') or ContainsText(H, 'копир') then
    Exit('copy');
  if ContainsText(S, 'paste') or ContainsText(H, 'встав') then
    Exit('paste');
  if ContainsText(S, 'play') or ContainsText(S, 'run') or
    ContainsText(S, 'connect') or ContainsText(H, 'запуст') or
    ContainsText(H, 'подключ') then
    Exit('play');
  if ContainsText(S, 'back') or ContainsText(H, 'назад') then
    Exit('back');
  if ContainsText(S, 'refresh') or ContainsText(S, 'reload') or
    ContainsText(H, 'обнов') or ContainsText(H, 'перезагруз') then
    Exit('refresh');
  if ContainsText(S, 'upload') or ContainsText(H, 'загруз') then
    Exit('upload');
  if ContainsText(S, 'download') or ContainsText(S, 'import') or
    ContainsText(H, 'скач') or ContainsText(H, 'импорт') then
    Exit('download');
  if ContainsText(S, 'transfer') or ContainsText(H, 'отправ') then
    Exit('transfer');
  if ContainsText(S, 'key') or ContainsText(H, 'ключ') then
    Exit('key');
  if ContainsText(S, 'server') or ContainsText(H, 'сервер') then
    Exit('server');
  if ContainsText(S, 'folder') or ContainsText(H, 'папк') then
    Exit('folder');
  if ContainsText(S, 'file') then
    Exit('file');
  if ContainsText(S, 'theme') then
    Exit('theme');
  if ContainsText(S, 'broadcast') then
    Exit('broadcast');
  if ContainsText(S, 'focus') then
    Exit('focus');
  if ContainsText(S, 'scripts') or ContainsText(S, 'script') then
    Exit('scripts');
  if ContainsText(S, 'select') then
    Exit('select');
  if ContainsText(S, 'sftp') then
    Exit('folder');
  if ContainsText(S, 'plus') or ContainsText(S, 'add') or
    ContainsText(S, 'create') or (Trim(AGlyph) = '+') then
    Exit('plus');
  if (Trim(AGlyph) = '^') or (AGlyph = #$2191) or ContainsText(H, 'вверх') then
    Exit('up');

  Result := CleanText(AGlyph);
  if Result = '' then
    Result := 'dot';
end;

procedure BuildIconPath(const AName: string; APath: TPathData;
  out AFill: Boolean);
var
  N: string;
begin
  APath.Clear;
  AFill := False;
  N := CleanText(AName);

  if N = 'plus' then
    APath.Data := 'M 12 5 L 12 19 M 5 12 L 19 12'
  else if N = 'close' then
    APath.Data := 'M 6 6 L 18 18 M 18 6 L 6 18'
  else if N = 'save' then
    APath.Data := 'M 5 4 L 17 4 L 19 6 L 19 20 L 5 20 Z M 8 4 L 8 10 L 16 10 L 16 4 M 8 16 L 16 16'
  else if N = 'delete' then
    APath.Data := 'M 7 8 L 17 8 M 10 8 L 10 20 M 14 8 L 14 20 M 8 8 L 9 21 L 15 21 L 16 8 M 10 5 L 14 5 L 15 8'
  else if N = 'edit' then
    APath.Data := 'M 5 18 L 5 21 L 8 21 L 19 10 L 16 7 Z M 14 9 L 17 12'
  else if N = 'copy' then
    APath.Data := 'M 8 8 L 18 8 L 18 20 L 8 20 Z M 5 5 L 15 5 L 15 8'
  else if N = 'paste' then
    APath.Data := 'M 8 6 L 16 6 L 16 9 L 8 9 Z M 6 8 L 18 8 L 18 21 L 6 21 Z'
  else if N = 'play' then
  begin
    AFill := True;
    APath.Data := 'M 8 5 L 19 12 L 8 19 Z';
  end
  else if N = 'back' then
    APath.Data := 'M 18 6 L 10 12 L 18 18 M 10 12 L 22 12'
  else if N = 'refresh' then
    APath.Data := 'M 18 8 A 7 7 0 1 0 19 15 M 18 8 L 18 4 L 22 4'
  else if N = 'upload' then
    APath.Data := 'M 12 19 L 12 6 M 6 12 L 12 6 L 18 12 M 5 20 L 19 20'
  else if N = 'download' then
    APath.Data := 'M 12 5 L 12 18 M 6 12 L 12 18 L 18 12 M 5 20 L 19 20'
  else if N = 'transfer' then
    APath.Data := 'M 5 8 L 18 8 M 14 4 L 18 8 L 14 12 M 19 16 L 6 16 M 10 12 L 6 16 L 10 20'
  else if N = 'key' then
    APath.Data := 'M 8 8 C 6 8 5 9 5 11 C 5 13 6 14 8 14 C 10 14 11 13 11 11 C 11 9 10 8 8 8 Z M 11 11 L 20 11 M 17 11 L 17 14 M 20 11 L 20 13'
  else if N = 'server' then
    APath.Data := 'M 6 4 L 18 4 L 18 14 L 6 14 Z M 9 18 L 15 18 M 12 14 L 12 18'
  else if N = 'folder' then
    APath.Data := 'M 4 7 L 10 7 L 12 9 L 20 9 L 20 19 L 4 19 Z'
  else if N = 'file' then
    APath.Data := 'M 7 3 L 15 3 L 19 7 L 19 21 L 7 21 Z M 15 3 L 15 8 L 20 8'
  else if N = 'theme' then
    APath.Data := 'M 12 4 A 8 8 0 1 0 12 20 A 3 3 0 0 1 12 14 L 14 14 A 2 2 0 0 0 14 10 L 12 10 Z'
  else if N = 'broadcast' then
    APath.Data := 'M 5 12 A 7 7 0 0 1 19 12 M 8 12 A 4 4 0 0 1 16 12 M 12 12 L 12 18'
  else if N = 'focus' then
    APath.Data := 'M 5 10 L 5 5 L 10 5 M 14 5 L 19 5 L 19 10 M 19 14 L 19 19 L 14 19 M 10 19 L 5 19 L 5 14'
  else if N = 'scripts' then
    APath.Data := 'M 8 7 L 4 12 L 8 17 M 16 7 L 20 12 L 16 17 M 13 6 L 11 18'
  else if N = 'select' then
    APath.Data := 'M 5 13 L 10 18 L 20 7'
  else if N = 'up' then
    APath.Data := 'M 12 5 L 12 20 M 6 11 L 12 5 L 18 11'
  else
  begin
    AFill := True;
    APath.Data := 'M 12 10 A 2 2 0 1 0 12 14 A 2 2 0 1 0 12 10';
  end;
end;

{ TnbVectorIcon }

constructor TnbVectorIcon.Create(AOwner: TComponent);
begin
  inherited;
  FIconColor := TAlphaColors.White;
  FStrokeWidth := 1.6;
  FIconName := 'dot';
  HitTest := False;
end;

procedure TnbVectorIcon.Paint;
var
  Path: TPathData;
  R: TRectF;
  FillIcon: Boolean;
begin
  inherited;
  if (Width <= 0) or (Height <= 0) then Exit;

  Path := TPathData.Create;
  try
    BuildIconPath(FIconName, Path, FillIcon);
    R := LocalRect;
    R.Inflate(-Max(2.0, FStrokeWidth), -Max(2.0, FStrokeWidth));
    Path.FitToRect(R);

    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := FIconColor;
    Canvas.Stroke.Thickness := FStrokeWidth;
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := FIconColor;
    if FillIcon then
      Canvas.FillPath(Path, AbsoluteOpacity)
    else
      Canvas.DrawPath(Path, AbsoluteOpacity);
  finally
    Path.Free;
  end;
end;

procedure TnbVectorIcon.SetIconColor(const AValue: TAlphaColor);
begin
  if FIconColor = AValue then Exit;
  FIconColor := AValue;
  Repaint;
end;

procedure TnbVectorIcon.SetIconName(const AValue: string);
begin
  if SameText(FIconName, AValue) then Exit;
  FIconName := AValue;
  Repaint;
end;

procedure TnbVectorIcon.SetStrokeWidth(const AValue: Single);
begin
  if SameValue(FStrokeWidth, AValue) then Exit;
  FStrokeWidth := AValue;
  Repaint;
end;

end.
