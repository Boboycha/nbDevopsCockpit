program TerminalAnsiTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  FMX.Types,
  FMX.Consts,
  Terminal.Theme,
  Terminal.Types,
  Terminal.Input,
  Terminal.Clipboard,
  Terminal.AnsiParser,
  Terminal.Buffer;

const
  ExpectedLineDrawing: string =
    #$00A0#$25C6#$2592#$2409#$240C#$240D#$240A#$00B0 +
    #$00B1#$2424#$240B#$2518#$2510#$250C#$2514#$253C +
    #$23BA#$23BB#$2500#$23BC#$23BD#$251C#$2524#$2534 +
    #$252C#$2502#$2264#$2265#$03C0#$2260#$00A3#$00B7;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure ProcessText(AParser: TAnsiParser; ABuffer: TTerminalBuffer;
  const AText: string);
var
  Commands: TArray<TAnsiCommand>;
  Command: TAnsiCommand;
begin
  Check(AParser.Parse(AText, Commands), 'parser returned no commands');
  for Command in Commands do
    ABuffer.ProcessCommand(Command);
end;

function FindCommand(const Commands: TArray<TAnsiCommand>;
  ACommand: TAnsiParserCommand): TAnsiCommand;
var
  Command: TAnsiCommand;
begin
  for Command in Commands do
    if Command.Command = ACommand then
      Exit(Command);
  raise Exception.CreateFmt('command %d was not emitted', [Ord(ACommand)]);
end;

procedure TestBatchScroll(ATheme: TTerminalTheme);
var
  Buffer: TTerminalBuffer;
  Line: TTerminalLine;
  Command: TAnsiCommand;
  I: Integer;
begin
  Buffer := TTerminalBuffer.Create(4, 4, ATheme);
  try
    Buffer.MaxScrollback := 1;
    for I := 0 to 3 do
    begin
      Line := Buffer.Lines[I];
      Line.Cells[0].Char := Char(Ord('A') + I);
      Buffer.Lines[I] := Line;
    end;

    Command := Default(TAnsiCommand);
    Command.Command := apcScrollUp;
    Command.Params := TArray<Integer>.Create(2);
    Buffer.ProcessCommand(Command);

    Check(Buffer.Scrollback.Count = 1,
      'batch scrollback trimming mismatch');
    Check(Buffer.Scrollback[0].Cells[0].Char = 'B',
      'batch scrollback retained wrong line');
    Check(Buffer.Lines[0].Cells[0].Char = 'C',
      'batch scroll did not shift first visible line');
    Check(Buffer.Lines[1].Cells[0].Char = 'D',
      'batch scroll did not shift second visible line');
    Check((Buffer.Lines[2].Cells[0].Char = ' ') and
      (Buffer.Lines[3].Cells[0].Char = ' '),
      'batch scroll did not clear inserted lines');
  finally
    Buffer.Free;
  end;
end;

procedure TestTextWriting(ATheme: TTerminalTheme);
var
  Buffer: TTerminalBuffer;
  Attr: TCharAttributes;
  Emoji: string;
begin
  Attr := TCharAttributes.Default(ATheme);
  Buffer := TTerminalBuffer.Create(4, 3, ATheme);
  try
    Buffer.WriteText('ABCDX', Attr);
    Check(Buffer.Lines[0].IsWrapped, 'automatic wrap flag was not set');
    Check(Buffer.Lines[1].Cells[0].Char = 'X',
      'automatic wrap placed character incorrectly');

    Buffer.Clear;
    Buffer.WriteText('AB'#10'C', Attr);
    Check(Buffer.Lines[1].Cells[2].Char = 'C',
      'line feed must preserve the cursor column');

    Buffer.Clear;
    Buffer.MoveCursor(3, 0);
    Buffer.WriteChar(#$754C, Attr);
    Check(Buffer.Lines[0].IsWrapped, 'wide-character wrap flag was not set');
    Check((Buffer.Lines[1].Cells[0].Char = #$754C) and
      (Buffer.Lines[1].Cells[0].Width = 2) and
      (Buffer.Lines[1].Cells[1].Width = 0),
      'wide character was not moved intact to the next line');

    Buffer.Clear;
    Emoji := #$D83D#$DE00;
    Buffer.WriteText(Emoji, Attr);
    Check(Buffer.Lines[0].Cells[0].Char = Emoji,
      'UTF-16 surrogate pair was split');

    Buffer.Clear;
    Buffer.WriteText(Emoji + #$200D + Emoji, Attr);
    Check(Buffer.Lines[0].Cells[0].Char = Emoji + #$200D + Emoji,
      'ZWJ sequence after a wide glyph was split');
    Check(Buffer.Lines[0].Cells[1].Width = 0,
      'ZWJ sequence damaged the wide-glyph tail');
  finally
    Buffer.Free;
  end;
end;

procedure TestCellEditing(ATheme: TTerminalTheme);
var
  Buffer: TTerminalBuffer;
  Attr: TCharAttributes;

  procedure PutWideAtColumnOne;
  begin
    Buffer.Clear;
    Buffer.MoveCursor(1, 0);
    Buffer.WriteChar(#$754C, Attr);
  end;

  procedure CheckWideWasCleared(const Operation: string);
  begin
    Check((Buffer.Lines[0].Cells[1].Char = ' ') and
      (Buffer.Lines[0].Cells[1].Width = 1) and
      (Buffer.Lines[0].Cells[2].Char = ' ') and
      (Buffer.Lines[0].Cells[2].Width = 1),
      Operation + ' left an orphan wide-character cell');
  end;

begin
  Attr := TCharAttributes.Default(ATheme);
  Buffer := TTerminalBuffer.Create(6, 2, ATheme);
  try
    Buffer.WriteText('ABCD', Attr);
    Buffer.InsertChar(1, 0, 2);
    Check((Buffer.Lines[0].Cells[0].Char = 'A') and
      (Buffer.Lines[0].Cells[1].Char = ' ') and
      (Buffer.Lines[0].Cells[2].Char = ' ') and
      (Buffer.Lines[0].Cells[3].Char = 'B'),
      'insert character shift mismatch');

    PutWideAtColumnOne;
    Buffer.EraseChar(2, 0, 1);
    CheckWideWasCleared('erase');

    PutWideAtColumnOne;
    Buffer.InsertChar(2, 0, 1);
    CheckWideWasCleared('insert');

    PutWideAtColumnOne;
    Buffer.DeleteChar(2, 0, 1);
    CheckWideWasCleared('delete');
  finally
    Buffer.Free;
  end;
end;

procedure TestTerminalInput;
var
  S: string;
begin
  Check(TTerminalInput.TranslateKey(vkUp, #0, [], False) = #27'[A',
    'normal cursor-up sequence mismatch');
  Check(TTerminalInput.TranslateKey(vkUp, #0, [], True) = #27'OA',
    'application cursor-up sequence mismatch');
  Check(TTerminalInput.TranslateKey(vkUp, #0, [ssCtrl], False) =
    #27'[1;5A', 'modified cursor-up sequence mismatch');
  Check(TTerminalInput.TranslateKey(vkHome, #0, [], True) = #27'OH',
    'application Home sequence mismatch');
  Check(TTerminalInput.TranslateKey(vkEnd, #0, [], True) = #27'OF',
    'application End sequence mismatch');
  Check(TTerminalInput.TranslateKey(vkF5, #0, [ssShift], False) =
    #27'[15;2~', 'modified F5 sequence mismatch');
  Check(TTerminalInput.TranslateKey(vkTab, #0, [ssShift], False) =
    #27'[Z', 'back-tab sequence mismatch');
  Check(TTerminalInput.TranslateKey(Ord('A'), 'a', [ssCtrl], False) = #1,
    'Ctrl+A sequence mismatch');
  Check(TTerminalInput.TranslateKey(Ord('A'), 'a', [ssCtrl, ssAlt], False) =
    #27#1, 'Ctrl+Alt+A must preserve the Alt prefix');
  S := TTerminalInput.TranslateKey(Ord(' '), ' ', [ssCtrl], False);
  Check((Length(S) = 1) and (S[1] = #0), 'Ctrl+Space must emit NUL');

  Check(TTerminalInput.BuildMouseReport(0, 10, 20, [], mbsDown,
    [mtm1000_Click, mtm1006_SGR]) = #27'[<0;10;20M',
    'SGR mouse-down report mismatch');
  Check(TTerminalInput.BuildMouseReport(0, 10, 20, [], mbsMove,
    [mtm1002_Wheel, mtm1006_SGR]) = #27'[<32;10;20M',
    'SGR button-motion report mismatch');
  Check(TTerminalInput.BuildMouseReport(0, 10, 20, [], mbsMove,
    [mtm1000_Click, mtm1006_SGR]) = '',
    'click-only mode must not report motion');
  Check(TTerminalInput.BuildMouseReport(0, 1, 1, [], mbsMove,
    [mtm1002_Wheel]) = #27'[M@!!',
    'legacy button-motion report mismatch');
end;

procedure TestSelection(ATheme: TTerminalTheme);
var
  Buffer: TTerminalBuffer;
  Attr: TCharAttributes;
begin
  Attr := TCharAttributes.Default(ATheme);
  Buffer := TTerminalBuffer.Create(6, 3, ATheme);
  try
    Buffer.MoveCursor(1, 0);
    Buffer.WriteChar(#$754C, Attr);
    Buffer.SetSelection(2, 0, 2, 0);
    Check(Buffer.GetSelectedText = #$754C,
      'selecting a wide-glyph tail must copy the whole glyph');

    Buffer.Clear;
    Buffer.Resize(4, 3);
    Buffer.WriteText('ABCDE', Attr);
    Buffer.SetSelection(0, 0, 0, 1);
    Check(Buffer.GetSelectedText = 'ABCDE',
      'soft-wrapped selection inserted a newline');

    Buffer.Clear;
    Buffer.Resize(6, 3);
    Buffer.WriteText('AB'#10'C', Attr);
    Buffer.SetSelection(0, 0, 2, 1);
    Check(Buffer.GetSelectedText = 'AB' + sLineBreak + '  C',
      'hard-line selection or trailing-space trimming mismatch');

    Buffer.SetSelection(-100, -100, 100, 100);
    Check(Buffer.HasSelection, 'clamped selection was unexpectedly cleared');
  finally
    Buffer.Free;
  end;
end;

procedure TestClipboardHelpers;
begin
  Check(TTerminalClipboard.NormalizeLineEndings(
    'a'#13#10'b'#10'c'#13'd') = 'a'#13'b'#13'c'#13'd',
    'paste line-ending normalization mismatch');
  Check(TTerminalClipboard.NormalizeLineEndings('plain') = 'plain',
    'plain paste text was modified');
  Check(TTerminalClipboard.WrapBracketedPaste('text') =
    #27'[200~text'#27'[201~', 'bracketed paste wrapper mismatch');
end;

var
  Theme, NewTheme: TTerminalTheme;
  Parser: TAnsiParser;
  Buffer: TTerminalBuffer;
  Line: TTerminalLine;
  OriginalRGB: TAlphaColor;
  Commands: TArray<TAnsiCommand>;
  Command: TAnsiCommand;
  I: Integer;
  Source: string;
begin
  Theme := TTerminalTheme.Create;
  NewTheme := TTerminalTheme.Create;
  Parser := TAnsiParser.Create(Theme);
  Buffer := TTerminalBuffer.Create(20, 3, Theme);
  try
    Check(GetCharDisplayWidth('A') = 1, 'ASCII width mismatch');
    Check(GetCharDisplayWidth(#$754C) = 2, 'CJK width mismatch');
    Check(GetCharDisplayWidth(#$0301) = 0,
      'combining mark must be zero-width');
    Check(GetCharDisplayWidth('e'#$0301) = 1,
      'combined Latin grapheme width mismatch');
    Check(GetCharDisplayWidth(#$007F) = 0,
      'DEL control character must be zero-width');
    Check(GetCharDisplayWidth('1'#$FE0F) = 2,
      'emoji presentation sequence width mismatch');
    Check(IsEmojiChar(#$D83D#$DE00), 'emoji was not recognized');
    Check(not IsEmojiChar(#$754C), 'CJK was incorrectly classified as emoji');
    Check(IsBoxDrawingChar(#$2500), 'box-drawing character was not recognized');

    OriginalRGB := $FFCD3131;
    Theme.AnsiColors[1] := OriginalRGB;
    NewTheme.Assign(Theme);
    NewTheme.AnsiColors[1] := $FF112233;

    ProcessText(Parser, Buffer,
      #27'[31mA'#27'[38;2;205;49;49mB'#27'[1mC'#27'[;mD');
    Line := Buffer.GetRenderLine(0);

    Check(Line.Cells[0].Attributes.ForegroundSource = tcsAnsi,
      'ANSI color source was not preserved');
    Check(Line.Cells[0].Attributes.ForegroundIndex = 1,
      'ANSI color index mismatch');
    Check(Line.Cells[1].Attributes.ForegroundSource = tcsRGB,
      'truecolor source was not preserved');
    Check(Line.Cells[2].Attributes.Bold, 'SGR 1 did not enable bold');
    Check(not Line.Cells[3].Attributes.Bold,
      'empty SGR parameter did not reset attributes');

    Buffer.SetTheme(NewTheme);
    Line := Buffer.GetRenderLine(0);
    Check(Line.Cells[0].Attributes.ForegroundColor = $FF112233,
      'ANSI color was not remapped');
    Check(Line.Cells[1].Attributes.ForegroundColor = OriginalRGB,
      'matching truecolor was incorrectly remapped');

    Parser.Reset;
    Parser.Parse(#27'[;H'#27'[J'#27'[?25l', Commands);
    Command := FindCommand(Commands, apcCursorPosition);
    Check((Length(Command.Params) = 2) and (Command.Params[0] = 1) and
      (Command.Params[1] = 1), 'empty cursor parameters must default to 1');
    Command := FindCommand(Commands, apcEraseDisplay);
    Check((Length(Command.Params) = 1) and (Command.Params[0] = 0),
      'empty erase parameter must default to 0');
    Command := FindCommand(Commands, apcResetPrivateMode);
    Check((Length(Command.Params) = 1) and (Command.Params[0] = 25),
      'private CSI parameter mismatch');

    Parser.Reset;
    ProcessText(Parser, Buffer, #27'[?25l'#27'[?1049h');
    Check(Buffer.IsAlternateBuffer,
      'alternate buffer was not activated');
    Check(not Buffer.Cursor.Visible,
      'alternate buffer switch restored a hidden cursor');
    ProcessText(Parser, Buffer, #27'[?25h'#27'[?1049l');
    Check(not Buffer.IsAlternateBuffer,
      'main buffer was not restored');
    Check(Buffer.Cursor.Visible,
      'main buffer switch lost visible cursor mode');

    Parser.Reset;
    Parser.Parse(#27'[1p', Commands);
    Check(Length(Commands) = 0,
      'CSI p without ! was incorrectly parsed as soft reset');
    Parser.Parse(#27'[!p', Commands);
    Check((Length(Commands) = 1) and
      (Commands[0].Command = apcSoftTerminalReset),
      'DECSTR CSI ! p was not parsed as soft reset');

    Parser.Reset;
    ProcessText(Parser, Buffer, #27'[3 q');
    Check((Buffer.Cursor.Shape = tcsUnderline) and Buffer.Cursor.Blink,
      'DECSCUSR blinking underline was not applied');
    ProcessText(Parser, Buffer, #27'[6 q');
    Check((Buffer.Cursor.Shape = tcsBar) and not Buffer.Cursor.Blink,
      'DECSCUSR steady bar was not applied');
    ProcessText(Parser, Buffer, #27'[2 q');
    Check((Buffer.Cursor.Shape = tcsBlock) and not Buffer.Cursor.Blink,
      'DECSCUSR steady block was not applied');

    Parser.Reset;
    Parser.Parse(#27'[38;5;196;48;2;1;2;3m', Commands);
    Command := FindCommand(Commands, apcSetGraphicsMode);
    Check(Command.Attributes.ForegroundSource = tcsIndexed,
      '256-color foreground source mismatch');
    Check(Command.Attributes.ForegroundIndex = 196,
      '256-color foreground index mismatch');
    Check(Command.Attributes.BackgroundSource = tcsRGB,
      'RGB background source mismatch');
    Check(Command.Attributes.BackgroundColor = $FF010203,
      'RGB background color mismatch');

    Parser.Reset;
    Parser.Parse(#27'[38;5;17m', Commands);
    Command := FindCommand(Commands, apcSetGraphicsMode);
    Check(Command.Attributes.ForegroundColor = $FF00005F,
      'xterm color cube level mismatch');
    Parser.Parse(#27'[38;5;232m', Commands);
    Command := FindCommand(Commands, apcSetGraphicsMode);
    Check(Command.Attributes.ForegroundColor = $FF080808,
      'xterm grayscale start mismatch');
    Parser.Parse(#27'[38;5;255m', Commands);
    Command := FindCommand(Commands, apcSetGraphicsMode);
    Check(Command.Attributes.ForegroundColor = $FFEEEEEE,
      'xterm grayscale end mismatch');

    Parser.Reset;
    Source := #27'(0';
    for I := $5F to $7E do
      Source := Source + Char(I);
    Parser.Parse(Source, Commands);
    Check(Length(Commands) = Length(ExpectedLineDrawing),
      'line-drawing command count mismatch');
    for I := 0 to High(Commands) do
      Check(Commands[I].Char = ExpectedLineDrawing[I + 1],
        Format('line-drawing mapping mismatch at $%.2x', [$5F + I]));

    TestBatchScroll(Theme);
    TestTextWriting(Theme);
    TestCellEditing(Theme);
    TestTerminalInput;
    TestSelection(Theme);
    TestClipboardHelpers;

    Writeln('PASSED');
  finally
    Buffer.Free;
    Parser.Free;
    NewTheme.Free;
    Theme.Free;
  end;
end.
