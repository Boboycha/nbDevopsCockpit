program LocalTerminalSmoke;

{$APPTYPE CONSOLE}

uses
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}
  System.SysUtils, System.Classes, System.Diagnostics,
  Terminal.LocalSession in '..\..\src\Terminal.LocalSession.pas',
  Terminal.LocalPTY in '..\..\src\Terminal.LocalPTY.pas';

type
  TProbe = class
    Text: string;
    Error: string;
    Code: Integer;
    Exited: Boolean;
    procedure ReadData(Sender: TObject; const Data: string);
    procedure OnError(Sender: TObject; const Data: string);
    procedure OnExit(Sender: TObject; ExitCode: Integer);
  end;

procedure TProbe.ReadData(Sender: TObject; const Data: string);
begin
  Text := Text + Data;
end;

procedure TProbe.OnError(Sender: TObject; const Data: string);
begin
  Error := Data;
end;

procedure TProbe.OnExit(Sender: TObject; ExitCode: Integer);
begin
  Code := ExitCode;
  Exited := True;
end;

procedure Require(Condition: Boolean; const Msg: string);
begin
  if not Condition then raise Exception.Create(Msg);
end;

var
  Session: TnbLocalTerminalSession;
  Probe: TProbe;
  Watch: TStopwatch;
  I: Integer;
  {$IFDEF MSWINDOWS}
  Written: DWORD;
  UnicodeText: string;
  {$ENDIF}
begin
  try
    if ParamStr(1) = '--flood' then
    begin
      for I := 1 to 50000 do Writeln(StringOfChar('X', 256));
      Halt(0);
    end;
    {$IFDEF MSWINDOWS}
    if ParamStr(1) = '--unicode' then
    begin
      UnicodeText := #$041F#$0440#$0438#$0432#$0435#$0442' '#$D83D#$DE0A + #13#10;
      WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE), PChar(UnicodeText),
        Length(UnicodeText), Written, nil);
      Halt(0);
    end;
    {$ENDIF}
    Probe := TProbe.Create;
    Session := TnbLocalTerminalSession.Create(nil);
    try
      Session.OnReadData := Probe.ReadData;
      Session.OnError := Probe.OnError;
      Session.OnExit := Probe.OnExit;
      {$IFDEF MSWINDOWS}
      Session.Start('cmd.exe', ['/d', '/q']);
      {$ELSE}
      Session.Start('/bin/sh', ['-i']);
      {$ENDIF}
      Session.ResizePTY(100, 35);
      {$IFDEF MSWINDOWS}
      Session.SendText('echo LOCAL_PTY_OK' + #13);
      Session.SendText('exit /b 7' + #13);
      {$ELSE}
      Session.SendText('printf "LOCAL_PTY_OK\n"; stty size; exit 7' + #13);
      {$ENDIF}
      Watch := TStopwatch.StartNew;
      while Session.Running and (Watch.ElapsedMilliseconds < 15000) do
      begin
        Session.Pump;
        TThread.Sleep(5);
      end;
      Require(not Session.Running, 'Shell did not exit within 15 seconds');
      Require(Probe.Error = '', 'Transport error: ' + Probe.Error);
      if Probe.Code <> 7 then Writeln('Captured: ', Probe.Text);
      Require(Probe.Exited and (Probe.Code = 7), 'Exit code was not 7: ' + IntToStr(Probe.Code));
      Require(Pos('LOCAL_PTY_OK', Probe.Text) > 0, 'Missing terminal output');
      {$IFNDEF MSWINDOWS}
      Require(Pos('35 100', Probe.Text) > 0, 'PTY resize was not applied');
      {$ENDIF}
      Writeln('PASS: interactive input, output, resize, exit status');

      for I := 1 to 5 do
      begin
        Session.Start;
        Session.SendText(StringOfChar('x', 100000) + #13);
        Watch := TStopwatch.StartNew;
        Session.Stop;
        Require(Watch.ElapsedMilliseconds < 5000, 'Stop blocked with pending input');
      end;
      Writeln('PASS: repeated start/stop with queued input');

      Session.Start(ParamStr(0), ['--flood']);
      TThread.Sleep(500); // deliberately do not Pump: fill the output queue
      Watch := TStopwatch.StartNew;
      Session.Stop;
      Require(Watch.ElapsedMilliseconds < 5000, 'Stop blocked with unread output');
      Writeln('PASS: stop with output backpressure');

      {$IFDEF MSWINDOWS}
      Probe.Text := '';
      Probe.Exited := False;
      Session.Start(ParamStr(0), ['--unicode']);
      Watch := TStopwatch.StartNew;
      while Session.Running and (Watch.ElapsedMilliseconds < 10000) do
      begin
        Session.Pump;
        TThread.Sleep(5);
      end;
      Require(Probe.Exited, 'Unicode child did not exit');
      Require(Pos(#$041F#$0440#$0438#$0432#$0435#$0442, Probe.Text) > 0,
        'Cyrillic output corrupted');
      Require(Pos(#$D83D#$DE0A, Probe.Text) > 0, 'Emoji output corrupted');
      Writeln('PASS: Cyrillic and supplementary Unicode output');
      {$ENDIF}

      try
        {$IFDEF MSWINDOWS}
        Session.Start('Z:\__missing_local_terminal_test__\shell.exe');
        {$ELSE}
        Session.Start('/__missing_local_terminal_test__/shell');
        {$ENDIF}
        raise Exception.Create('Invalid executable unexpectedly started');
      except
        on E: EOSError do Writeln('PASS: launch failure');
      end;
      Require(not Session.Running, 'Failed startup left session running');
    finally
      Session.Free;
      Probe.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
