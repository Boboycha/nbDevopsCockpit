unit uMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, System.Skia,
  System.Actions, FMX.ActnList, ModernSSHClient, FMX.Skia, Terminal.Control,
  FMX.StdCtrls, FMX.Controls.Presentation;

type
  TForm1 = class(TForm)
    SSHClient1: TnbSSHClient;
    ActionList1: TActionList;
    TerminalControl1: TnbTerminalControl;
    Panel1: TPanel;
    odTheme: TOpenDialog;
    CornerButton1: TCornerButton;
    CornerButton2: TCornerButton;
    procedure FormShow(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure SSHClient1StatusChange(Sender: TObject; Status: TSSHStatus);
    procedure SSHClient1Disconnected(Sender: TObject);
    procedure CornerButton3Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}

procedure TForm1.Button1Click(Sender: TObject);
begin
  SSHClient1.Connect;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  SSHClient1.Disconnect;
end;

procedure TForm1.CornerButton3Click(Sender: TObject);
begin
  // Выбор файла темы и применение его к терминалу
  if not odTheme.Execute then Exit;
  TerminalControl1.LoadThemeFromFile(odTheme.FileName);
  TerminalControl1.SetFocus;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  TerminalControl1.TabStop := True;
  TerminalControl1.CanFocus := True;
end;

procedure TForm1.FormShow(Sender: TObject);
var
  Btn: TCornerButton;
begin
  // Кнопка "ApplyTheme" живёт в стиле рамки окна — привязываем обработчик в рантайме
  Btn := Border.WindowBorder.FindStyleResource('ApplyTheme') as TCornerButton;
  if Assigned(Btn) then
    Btn.OnClick := CornerButton3Click;
end;

procedure TForm1.SSHClient1Disconnected(Sender: TObject);
begin
  TerminalControl1.Clear;
end;

procedure TForm1.SSHClient1StatusChange(Sender: TObject; Status: TSSHStatus);
begin
  if Status = ssIdle then
  begin
    // Сессия завершена — очищаем экран терминала
    TerminalControl1.Clear;
  end;
end;

end.
