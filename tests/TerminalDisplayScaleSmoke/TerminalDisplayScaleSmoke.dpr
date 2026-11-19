program TerminalDisplayScaleSmoke;

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Platform,
  Terminal.Control
{$IFDEF MACOS}
  , FMX.Platform.Mac
{$ENDIF}
  ;

type
  TProbeTerminal = class(TnbTerminalControl)
  public
    PaintCount: Integer;
    ObservedCanvasScale, ObservedRasterScale: Single;
    procedure Paint; override;
  end;
  TProbeForm = class(TForm)
  public
    Terminal: TProbeTerminal;
    Timer: TTimer;
    Phase, Ticks, Failures: Integer;
    procedure Tick(Sender: TObject);
    procedure MoveToPhase;
    constructor Create(AOwner: TComponent); override;
  end;

var LogFile: TextFile;

procedure Log(const S: string);
begin
  Writeln(LogFile, S); Flush(LogFile);
end;

procedure TProbeTerminal.Paint;
begin
  inherited;
  ObservedCanvasScale := Canvas.Scale;
  ObservedRasterScale := Renderer.Scale;
  Inc(PaintCount);
end;

constructor TProbeForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Terminal display scale regression'; Width := 640; Height := 360;
  Terminal := TProbeTerminal.Create(Self); Terminal.Parent := Self;
  Terminal.Align := TAlignLayout.Client;
  Terminal.WriteText('Synthetic terminal: ABC abc 0123456789'#13#10 +
    '+-------------------+'#13#10 + '| Pixel scale probe |'#13#10 + '+-------------------+');
  Timer := TTimer.Create(Self); Timer.Interval := 500; Timer.OnTimer := Tick;
  MoveToPhase;
end;

procedure TProbeForm.MoveToPhase;
var Index: Integer; R: TRectF;
begin
  // Forward and backward moves cover 1x -> 2x -> 1x on mixed-density displays.
  Index := Phase mod (Screen.DisplayCount * 2);
  if Index >= Screen.DisplayCount then Index := Screen.DisplayCount * 2 - 1 - Index;
  R := Screen.Displays[Index].Workarea;
  Left := Round(R.Left) + 40; Top := Round(R.Top) + 40;
  if Phase >= Screen.DisplayCount * 2 then Terminal.Scale.Point := PointF(1.25, 1.25)
  else Terminal.Scale.Point := PointF(1, 1);
  Terminal.PaintCount := 0; Ticks := 0; Terminal.Repaint;
end;

procedure TProbeForm.Tick(Sender: TObject);
var NativeScale, Expected: Single; ScreenSvc: IFMXScreenService;
begin
  Inc(Ticks); Terminal.Repaint;
  if (Ticks < 3) or (Terminal.PaintCount = 0) then Exit;
  NativeScale := Terminal.ObservedCanvasScale;
{$IFDEF MACOS}
  NativeScale := WindowHandleToPlatform(Handle).Wnd.backingScaleFactor;
{$ENDIF}
  Expected := NativeScale * Max(Abs(Terminal.AbsoluteScale.X), Abs(Terminal.AbsoluteScale.Y));
  Log(Format('phase=%d native=%.2f canvas=%.2f raster=%.2f expected=%.2f',
    [Phase, NativeScale, Terminal.ObservedCanvasScale, Terminal.ObservedRasterScale, Expected]));
  if TPlatformServices.Current.SupportsPlatformService(IFMXScreenService, ScreenSvc) then
    Log(Format('primary_scale=%.2f', [ScreenSvc.GetScreenScale]));
  if not SameValue(Terminal.ObservedCanvasScale, NativeScale, 0.001) or
    not SameValue(Terminal.ObservedRasterScale, Expected, 0.001) then Inc(Failures);
  Inc(Phase);
  if Phase = Screen.DisplayCount * 4 then
  begin
    Timer.Enabled := False;
    Log(Format('RESULT failures=%d displays=%d', [Failures, Screen.DisplayCount]));
    ExitCode := Ord(Failures <> 0); Close;
  end
  else MoveToPhase;
end;

var Form: TProbeForm;
begin
  AssignFile(LogFile, ParamStr(1)); Rewrite(LogFile);
  try
    Application.Initialize;
    Form := TProbeForm.Create(nil); Application.MainForm := Form; Form.Show;
    Application.Run;
  finally CloseFile(LogFile); end;
end.
