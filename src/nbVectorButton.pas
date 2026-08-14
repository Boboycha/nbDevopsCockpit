unit nbVectorButton;

interface

uses
  System.Classes, System.SysUtils, System.UITypes,
  FMX.StdCtrls,
  nbVectorIcons;

type
  TnbVectorButton = class(TButton)
  private
    FIcon: TnbVectorIcon;
    FIconName: string;
    FIconColor: TAlphaColor;
    FIconSize: Single;
    FIconMargin: Single;
    procedure SetIconName(const AValue: string);
    procedure SetIconColor(const AValue: TAlphaColor);
    procedure SetIconSize(const AValue: Single);
    procedure SetIconMargin(const AValue: Single);
    procedure LayoutIcon;
    procedure UpdateIconColor;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property IconName: string read FIconName write SetIconName;
    property IconColor: TAlphaColor read FIconColor write SetIconColor
      default TAlphaColors.Null;
    property IconSize: Single read FIconSize write SetIconSize;
    property IconMargin: Single read FIconMargin write SetIconMargin;
  end;

implementation

uses
  System.Math;

constructor TnbVectorButton.Create(AOwner: TComponent);
begin
  inherited;
  FIconColor := TAlphaColors.Null;
  FIconSize := 18;
  FIconMargin := 8;
  FIcon := TnbVectorIcon.Create(Self);
  FIcon.Parent := Self;
  FIcon.Stored := False;
  FIcon.HitTest := False;
  FIcon.Locked := True;
end;

procedure TnbVectorButton.LayoutIcon;
var
  IconExtent: Single;
begin
  if FIcon = nil then
    Exit;
  IconExtent := Min(FIconSize, Min(Width, Height));
  if IconExtent < 0 then
    IconExtent := 0;
  if Text = '' then
    FIcon.SetBounds((Width - IconExtent) / 2, (Height - IconExtent) / 2,
      IconExtent, IconExtent)
  else
    FIcon.SetBounds(FIconMargin, (Height - IconExtent) / 2,
      IconExtent, IconExtent);
end;

procedure TnbVectorButton.Paint;
begin
  UpdateIconColor;
  LayoutIcon;
  inherited;
end;

procedure TnbVectorButton.Resize;
begin
  inherited;
  LayoutIcon;
end;

procedure TnbVectorButton.SetIconColor(const AValue: TAlphaColor);
begin
  if FIconColor = AValue then
    Exit;
  FIconColor := AValue;
  UpdateIconColor;
  Repaint;
end;

procedure TnbVectorButton.SetIconMargin(const AValue: Single);
begin
  if SameValue(FIconMargin, AValue) then
    Exit;
  FIconMargin := Max(0, AValue);
  LayoutIcon;
  Repaint;
end;

procedure TnbVectorButton.SetIconName(const AValue: string);
begin
  if FIconName = AValue then
    Exit;
  FIconName := AValue;
  if FIcon <> nil then
  begin
    FIcon.IconName := AValue;
    FIcon.Visible := AValue <> '';
  end;
  Repaint;
end;

procedure TnbVectorButton.SetIconSize(const AValue: Single);
begin
  if SameValue(FIconSize, AValue) then
    Exit;
  FIconSize := Max(0, AValue);
  LayoutIcon;
  Repaint;
end;

procedure TnbVectorButton.UpdateIconColor;
begin
  if FIcon = nil then
    Exit;
  if FIconColor <> TAlphaColors.Null then
    FIcon.IconColor := FIconColor
  else if ResultingTextSettings <> nil then
    FIcon.IconColor := ResultingTextSettings.FontColor;
end;

end.