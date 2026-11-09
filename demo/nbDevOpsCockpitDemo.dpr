program nbDevOpsCockpitDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  uDemoMain in 'uDemoMain.pas' {DemoForm},
  uBridgeDemo in 'uBridgeDemo.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TDemoForm, DemoForm);
  Application.Run;
end.
