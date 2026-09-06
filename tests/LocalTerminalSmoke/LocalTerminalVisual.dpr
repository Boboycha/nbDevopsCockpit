program LocalTerminalVisual;

uses
  System.SysUtils, System.Classes, System.IOUtils,
  FMX.Forms, FMX.Types, FMX.Graphics, FMX.Controls,
  Terminal.Control;

type
  TVisualProbe = class(TForm)
  private
    Terminal: TnbTerminalControl;
    Timer: TTimer;
    Step: Integer;
    procedure Tick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TVisualProbe.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Local terminal visual smoke';
  Width := 900;
  Height := 520;
  Terminal := TnbTerminalControl.Create(Self);
  Terminal.Parent := Self;
  Terminal.Align := TAlignLayout.Client;
  Terminal.FontSize := 16;
  Timer := TTimer.Create(Self);
  Timer.Interval := 1000;
  Timer.OnTimer := Tick;
end;

procedure TVisualProbe.Tick(Sender: TObject);
var
  Bitmap: TBitmap;
begin
  Inc(Step);
  case Step of
    1:
      begin
        Terminal.StartLocalSession;
      end;
    3:
      begin
        {$IFDEF MSWINDOWS}
        Terminal.LocalSession.SendText('Write-Host "LOCAL TERMINAL OK" -ForegroundColor Green' + #13);
        {$ELSE}
        Terminal.LocalSession.SendText('printf "\033[32mLOCAL TERMINAL OK\033[0m\n"' + #13);
        {$ENDIF}
      end;
    5:
      begin
        Width := 760;
        Height := 440;
      end;
    7:
      begin
        Bitmap := Terminal.MakeScreenshot;
        try
          Bitmap.SaveToFile(TPath.Combine(ExtractFilePath(ParamStr(0)), 'local-terminal.png'));
        finally
          Bitmap.Free;
        end;
        Timer.Enabled := False;
        Terminal.StopLocalSession;
        Close;
      end;
  end;
end;

var Form: TVisualProbe;
begin
  Application.Initialize;
  Application.CreateForm(TVisualProbe, Form);
  Application.Run;
end.
