unit Terminal.SSHBridge;

interface

uses
  System.Classes,
  ModernSSHClient;

type
  TTerminalSSHDataEvent = procedure(Sender: TObject; const Data: string) of object;
  TTerminalSSHErrorEvent = procedure(Sender: TObject; const ErrorMessage: string) of object;

  TTerminalSSHBridge = class(TComponent)
  private
    FClient: TnbSSHClient;
    FOnConnected: TNotifyEvent;
    FOnError: TTerminalSSHErrorEvent;
    FOnReadData: TTerminalSSHDataEvent;
    procedure SetClient(const AValue: TnbSSHClient);
    procedure HandleStatusChange(Sender: TObject; Status: TSSHStatus);
    procedure HandleReadData(Sender: TObject; const Data: string);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    destructor Destroy; override;

    procedure SendTerminalData(const S: string);
    procedure ResizePTY(Cols, Rows: Integer);
    function Connected: Boolean;

    property Client: TnbSSHClient read FClient write SetClient;
    property OnConnected: TNotifyEvent read FOnConnected write FOnConnected;
    property OnError: TTerminalSSHErrorEvent read FOnError write FOnError;
    property OnReadData: TTerminalSSHDataEvent read FOnReadData write FOnReadData;
  end;

implementation

destructor TTerminalSSHBridge.Destroy;
begin
  SetClient(nil);
  inherited;
end;

procedure TTerminalSSHBridge.SetClient(const AValue: TnbSSHClient);
begin
  if FClient = AValue then Exit;

  if Assigned(FClient) then
  begin
    if not (csDestroying in FClient.ComponentState) then
    begin
      FClient.OnStatusChange := nil;
      FClient.OnReadData := nil;
    end;
    FClient.RemoveFreeNotification(Self);
  end;

  FClient := AValue;

  if Assigned(FClient) then
  begin
    FClient.FreeNotification(Self);
    FClient.OnStatusChange := HandleStatusChange;
    FClient.OnReadData := HandleReadData;
  end;
end;

procedure TTerminalSSHBridge.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FClient) then
    FClient := nil;
end;

procedure TTerminalSSHBridge.HandleStatusChange(Sender: TObject;
  Status: TSSHStatus);
begin
  case Status of
    ssConnected:
      if Assigned(FOnConnected) then
        FOnConnected(Self);
    ssError:
      if Assigned(FOnError) and Assigned(FClient) and
         (FClient.ErrorMessage <> '') then
        FOnError(Self, FClient.ErrorMessage);
  end;
end;

procedure TTerminalSSHBridge.HandleReadData(Sender: TObject; const Data: string);
begin
  if Assigned(FOnReadData) then
    FOnReadData(Self, Data);
end;

procedure TTerminalSSHBridge.SendTerminalData(const S: string);
begin
  if Assigned(FClient) and (FClient.Status = ssConnected) then
    FClient.WriteString(S);
end;

procedure TTerminalSSHBridge.ResizePTY(Cols, Rows: Integer);
begin
  if Assigned(FClient) then
    FClient.ResizePTY(Cols, Rows);
end;

function TTerminalSSHBridge.Connected: Boolean;
begin
  Result := Assigned(FClient) and (FClient.Status = ssConnected);
end;

end.
