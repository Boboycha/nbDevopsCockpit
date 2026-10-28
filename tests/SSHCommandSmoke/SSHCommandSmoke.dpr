program SSHCommandSmoke;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  ModernSSHClient;

type
  TCommandProbe = class
  private
    FClient: TnbSSHClient;
    FCompletedCount: Integer;
    FDone: Boolean;
    procedure CommandCompleted(Sender: TObject; AExitStatus: Integer);
    procedure Check(ACondition: Boolean; const AMessage: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

constructor TCommandProbe.Create;
begin
  inherited;
  FClient := TnbSSHClient.Create(nil);
  FClient.OnCommandCompleted := CommandCompleted;
  FClient.KeyPath := TPath.Combine(TPath.GetTempPath,
    'nbdevopscockpit-missing-' + TGUID.NewGuid.ToString);
end;

destructor TCommandProbe.Destroy;
begin
  FClient.Free;
  inherited;
end;

procedure TCommandProbe.Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure TCommandProbe.CommandCompleted(Sender: TObject;
  AExitStatus: Integer);
begin
  Inc(FCompletedCount);
  Check(AExitStatus = -1,
    'Failed command must preserve the unknown exit status');
  Check(FClient.Status = ssIdle,
    'Client must be idle before OnCommandCompleted');

  if FCompletedCount = 1 then
  begin
    FClient.KeyPath := TPath.Combine(TPath.GetTempPath,
      'nbdevopscockpit-missing-' + TGUID.NewGuid.ToString);
    FClient.ExecuteCommand('second command');
  end
  else
    FDone := True;
end;

procedure TCommandProbe.Run;
var
  StartedAt: UInt64;
begin
  Check(FClient.CommandOutputLimitBytes = 16 * 1024 * 1024,
    'Unexpected default command output limit');

  FClient.ExecuteCommand('first command');
  StartedAt := TThread.GetTickCount64;
  while not FDone and (TThread.GetTickCount64 - StartedAt < 5000) do
  begin
    CheckSynchronize(10);
    Sleep(1);
  end;

  Check(FDone, 'Command completion reentrancy timed out');
  Check(FCompletedCount = 2, 'Expected two command completion events');
  Check(FClient.Status = ssIdle, 'Client did not return to idle');
end;

var
  Probe: TCommandProbe;

begin
  Probe := TCommandProbe.Create;
  try
    Probe.Run;
    Writeln('SSHCommandSmoke: PASS');
  finally
    Probe.Free;
  end;
end.
