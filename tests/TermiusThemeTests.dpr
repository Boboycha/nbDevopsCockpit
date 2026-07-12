program TermiusThemeTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Terminal.Theme,
  GoghThemeLoader;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

var
  Theme: TTerminalTheme;
  ErrorMessage: string;
begin
  Theme := TTerminalTheme.Create;
  try
    Check(TGoghThemeLoader.LoadIntoTheme(
      'demo\themes\termius\Termius Dark.yml', Theme, ErrorMessage),
      ErrorMessage);
    Check(Theme.DefaultBG = $FF141729, 'background mismatch');
    Check(Theme.DefaultFG = $FF21B568, 'foreground mismatch');
    Check(Theme.CursorColor = $FF21B568, 'cursor mismatch');
    Check(Theme.SelectionColor = $8021B568, 'selection RGBA mismatch');
    Check(Theme.TerminalUIColor = $FF8D91A5, 'terminal UI mismatch');
    Check(Theme.AnsiColors[0] = $FF343851, 'ANSI color 0 mismatch');
    Check(Theme.AnsiColors[15] = $FFFFFFFF, 'ANSI color 15 mismatch');
    Writeln('PASSED');
  finally
    Theme.Free;
  end;
end.
