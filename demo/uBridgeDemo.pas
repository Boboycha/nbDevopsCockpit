unit uBridgeDemo;

interface

uses
  System.Classes, System.SysUtils, System.IOUtils, System.IniFiles,
  System.NetEncoding,
  System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.StdCtrls,
  FMX.Controls.Presentation, FMX.Edit, FMX.Layouts, FMX.TabControl,
  FMX.Dialogs, FMX.DialogService.Sync, FMX.ListBox,
  nbSSH.TunnelManager;

type
  TBridgeDemoForm = class(TForm)
    HeaderPanel: TPanel;
    StartButton: TButton;
    StopButton: TButton;
    StatusLabel: TLabel;
    SessionLabel: TLabel;
    StatisticsLabel: TLabel;
    SpeedLabel: TLabel;
    UptimeLabel: TLabel;
    ErrorLabel: TLabel;
    ConnectionTabs: TTabControl;
    MasterTab: TTabItem;
    MasterScroll: TVertScrollBox;
    MasterHostLabel: TLabel;
    MasterHostEdit: TEdit;
    MasterPortLabel: TLabel;
    MasterPortEdit: TEdit;
    MasterUserLabel: TLabel;
    MasterUserEdit: TEdit;
    MasterPasswordLabel: TLabel;
    MasterPasswordEdit: TEdit;
    MasterKeyLabel: TLabel;
    MasterKeyEdit: TEdit;
    MasterKeyButton: TButton;
    MasterPassphraseLabel: TLabel;
    MasterPassphraseEdit: TEdit;
    MasterFingerprintLabel: TLabel;
    MasterFingerprintEdit: TEdit;
    ReplicaTab: TTabItem;
    ReplicaScroll: TVertScrollBox;
    ReplicaHostLabel: TLabel;
    ReplicaHostEdit: TEdit;
    ReplicaPortLabel: TLabel;
    ReplicaPortEdit: TEdit;
    ReplicaUserLabel: TLabel;
    ReplicaUserEdit: TEdit;
    ReplicaPasswordLabel: TLabel;
    ReplicaPasswordEdit: TEdit;
    ReplicaKeyLabel: TLabel;
    ReplicaKeyEdit: TEdit;
    ReplicaKeyButton: TButton;
    ReplicaPassphraseLabel: TLabel;
    ReplicaPassphraseEdit: TEdit;
    ReplicaFingerprintLabel: TLabel;
    ReplicaFingerprintEdit: TEdit;
    RouteTab: TTabItem;
    RouteScroll: TVertScrollBox;
    ListenHostLabel: TLabel;
    ListenHostEdit: TEdit;
    ListenPortLabel: TLabel;
    ListenPortEdit: TEdit;
    TargetHostLabel: TLabel;
    TargetHostEdit: TEdit;
    TargetPortLabel: TLabel;
    TargetPortEdit: TEdit;
    ThroughputLabel: TLabel;
    ThroughputComboBox: TComboBox;
    MaximumThroughputItem: TListBoxItem;
    BalancedThroughputItem: TListBoxItem;
    CompatibilityThroughputItem: TListBoxItem;
    KeyDialog: TOpenDialog;
    UpdateTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure StartButtonClick(Sender: TObject);
    procedure StopButtonClick(Sender: TObject);
    procedure UpdateTimerTimer(Sender: TObject);
    procedure MasterKeyButtonClick(Sender: TObject);
    procedure ReplicaKeyButtonClick(Sender: TObject);
  private
    FManager: TnbSSHTunnelManager;
    FAcceptedMasterFingerprint: string;
    FAcceptedReplicaFingerprint: string;
    FRateStartTick: UInt64;
    FLastRateTick: UInt64;
    FRateBaseRxBytes: Int64;
    FRateBaseTxBytes: Int64;
    FLastRxBytes: Int64;
    FLastTxBytes: Int64;
    FNextChannelDiagnosticTick: UInt64;
    procedure BridgeError(Sender: TObject; const AMessage: string);
    procedure VerifyHostKey(Sender: TObject; ARole: TnbSSHBridgeRole;
      const AHost, AFingerprint: string; var AAccept: Boolean);
    procedure UpdateState;
    procedure ApplyEndpoint(AEndpoint: TnbSSHBridgeEndpoint; AHost, APort,
      AUser, APassword, AKeyPath, APassphrase, AFingerprint: TEdit);
    procedure SelectKeyFile(AEdit: TEdit);
    function IsEncryptedPrivateKeyFile(const AFileName: string): Boolean;
    function EnsurePassphrase(AKeyEdit, APassphraseEdit: TEdit;
      const ACaption: string): Boolean;
    procedure ApplyThroughputProfile;
    procedure ResetRateMeter;
    procedure UpdateRateMeter;
    function SettingsFileName: string;
    procedure LoadSettings;
    procedure SaveSettings;
    function FormatUptime(AMilliseconds: UInt64): string;
    function DiagnosticLogFileName: string;
    procedure AppendDiagnostic(const ALevel, AMessage: string);
  public
    destructor Destroy; override;
  end;

procedure ShowBridgeDemo;

implementation

{$R *.fmx}

procedure ShowBridgeDemo;
var
  Form: TBridgeDemoForm;
begin
  Form := TBridgeDemoForm.Create(Application);
  Form.Show;
end;

function TBridgeDemoForm.FormatUptime(AMilliseconds: UInt64): string;
var
  TotalSeconds: UInt64;
  Days, Hours, Minutes, Seconds: Integer;
begin
  TotalSeconds := AMilliseconds div 1000;
  Days := TotalSeconds div 86400;
  Hours := (TotalSeconds div 3600) mod 24;
  Minutes := (TotalSeconds div 60) mod 60;
  Seconds := TotalSeconds mod 60;
  if Days > 0 then
    Result := Format('%d d %.2d:%.2d:%.2d',
      [Days, Hours, Minutes, Seconds])
  else
    Result := Format('%.2d:%.2d:%.2d', [Hours, Minutes, Seconds]);
end;

procedure TBridgeDemoForm.FormCreate(Sender: TObject);
begin
  FManager := TnbSSHTunnelManager.Create(Self);
  FManager.OnError := BridgeError;
  FManager.OnVerifyHostKey := VerifyHostKey;
  LoadSettings;
  ResetRateMeter;
  UpdateState;
end;

destructor TBridgeDemoForm.Destroy;
begin
  UpdateTimer.Enabled := False;
  if FManager <> nil then
  begin
    FManager.OnError := nil;
    FManager.OnStatistics := nil;
    FManager.OnStatusChange := nil;
    FManager.OnVerifyHostKey := nil;
    FManager.Stop;
    FreeAndNil(FManager);
  end;
  inherited;
end;

procedure TBridgeDemoForm.FormClose(Sender: TObject;
  var Action: TCloseAction);
begin
  Action := TCloseAction.caFree;
end;

procedure TBridgeDemoForm.ApplyEndpoint(AEndpoint: TnbSSHBridgeEndpoint;
  AHost, APort, AUser, APassword, AKeyPath, APassphrase,
  AFingerprint: TEdit);
begin
  AEndpoint.Host := Trim(AHost.Text);
  AEndpoint.Port := StrToIntDef(Trim(APort.Text), 0);
  AEndpoint.User := Trim(AUser.Text);
  AEndpoint.Password := APassword.Text;
  AEndpoint.KeyPath := Trim(AKeyPath.Text);
  AEndpoint.Passphrase := APassphrase.Text;
  AEndpoint.HostKeyFingerprint := Trim(AFingerprint.Text);
end;

procedure TBridgeDemoForm.StartButtonClick(Sender: TObject);
begin
  ErrorLabel.Text := '';
  FNextChannelDiagnosticTick := 0;
  FAcceptedMasterFingerprint := '';
  FAcceptedReplicaFingerprint := '';
  try
    if not EnsurePassphrase(MasterKeyEdit, MasterPassphraseEdit,
      'Master SSH key') then
      Exit;
    if not EnsurePassphrase(ReplicaKeyEdit, ReplicaPassphraseEdit,
      'Replica SSH key') then
      Exit;
    ApplyEndpoint(FManager.Profile.Master, MasterHostEdit, MasterPortEdit,
      MasterUserEdit, MasterPasswordEdit, MasterKeyEdit,
      MasterPassphraseEdit, MasterFingerprintEdit);
    ApplyEndpoint(FManager.Profile.Replica, ReplicaHostEdit, ReplicaPortEdit,
      ReplicaUserEdit, ReplicaPasswordEdit, ReplicaKeyEdit,
      ReplicaPassphraseEdit, ReplicaFingerprintEdit);
    FManager.Profile.RemoteListenHost := Trim(ListenHostEdit.Text);
    FManager.Profile.RemoteListenPort := StrToIntDef(Trim(ListenPortEdit.Text), 0);
    FManager.Profile.TargetHost := Trim(TargetHostEdit.Text);
    FManager.Profile.TargetPort := StrToIntDef(Trim(TargetPortEdit.Text), 0);
    ApplyThroughputProfile;
    ResetRateMeter;
    FManager.Start;
    SaveSettings;
    UpdateState;
  except
    on E: Exception do
      ErrorLabel.Text := E.Message;
  end;
end;

function TBridgeDemoForm.SettingsFileName: string;
var
  BaseDirectory: string;
begin
{$IF Defined(MSWINDOWS)}
  BaseDirectory := GetEnvironmentVariable('LOCALAPPDATA');
  if BaseDirectory = '' then
    BaseDirectory := TPath.GetHomePath;
  BaseDirectory := TPath.Combine(BaseDirectory, 'nbDevOpsCockpit');
{$ELSE}
  BaseDirectory := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if BaseDirectory = '' then
    BaseDirectory := TPath.Combine(TPath.GetHomePath, '.config');
  BaseDirectory := TPath.Combine(BaseDirectory, 'nbdevopscockpit');
{$ENDIF}
  Result := TPath.Combine(BaseDirectory, 'ssh-bridge-demo.ini');
end;

function TBridgeDemoForm.DiagnosticLogFileName: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(SettingsFileName),
    'ssh-bridge-demo.log');
end;

procedure TBridgeDemoForm.AppendDiagnostic(const ALevel, AMessage: string);
var
  Uptime: string;
begin
  try
    if FManager.ConnectedSinceTick <> 0 then
      Uptime := FormatUptime(TThread.GetTickCount64 -
        FManager.ConnectedSinceTick)
    else
      Uptime := '--';
    ForceDirectories(TPath.GetDirectoryName(DiagnosticLogFileName));
    TFile.AppendAllText(DiagnosticLogFileName,
      Format('%s [%s] status=%s channels=%d uptime=%s rx=%d tx=%d %s%s',
        [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), ALevel,
         SSHBridgeStatusToString(FManager.Status), FManager.ActiveChannels,
         Uptime, FManager.RxBytes, FManager.TxBytes, AMessage, sLineBreak]),
      TEncoding.UTF8);
  except
    // Diagnostics must never affect the forwarding session.
  end;
end;

procedure TBridgeDemoForm.LoadSettings;
var
  Ini: TMemIniFile;
  ProfileIndex: Integer;

  procedure LoadEdit(const ASection, AName: string; AEdit: TEdit);
  begin
    if Ini.ValueExists(ASection, AName) then
      AEdit.Text := Ini.ReadString(ASection, AName, AEdit.Text);
  end;

begin
  if not TFile.Exists(SettingsFileName) then
    Exit;
  Ini := TMemIniFile.Create(SettingsFileName, TEncoding.UTF8);
  try
    LoadEdit('Master', 'Host', MasterHostEdit);
    LoadEdit('Master', 'Port', MasterPortEdit);
    LoadEdit('Master', 'User', MasterUserEdit);
    LoadEdit('Master', 'KeyPath', MasterKeyEdit);
    LoadEdit('Master', 'HostKeyFingerprint', MasterFingerprintEdit);
    LoadEdit('Replica', 'Host', ReplicaHostEdit);
    LoadEdit('Replica', 'Port', ReplicaPortEdit);
    LoadEdit('Replica', 'User', ReplicaUserEdit);
    LoadEdit('Replica', 'KeyPath', ReplicaKeyEdit);
    LoadEdit('Replica', 'HostKeyFingerprint', ReplicaFingerprintEdit);
    LoadEdit('Route', 'ListenHost', ListenHostEdit);
    LoadEdit('Route', 'ListenPort', ListenPortEdit);
    LoadEdit('Route', 'TargetHost', TargetHostEdit);
    LoadEdit('Route', 'TargetPort', TargetPortEdit);
    ProfileIndex := Ini.ReadInteger('Route', 'ThroughputProfile', 0);
    if (ProfileIndex >= 0) and
      (ProfileIndex < ThroughputComboBox.Count) then
      ThroughputComboBox.ItemIndex := ProfileIndex;
  finally
    Ini.Free;
  end;
end;

procedure TBridgeDemoForm.SaveSettings;
var
  Ini: TMemIniFile;
  FileName: string;
begin
  FileName := SettingsFileName;
  ForceDirectories(TPath.GetDirectoryName(FileName));
  Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
  try
    Ini.WriteString('Master', 'Host', Trim(MasterHostEdit.Text));
    Ini.WriteString('Master', 'Port', Trim(MasterPortEdit.Text));
    Ini.WriteString('Master', 'User', Trim(MasterUserEdit.Text));
    Ini.WriteString('Master', 'KeyPath', Trim(MasterKeyEdit.Text));
    Ini.WriteString('Master', 'HostKeyFingerprint',
      Trim(MasterFingerprintEdit.Text));
    Ini.WriteString('Replica', 'Host', Trim(ReplicaHostEdit.Text));
    Ini.WriteString('Replica', 'Port', Trim(ReplicaPortEdit.Text));
    Ini.WriteString('Replica', 'User', Trim(ReplicaUserEdit.Text));
    Ini.WriteString('Replica', 'KeyPath', Trim(ReplicaKeyEdit.Text));
    Ini.WriteString('Replica', 'HostKeyFingerprint',
      Trim(ReplicaFingerprintEdit.Text));
    Ini.WriteString('Route', 'ListenHost', Trim(ListenHostEdit.Text));
    Ini.WriteString('Route', 'ListenPort', Trim(ListenPortEdit.Text));
    Ini.WriteString('Route', 'TargetHost', Trim(TargetHostEdit.Text));
    Ini.WriteString('Route', 'TargetPort', Trim(TargetPortEdit.Text));
    Ini.WriteInteger('Route', 'ThroughputProfile',
      ThroughputComboBox.ItemIndex);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

procedure TBridgeDemoForm.ApplyThroughputProfile;
begin
  case ThroughputComboBox.ItemIndex of
    1:
      begin
        FManager.Profile.BufferSize := 256 * 1024;
        FManager.Profile.IdleWaitMs := 2;
      end;
    2:
      begin
        FManager.Profile.BufferSize := 64 * 1024;
        FManager.Profile.IdleWaitMs := 5;
      end;
  else
    begin
      FManager.Profile.BufferSize := 1024 * 1024;
      FManager.Profile.IdleWaitMs := 1;
    end;
  end;
end;

procedure TBridgeDemoForm.ResetRateMeter;
begin
  FRateStartTick := TThread.GetTickCount64;
  FLastRateTick := FRateStartTick;
  FRateBaseRxBytes := FManager.RxBytes;
  FRateBaseTxBytes := FManager.TxBytes;
  FLastRxBytes := FRateBaseRxBytes;
  FLastTxBytes := FRateBaseTxBytes;
end;

procedure TBridgeDemoForm.UpdateRateMeter;
var
  NowTick, SampleMs, TotalMs: UInt64;
  RxRate, TxRate, AverageRate: Double;
begin
  if FManager.Status <> sbsActive then
  begin
    ResetRateMeter;
    SpeedLabel.Text := 'RX: 0.0 MB/s    TX: 0.0 MB/s    Avg: 0.0 MB/s';
    Exit;
  end;

  NowTick := TThread.GetTickCount64;
  SampleMs := NowTick - FLastRateTick;
  TotalMs := NowTick - FRateStartTick;
  if SampleMs = 0 then
    Exit;

  RxRate := (FManager.RxBytes - FLastRxBytes) * 1000.0 /
    SampleMs / (1024 * 1024);
  TxRate := (FManager.TxBytes - FLastTxBytes) * 1000.0 /
    SampleMs / (1024 * 1024);
  if TotalMs > 0 then
    AverageRate := (FManager.RxBytes - FRateBaseRxBytes +
      FManager.TxBytes - FRateBaseTxBytes) * 1000.0 /
      TotalMs / (1024 * 1024)
  else
    AverageRate := 0;
  SpeedLabel.Text := Format('RX: %.1f MB/s    TX: %.1f MB/s    Avg: %.1f MB/s',
    [RxRate, TxRate, AverageRate]);
  FLastRateTick := NowTick;
  FLastRxBytes := FManager.RxBytes;
  FLastTxBytes := FManager.TxBytes;
end;

function TBridgeDemoForm.IsEncryptedPrivateKeyFile(
  const AFileName: string): Boolean;
var
  KeyText, Base64Text, CipherName: string;
  Lines: TStringList;
  Data: TBytes;
  I, Offset, NameLength: Integer;

  function ReadUInt32BE(const AData: TBytes; AOffset: Integer;
    out AValue: Integer): Boolean;
  begin
    Result := (AOffset >= 0) and (AOffset + 4 <= Length(AData));
    if Result then
      AValue := (Integer(AData[AOffset]) shl 24) or
        (Integer(AData[AOffset + 1]) shl 16) or
        (Integer(AData[AOffset + 2]) shl 8) or
        Integer(AData[AOffset + 3]);
  end;

begin
  Result := False;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;

  KeyText := TFile.ReadAllText(AFileName, TEncoding.ASCII);
  if KeyText.Contains('-----BEGIN ENCRYPTED PRIVATE KEY-----') or
     KeyText.Contains('Proc-Type: 4,ENCRYPTED') or
     KeyText.Contains('DEK-Info:') then
    Exit(True);

  if not KeyText.Contains('-----BEGIN OPENSSH PRIVATE KEY-----') then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.Text := KeyText;
    Base64Text := '';
    for I := 0 to Lines.Count - 1 do
      if not Trim(Lines[I]).StartsWith('-----') then
        Base64Text := Base64Text + Trim(Lines[I]);
  finally
    Lines.Free;
  end;

  try
    Data := TNetEncoding.Base64.DecodeStringToBytes(Base64Text);
    Offset := Length('openssh-key-v1') + 1;
    if (Length(Data) < Offset) or
       (TEncoding.ASCII.GetString(Data, 0, Offset) <> 'openssh-key-v1'#0) or
       not ReadUInt32BE(Data, Offset, NameLength) or
       (NameLength < 0) or (Offset + 4 + NameLength > Length(Data)) then
      Exit;
    Inc(Offset, 4);
    CipherName := TEncoding.ASCII.GetString(Data, Offset, NameLength);
    Result := not SameText(CipherName, 'none');
  except
    Result := False;
  end;
end;

function TBridgeDemoForm.EnsurePassphrase(AKeyEdit, APassphraseEdit: TEdit;
  const ACaption: string): Boolean;
var
  Values: array[0..0] of string;
begin
  Result := True;
  if (Trim(AKeyEdit.Text) = '') or (APassphraseEdit.Text <> '') or
     not IsEncryptedPrivateKeyFile(Trim(AKeyEdit.Text)) then
    Exit;

  Values[0] := '';
  Result := TDialogServiceSync.InputQuery(ACaption,
    [#31 + 'Key passphrase'], Values);
  if not Result then
    Exit;
  if Values[0] = '' then
  begin
    ErrorLabel.Text := 'Passphrase is required for the encrypted key.';
    Exit(False);
  end;
  APassphraseEdit.Text := Values[0];
end;

procedure TBridgeDemoForm.StopButtonClick(Sender: TObject);
begin
  FManager.Stop;
  UpdateState;
end;

procedure TBridgeDemoForm.UpdateTimerTimer(Sender: TObject);
var
  NowTick: UInt64;
begin
  UpdateState;
  NowTick := TThread.GetTickCount64;
  if (FManager.ActiveChannels > 0) and
    (FManager.ChannelDiagnostics <> '') and
    ((FNextChannelDiagnosticTick = 0) or
     (NowTick >= FNextChannelDiagnosticTick)) then
  begin
    AppendDiagnostic('CHANNEL', StringReplace(FManager.ChannelDiagnostics,
      sLineBreak, ' | ', [rfReplaceAll]));
    FNextChannelDiagnosticTick := NowTick + 30000;
  end
  else if FManager.ActiveChannels = 0 then
    FNextChannelDiagnosticTick := 0;
end;

procedure TBridgeDemoForm.BridgeError(Sender: TObject;
  const AMessage: string);
begin
  ErrorLabel.Text := AMessage;
  AppendDiagnostic('ERROR', AMessage);
end;

procedure TBridgeDemoForm.VerifyHostKey(Sender: TObject;
  ARole: TnbSSHBridgeRole; const AHost, AFingerprint: string;
  var AAccept: Boolean);
var
  RoleName, AcceptedFingerprint: string;
  FingerprintEdit: TEdit;
begin
  if ARole = sbrMaster then
  begin
    RoleName := 'Master';
    AcceptedFingerprint := FAcceptedMasterFingerprint;
    FingerprintEdit := MasterFingerprintEdit;
  end
  else
  begin
    RoleName := 'Replica';
    AcceptedFingerprint := FAcceptedReplicaFingerprint;
    FingerprintEdit := ReplicaFingerprintEdit;
  end;

  if (AcceptedFingerprint <> '') and
     SameStr(AcceptedFingerprint, AFingerprint) then
  begin
    AAccept := True;
    Exit;
  end;

  AAccept := TDialogServiceSync.MessageDialog(
    Format('%s SSH host: %s%s%s%sAccept this host key?',
      [RoleName, AHost, sLineBreak, AFingerprint, sLineBreak + sLineBreak]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbNo, 0) = mrYes;
  if not AAccept then
    Exit;

  FingerprintEdit.Text := AFingerprint;
  if ARole = sbrMaster then
    FAcceptedMasterFingerprint := AFingerprint
  else
    FAcceptedReplicaFingerprint := AFingerprint;
  SaveSettings;
end;

procedure TBridgeDemoForm.UpdateState;
begin
  StatusLabel.Text := 'Status: ' + SSHBridgeStatusToString(FManager.Status);
  ErrorLabel.Text := FManager.LastError;
  SessionLabel.Text := Format('Master SSH: %s    Replica SSH: %s',
    [BoolToStr(FManager.MasterConnected, True),
     BoolToStr(FManager.ReplicaConnected, True)]);
  if FManager.ConnectedSinceTick <> 0 then
    UptimeLabel.Text := 'Uninterrupted: ' + FormatUptime(
      TThread.GetTickCount64 - FManager.ConnectedSinceTick)
  else
    UptimeLabel.Text := 'Uninterrupted: --';
  StatisticsLabel.Text := Format('Channels: %d    RX: %.1f MB    TX: %.1f MB',
    [FManager.ActiveChannels, FManager.RxBytes / (1024 * 1024),
     FManager.TxBytes / (1024 * 1024)]);
  UpdateRateMeter;
  StartButton.Enabled := FManager.Status in [sbsStopped, sbsError];
  StopButton.Enabled := FManager.Status <> sbsStopped;
end;

procedure TBridgeDemoForm.SelectKeyFile(AEdit: TEdit);
begin
  if AEdit.Text <> '' then
    KeyDialog.FileName := AEdit.Text;
  if KeyDialog.Execute then
    AEdit.Text := KeyDialog.FileName;
end;

procedure TBridgeDemoForm.MasterKeyButtonClick(Sender: TObject);
begin
  SelectKeyFile(MasterKeyEdit);
end;

procedure TBridgeDemoForm.ReplicaKeyButtonClick(Sender: TObject);
begin
  SelectKeyFile(ReplicaKeyEdit);
end;

end.
