unit uDemoMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, System.Skia,
  System.Actions, FMX.ActnList, ModernSSHClient, FMX.Skia, Terminal.Control,
  FMX.StdCtrls, FMX.Controls.Presentation,  GoghThemeLoader,
  FMX.ListBox,  FMX.Edit;

type
  TDemoForm = class(TForm)
    SSHClient1: TnbSSHClient;
    ActionList1: TActionList;
    TerminalControl1: TnbTerminalControl;
    Panel1: TPanel;
    odTheme: TOpenDialog;
    CornerButton1: TCornerButton;
    CornerButton2: TCornerButton;
    lblTheme: TLabel;
    cbTheme: TComboBox;
    btnBrowse: TCornerButton;
    lblHost: TLabel;
    edHost: TEdit;
    lblPort: TLabel;
    edPort: TEdit;
    lblUser: TLabel;
    edUser: TEdit;
    lblKey: TLabel;
    edKeyPath: TEdit;
    btnBrowseKey: TCornerButton;
    odKey: TOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure BrowseThemeClick(Sender: TObject);
    procedure cbThemeChange(Sender: TObject);
    procedure BrowseKeyClick(Sender: TObject);
  private
    FThemes: TGoghThemeInfoArray;
    procedure SSHConnecting(Sender: TObject);
    procedure SSHConnected(Sender: TObject);
    procedure SSHError(Sender: TObject; const Msg: string);
    procedure SSHDisconnected(Sender: TObject);
    procedure UpdateButtons;
  public
  end;

var
  DemoForm: TDemoForm;

implementation

{$R *.fmx}

procedure TDemoForm.Button1Click(Sender: TObject);
begin
  SSHClient1.Host := Trim(edHost.Text);
  SSHClient1.Port := Trim(edPort.Text);
  SSHClient1.User := Trim(edUser.Text);
  SSHClient1.KeyPath := Trim(edKeyPath.Text);

  if SSHClient1.Host = '' then
  begin
    ShowMessage('Укажите хост для подключения.');
    edHost.SetFocus;
    Exit;
  end;

  if SSHClient1.User = '' then
  begin
    ShowMessage('Укажите имя пользователя.');
    edUser.SetFocus;
    Exit;
  end;

  if SSHClient1.Port = '' then
  begin
    ShowMessage('Укажите порт SSH.');
    edPort.SetFocus;
    Exit;
  end;

  SSHClient1.Connect;
end;

procedure TDemoForm.Button2Click(Sender: TObject);
begin
  SSHClient1.Disconnect;
end;

procedure TDemoForm.BrowseThemeClick(Sender: TObject);
begin
  odTheme.Filter := 'Темы Gogh (*.yml;*.yaml)|*.yml;*.yaml|Все файлы (*.*)|*.*';
  if not odTheme.Execute then Exit;
  TerminalControl1.LoadThemeFromFile(odTheme.FileName);
  TerminalControl1.SetFocus;
end;

procedure TDemoForm.BrowseKeyClick(Sender: TObject);
begin
  odKey.Filter := 'Приватные ключи (*.pem;*.key;id_*)|*.pem;*.key;id_*|Все файлы (*.*)|*.*';
  if edKeyPath.Text <> '' then
    odKey.FileName := edKeyPath.Text;
  if not odKey.Execute then Exit;
  edKeyPath.Text := odKey.FileName;
  TerminalControl1.SetFocus;
end;

procedure TDemoForm.cbThemeChange(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := cbTheme.ItemIndex;
  if Idx <= 0 then
  begin
    TerminalControl1.LoadDefaultTheme;
    TerminalControl1.SetFocus;
    Exit;
  end;
  Dec(Idx);  // 0 = «По умолчанию», поэтому сдвигаем на один
  if Idx < Length(FThemes) then
    TerminalControl1.LoadThemeFromFile(FThemes[Idx].FileName);
  TerminalControl1.SetFocus;
end;

// --- Обновление состояния кнопок ---

procedure TDemoForm.UpdateButtons;
begin
  case SSHClient1.Status of
    ssIdle:
      begin
        CornerButton1.Enabled := True;
        CornerButton2.Enabled := False;
      end;
    ssConnecting, ssAuthenticating:
      begin
        CornerButton1.Enabled := False;
        CornerButton2.Enabled := False;
      end;
    ssConnected:
      begin
        CornerButton1.Enabled := False;
        CornerButton2.Enabled := True;
      end;
    ssError:
      begin
        CornerButton1.Enabled := True;
        CornerButton2.Enabled := False;
      end;
  end;
end;

procedure TDemoForm.SSHConnecting(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TDemoForm.SSHConnected(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TDemoForm.SSHError(Sender: TObject; const Msg: string);
begin
  UpdateButtons;
  // Ошибка уже выводится в терминал через TnbTerminalControl.HandleSSHStatusChange
end;

procedure TDemoForm.SSHDisconnected(Sender: TObject);
begin
  UpdateButtons;
  // Намеренно НЕ вызываем TerminalControl1.Clear — содержимое терминала
  // (включая сообщения об ошибках) должно остаться видимым после отключения.
end;

// --- Инициализация ---

procedure TDemoForm.FormCreate(Sender: TObject);
var
  I: Integer;
  ThemesDir: string;
begin
  TerminalControl1.TabStop := True;
  TerminalControl1.CanFocus := True;

  // Подписываемся на отдельные события SSH — OnStatusChange занят TerminalControl1
  SSHClient1.OnConnecting   := SSHConnecting;
  SSHClient1.OnConnected    := SSHConnected;
  SSHClient1.OnError        := SSHError;
  SSHClient1.OnDisconnected := SSHDisconnected;

  // Начальное состояние кнопок
  CornerButton2.Enabled := False;
  SSHClient1.Host := '';
  SSHClient1.Port := '22';
  SSHClient1.User := '';
  SSHClient1.KeyPath := '';
  edHost.Text := '';
  edPort.Text := SSHClient1.Port;
  edUser.Text := '';
  edKeyPath.Text := '';

  // Рядом с exe (деплой); при разработке — в репозитории demo\themes\
  ThemesDir := ExtractFilePath(ParamStr(0)) + 'themes\';
  if not DirectoryExists(ThemesDir) then
    ThemesDir := ExpandFileName(ExtractFilePath(ParamStr(0)) +
      '..\..\..\..\demo\themes\');
  FThemes := TnbTerminalControl.EnumThemes(ThemesDir);

  cbTheme.Items.BeginUpdate;
  try
    cbTheme.Items.Add('По умолчанию');
    for I := 0 to High(FThemes) do
      cbTheme.Items.Add(FThemes[I].Name);
  finally
    cbTheme.Items.EndUpdate;
  end;
  cbTheme.ItemIndex := 0;
end;

end.
