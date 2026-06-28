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
  if ContainsText(S, 'rename') or ContainsText(H, 'переимен') then
    Exit('rename');
  if ContainsText(S, 'edit') or ContainsText(H, 'редакт') then
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

  // Иконки в духе Lucide/Feather: сетка 24x24, скруглённые углы через кривые Безье
  if N = 'plus' then
    APath.Data := 'M 12 5 L 12 19 M 5 12 L 19 12'
  else if N = 'close' then
    APath.Data := 'M 6 6 L 18 18 M 18 6 L 6 18'
  else if N = 'save' then
    APath.Data := 'M 5 4 L 16 4 L 20 8 L 20 19 C 20 19.55 19.55 20 19 20 L 5 20 ' +
      'C 4.45 20 4 19.55 4 19 L 4 5 C 4 4.45 4.45 4 5 4 Z ' +
      'M 8 4 L 8 9.5 L 15 9.5 L 15 4 M 7 20 L 7 13.5 L 17 13.5 L 17 20'
  else if N = 'delete' then
    APath.Data := 'M 4 7 L 20 7 ' +
      'M 9.5 7 L 9.5 5 C 9.5 4.45 9.95 4 10.5 4 L 13.5 4 C 14.05 4 14.5 4.45 14.5 5 L 14.5 7 ' +
      'M 6 7 L 7 19.1 C 7.04 19.6 7.5 20 8 20 L 16 20 C 16.5 20 16.96 19.6 17 19.1 L 18 7 ' +
      'M 10 10.5 L 10 16.5 M 14 10.5 L 14 16.5'
  else if N = 'edit' then
    APath.Data := 'M 20.3 7.7 L 8 20 L 4 21 L 5 17 L 17.3 4.7 ' +
      'C 17.7 4.3 18.3 4.3 18.7 4.7 L 20.3 6.3 C 20.7 6.7 20.7 7.3 20.3 7.7 Z ' +
      'M 15 7 L 18 10'
  else if N = 'rename' then
  begin
    AFill := True;
    APath.Data := 'M 10 4 L 8 4 L 8 6 L 5 6 C 3.34315 6 2 7.34315 2 9 L 2 15 ' +
      'C 2 16.6569 3.34315 18 5 18 L 8 18 L 8 20 L 10 20 L 10 4 Z ' +
      'M 8 8 L 8 16 L 5 16 C 4.44772 16 4 15.5523 4 15 L 4 9 ' +
      'C 4 8.44772 4.44772 8 5 8 L 8 8 Z ' +
      'M 19 16 L 12 16 L 12 18 L 19 18 C 20.6569 18 22 16.6569 22 15 L 22 9 ' +
      'C 22 7.34315 20.6569 6 19 6 L 12 6 L 12 8 L 19 8 ' +
      'C 19.5523 8 20 8.44771 20 9 L 20 15 C 20 15.5523 19.5523 16 19 16 Z'
  end
  else if N = 'copy' then
    APath.Data := 'M 10 9 L 19 9 C 19.55 9 20 9.45 20 10 L 20 19 C 20 19.55 19.55 20 19 20 L 10 20 ' +
      'C 9.45 20 9 19.55 9 19 L 9 10 C 9 9.45 9.45 9 10 9 Z ' +
      'M 5.5 15 L 5 15 C 4.45 15 4 14.55 4 14 L 4 5 C 4 4.45 4.45 4 5 4 L 14 4 C 14.55 4 15 4.45 15 5 L 15 5.5'
  else if N = 'paste' then
    APath.Data := 'M 9.5 3.5 L 14.5 3.5 C 15.05 3.5 15.5 3.95 15.5 4.5 L 15.5 5.5 ' +
      'C 15.5 6.05 15.05 6.5 14.5 6.5 L 9.5 6.5 C 8.95 6.5 8.5 6.05 8.5 5.5 L 8.5 4.5 C 8.5 3.95 8.95 3.5 9.5 3.5 Z ' +
      'M 15.5 5 L 17 5 C 17.55 5 18 5.45 18 6 L 18 19.5 C 18 20.05 17.55 20.5 17 20.5 L 7 20.5 ' +
      'C 6.45 20.5 6 20.05 6 19.5 L 6 6 C 6 5.45 6.45 5 7 5 L 8.5 5'
  else if N = 'play' then
  begin
    AFill := True;
    APath.Data := 'M 8.5 5.5 L 19 12 L 8.5 18.5 Z';
  end
  else if N = 'back' then
    APath.Data := 'M 20 12 L 4 12 M 10 6 L 4 12 L 10 18'
  else if N = 'refresh' then
    APath.Data := 'M 21 12 A 9 9 0 1 1 12 3 C 14.5 3 16.9 4 18.7 5.7 L 21 8 ' +
      'M 21 3 L 21 8 L 16 8'
  else if N = 'upload' then
    APath.Data := 'M 12 16 L 12 4.5 M 7 9.5 L 12 4.5 L 17 9.5 ' +
      'M 4 17 L 4 19 C 4 19.55 4.45 20 5 20 L 19 20 C 19.55 20 20 19.55 20 19 L 20 17'
  else if N = 'download' then
    APath.Data := 'M 12 4 L 12 15.5 M 7 10.5 L 12 15.5 L 17 10.5 ' +
      'M 4 17 L 4 19 C 4 19.55 4.45 20 5 20 L 19 20 C 19.55 20 20 19.55 20 19 L 20 17'
  else if N = 'transfer' then
    APath.Data := 'M 4 8 L 17 8 M 13.5 4.5 L 17 8 L 13.5 11.5 ' +
      'M 20 16 L 7 16 M 10.5 12.5 L 7 16 L 10.5 19.5'
  else if N = 'key' then
    APath.Data := 'M 4 11.5 A 3.25 3.25 0 1 0 10.5 11.5 A 3.25 3.25 0 1 0 4 11.5 ' +
      'M 10.5 11.5 L 20 11.5 M 16.5 11.5 L 16.5 15 M 20 11.5 L 20 14.5'
  else if N = 'server' then
    APath.Data := 'M 4 5 C 4 4.45 4.45 4 5 4 L 19 4 C 19.55 4 20 4.45 20 5 ' +
      'L 20 14 C 20 14.55 19.55 15 19 15 L 5 15 C 4.45 15 4 14.55 4 14 Z ' +
      'M 9 19 L 15 19 M 12 15 L 12 19'
  else if N = 'folder' then
    APath.Data := 'M 4 6 C 4 5.45 4.45 5 5 5 L 9.6 5 L 11.6 7 L 19 7 C 19.55 7 20 7.45 20 8 ' +
      'L 20 18 C 20 18.55 19.55 19 19 19 L 5 19 C 4.45 19 4 18.55 4 18 Z'
  else if N = 'file' then
    APath.Data := 'M 14.5 3 L 7 3 C 6.45 3 6 3.45 6 4 L 6 20 C 6 20.55 6.45 21 7 21 L 17 21 ' +
      'C 17.55 21 18 20.55 18 20 L 18 6.5 Z M 14.5 3 L 14.5 6.5 L 18 6.5'
  else if N = 'theme' then
    // Палитра художника: контур с выемкой под большой палец + 4 лунки краски
    APath.Data := 'M 12 21.5 A 9.5 9.5 0 1 1 21.5 12 C 21.5 13.65 20.15 15 18.5 15 ' +
      'L 16.5 15 C 15.4 15 14.5 15.9 14.5 17 C 14.5 17.5 14.7 17.95 15 18.35 ' +
      'C 15.3 18.75 15.5 19.2 15.5 19.7 C 15.5 20.7 14.7 21.5 13.7 21.5 Z ' +
      'M 12.5 6.5 A 1 1 0 1 0 14.5 6.5 A 1 1 0 1 0 12.5 6.5 ' +
      'M 16.5 10.5 A 1 1 0 1 0 18.5 10.5 A 1 1 0 1 0 16.5 10.5 ' +
      'M 7.5 7.5 A 1 1 0 1 0 9.5 7.5 A 1 1 0 1 0 7.5 7.5 ' +
      'M 5.5 12.5 A 1 1 0 1 0 7.5 12.5 A 1 1 0 1 0 5.5 12.5'
  else if N = 'broadcast' then
    // Fan-out "один-ко-многим": узел-источник слева, три ветки к узлам справа
    APath.Data := 'M 3 12 A 2 2 0 1 0 7 12 A 2 2 0 1 0 3 12 ' +
      'M 17 5 A 2 2 0 1 0 21 5 A 2 2 0 1 0 17 5 ' +
      'M 17 12 A 2 2 0 1 0 21 12 A 2 2 0 1 0 17 12 ' +
      'M 17 19 A 2 2 0 1 0 21 19 A 2 2 0 1 0 17 19 ' +
      'M 7 12 L 17 12 M 6.8 11.1 L 17.2 5.9 M 6.8 12.9 L 17.2 18.1'
  else if N = 'focus' then
    APath.Data := 'M 5 10 L 5 5 L 10 5 M 14 5 L 19 5 L 19 10 M 19 14 L 19 19 L 14 19 M 10 19 L 5 19 L 5 14'
  else if N = 'scripts' then
    APath.Data := 'M 8 7 L 3.5 12 L 8 17 M 16 7 L 20.5 12 L 16 17 M 13.5 5.5 L 10.5 18.5'
  else if N = 'select' then
    APath.Data := 'M 4.5 12.5 L 9.5 17.5 L 19.5 6.5'
  else if N = 'up' then
    APath.Data := 'M 12 19 L 12 5 M 6 11 L 12 5 L 18 11'
  else
  begin
    AFill := True;
    APath.Data := 'M 12 9.5 A 2.5 2.5 0 1 0 12 14.5 A 2.5 2.5 0 1 0 12 9.5';
  end;
end;

{ TnbVectorIcon }

constructor TnbVectorIcon.Create(AOwner: TComponent);
begin
  inherited;
  FIconColor := TAlphaColors.White;
  FStrokeWidth := 1.4;
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
    // Скруглённые концы и стыки — иначе тонкие штрихи выглядят "рублеными"
    Canvas.Stroke.Cap := TStrokeCap.Round;
    Canvas.Stroke.Join := TStrokeJoin.Round;
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
