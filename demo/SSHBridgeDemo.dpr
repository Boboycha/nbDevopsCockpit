program SSHBridgeDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  uBridgeDemo in 'uBridgeDemo.pas';

{$R *.res}

var
  BridgeForm: TBridgeDemoForm;

begin
  Application.Initialize;
{$IFDEF SSH_BRIDGE_LIFECYCLE_SMOKE}
  BridgeForm := TBridgeDemoForm.Create(nil);
  BridgeForm.Free;
{$ELSE}
  Application.CreateForm(TBridgeDemoForm, BridgeForm);
  Application.Run;
{$ENDIF}
end.
