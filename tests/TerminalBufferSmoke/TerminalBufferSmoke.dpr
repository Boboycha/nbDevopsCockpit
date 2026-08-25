program TerminalBufferSmoke;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.UITypes, FMX.Consts,
  Terminal.AnsiParser in '..\..\src\Terminal.AnsiParser.pas',
  Terminal.Input in '..\..\src\Terminal.Input.pas',
  Terminal.Buffer in '..\..\src\Terminal.Buffer.pas',
  Terminal.Theme in '..\..\src\Terminal.Theme.pas',
  Terminal.Types in '..\..\src\Terminal.Types.pas';

procedure Fail(const Msg: string);
begin
  Writeln('FAIL: ' + Msg);
  Halt(1);
end;

function CellText(Buffer: TTerminalBuffer; Row, Col, Count: Integer): string;
var
  I: Integer;
  Line: TTerminalLine;
begin
  Result := '';
  Line := Buffer.GetRenderLine(Row);
  for I := Col to Col + Count - 1 do
    if (I >= 0) and (I < Length(Line.Cells)) and (Line.Cells[I].Width > 0) then
      Result := Result + Line.Cells[I].Char;
end;

procedure CheckCursor(Buffer: TTerminalBuffer; X, Y: Integer; const Msg: string);
begin
  if (Buffer.Cursor.X <> X) or (Buffer.Cursor.Y <> Y) then
    Fail(Msg + Format(' expected=%d,%d actual=%d,%d',
      [X + 1, Y + 1, Buffer.Cursor.X + 1, Buffer.Cursor.Y + 1]));
end;
procedure Feed(Buffer: TTerminalBuffer; Parser: TAnsiParser; const Text: string);
var
  Commands: TArray<TAnsiCommand>;
  I: Integer;
begin
  Parser.Parse(Text, Commands);
  for I := 0 to High(Commands) do
    Buffer.ProcessCommand(Commands[I]);
end;
procedure Exec(Buffer: TTerminalBuffer; Command: TAnsiParserCommand;
  const Params: array of Integer);
var
  Cmd: TAnsiCommand;
  I: Integer;
begin
  Cmd.Command := Command;
  Cmd.Char := '';
  Cmd.Attributes := Buffer.CurrentAttributes;
  SetLength(Cmd.Params, Length(Params));
  for I := 0 to High(Params) do
    Cmd.Params[I] := Params[I];
  Buffer.ProcessCommand(Cmd);
end;

procedure TestCursorBackwardTab;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
  Parser: TAnsiParser;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(80, 3, Theme);
    try
      Parser := TAnsiParser.Create(Theme);
      try
        Buffer.MoveCursor(65, 0);
        Feed(Buffer, Parser, #27'[Z');
        CheckCursor(Buffer, 64, 0, 'CSI Z must move to previous tab stop');
        Feed(Buffer, Parser, #27'[2Z');
        CheckCursor(Buffer, 48, 0, 'CSI 2 Z must move two previous tab stops');
      finally
        Parser.Free;
      end;
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;
procedure TestPrintableNonAsciiWithCtrl;
var
  S: string;
begin
  S := TTerminalInput.TranslateKey(Ord('C'), WideChar($0441), [ssCtrl], False);
  if S <> WideChar($0441) then
    Fail('printable non-ASCII KeyChar with Ctrl must not become a physical-key control command');
end;
procedure TestPrintableAltGrInput;
var
  S: string;
begin
  S := TTerminalInput.TranslateKey(Ord('C'), WideChar($0441), [ssCtrl, ssAlt], False);
  if S <> WideChar($0441) then
    Fail('printable Ctrl+Alt KeyChar must be treated as AltGr text input');

  S := TTerminalInput.TranslateKey(Ord('.'), '.', [ssCtrl, ssAlt], False);
  if S <> '.' then
    Fail('printable Ctrl+Alt dot must not become an ESC-prefixed command');
end;
procedure TestInsertMode;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(10, 3, Theme);
    try
      Buffer.WriteText('abcd', Buffer.CurrentAttributes);
      Buffer.MoveCursor(1, 0);
      Exec(Buffer, apcSetMode, [4]);
      Buffer.WriteText('XY', Buffer.CurrentAttributes);
      if CellText(Buffer, 0, 0, 6) <> 'aXYbcd' then
        Fail('insert mode must shift existing cells before printable text');
      Exec(Buffer, apcResetMode, [4]);
      if Buffer.InsertMode then
        Fail('CSI 4 l must reset insert mode');
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;

procedure TestOriginMode;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(10, 6, Theme);
    try
      Exec(Buffer, apcSetScrollingRegion, [3, 5]);
      Exec(Buffer, apcSetPrivateMode, [6]);
      Exec(Buffer, apcCursorPosition, [1, 2]);
      if (Buffer.Cursor.Y <> 2) or (Buffer.Cursor.X <> 1) then
        Fail('origin mode cursor position must be relative to scroll top');
      Exec(Buffer, apcVerticalPositionAbs, [3]);
      if Buffer.Cursor.Y <> 4 then
        Fail('origin mode vertical position must stay inside scroll region');
      Exec(Buffer, apcResetPrivateMode, [6]);
      if Buffer.OriginMode then
        Fail('CSI ? 6 l must reset origin mode');
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;

procedure TestParserInsertLine;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
  Parser: TAnsiParser;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(12, 4, Theme);
    try
      Parser := TAnsiParser.Create(Theme);
      try
        Feed(Buffer, Parser, 'one'#10#13'two'#10#13'three');
        Buffer.MoveCursor(0, 1);
        Feed(Buffer, Parser, #27'[Lpaste');
        if CellText(Buffer, 1, 0, 5) <> 'paste' then
          Fail('CSI L must create a blank line for pasted text');
        if CellText(Buffer, 2, 0, 3) <> 'two' then
          Fail('CSI L must shift the current line down');
      finally
        Parser.Free;
      end;
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;
procedure TestEscSaveRestoreReverseIndex;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
  Parser: TAnsiParser;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(12, 5, Theme);
    try
      Parser := TAnsiParser.Create(Theme);
      try
        Feed(Buffer, Parser, 'one'#10#13'two'#10#13'three'#10#13'four');
        Buffer.MoveCursor(0, 1);
        Feed(Buffer, Parser, #27'7'#27'[2;4r'#27'8'#27'Mpaste');
        if CellText(Buffer, 1, 0, 5) <> 'paste' then
          Fail('ESC 7/8 + RI must insert a blank line at the saved cursor');
        if CellText(Buffer, 2, 0, 3) <> 'two' then
          Fail('RI at scroll top must shift existing lines down');
      finally
        Parser.Free;
      end;
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;
procedure TestFragmentedCsi;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
  Parser: TAnsiParser;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(40, 20, Theme);
    try
      Parser := TAnsiParser.Create(Theme);
      try
        Feed(Buffer, Parser, #27'[');
        Feed(Buffer, Parser, '10;');
        Feed(Buffer, Parser, '20');
        Feed(Buffer, Parser, 'H');
        CheckCursor(Buffer, 19, 9, 'fragmented CUP must match complete CUP');
      finally
        Parser.Free;
      end;
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;

procedure TestPendingWrapBackspace;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(5, 3, Theme);
    try
      Buffer.WriteText('abcde', Buffer.CurrentAttributes);
      CheckCursor(Buffer, 4, 0, 'last-column write must leave cursor on final cell');
      if not Buffer.PendingWrap then
        Fail('last-column write must set pending wrap');
      Buffer.WriteText(#8, Buffer.CurrentAttributes);
      CheckCursor(Buffer, 3, 0, 'backspace after pending wrap must move left on same row');
      if Buffer.PendingWrap then
        Fail('backspace must clear pending wrap');
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;

procedure TestDecawmMode;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
  Parser: TAnsiParser;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(5, 3, Theme);
    try
      Parser := TAnsiParser.Create(Theme);
      try
        Feed(Buffer, Parser, #27'[?7l');
        if Buffer.AutoWrapMode then
          Fail('CSI ? 7 l must disable autowrap mode');
        Buffer.WriteText('abcdef', Buffer.CurrentAttributes);
        CheckCursor(Buffer, 4, 0, 'DECAWM reset must keep cursor on final cell');
        if Buffer.PendingWrap then
          Fail('DECAWM reset must not leave pending wrap');
        if CellText(Buffer, 0, 0, 5) <> 'abcdf' then
          Fail('DECAWM reset must overwrite the final cell instead of wrapping');

        Feed(Buffer, Parser, #27'[?7h');
        if not Buffer.AutoWrapMode then
          Fail('CSI ? 7 h must enable autowrap mode');
        Buffer.MoveCursor(0, 1);
        Buffer.WriteText('12345', Buffer.CurrentAttributes);
        CheckCursor(Buffer, 4, 1, 'DECAWM set must defer wrap at final cell');
        if not Buffer.PendingWrap then
          Fail('DECAWM set must leave pending wrap after final-cell write');
        Buffer.WriteText('6', Buffer.CurrentAttributes);
        CheckCursor(Buffer, 1, 2, 'print after pending wrap must advance on next row');
        if CellText(Buffer, 2, 0, 1) <> '6' then
          Fail('print after pending wrap must land at first cell of next row');
      finally
        Parser.Free;
      end;
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;
procedure TestScrollRegionIsolation;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
  Parser: TAnsiParser;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(12, 5, Theme);
    try
      Parser := TAnsiParser.Create(Theme);
      try
        Feed(Buffer, Parser, 'top'#10#13'one'#10#13'two'#10#13'three'#10#13'bottom');
        Buffer.MoveCursor(0, 1);
        Feed(Buffer, Parser, #27'[2;4r'#27'M');
        if CellText(Buffer, 0, 0, 3) <> 'top' then
          Fail('RI inside scroll region must not touch line above region');
        if CellText(Buffer, 4, 0, 6) <> 'bottom' then
          Fail('RI inside scroll region must not touch line below region');
      finally
        Parser.Free;
      end;
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;

procedure TestWideAndCombiningWidths;
var
  Theme: TTerminalTheme;
  Buffer: TTerminalBuffer;
begin
  Theme := TTerminalTheme.Create;
  try
    Buffer := TTerminalBuffer.Create(10, 2, Theme);
    try
      Buffer.WriteText('A' + #$0301 + '界', Buffer.CurrentAttributes);
      CheckCursor(Buffer, 3, 0, 'combining width 0 and CJK width 2 must advance by cells');
      if CellText(Buffer, 0, 0, 2) <> 'A' + #$0301 + '界' then
        Fail('wide/combining cells must preserve grapheme text');
    finally
      Buffer.Free;
    end;
  finally
    Theme.Free;
  end;
end;
begin
  try
    TestFragmentedCsi;
    TestCursorBackwardTab;
    TestPrintableNonAsciiWithCtrl;
    TestPrintableAltGrInput;
    TestPendingWrapBackspace;
    TestDecawmMode;
    TestScrollRegionIsolation;
    TestWideAndCombiningWidths;
    TestInsertMode;
    TestOriginMode;
    TestParserInsertLine;
    TestEscSaveRestoreReverseIndex;
    Writeln('OK');
  except
    on E: Exception do
      Fail(E.ClassName + ': ' + E.Message);
  end;
end.
