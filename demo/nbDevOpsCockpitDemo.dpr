program nbDevOpsCockpitDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  uDemoMain in 'uDemoMain.pas' {DemoForm};

{$R *.res}

begin
  GlobalUseSkia := True;
  Application.Initialize;
  Application.CreateForm(TDemoForm, DemoForm);
  Application.Run;
end.
