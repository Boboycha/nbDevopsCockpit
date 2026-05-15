program Project1;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  uMain in 'uMain.pas' {Form1};

{$R *.res}

begin
  GlobalUseSkia := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
