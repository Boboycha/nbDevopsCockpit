unit Terminal.Clipboard;

interface

type
  TTerminalClipboard = record
  public
    class function CopyText(const Text: string): Boolean; static;
    class function ReadText(out Text: string): Boolean; static;
    class function WrapBracketedPaste(const Text: string): string; static;
  end;

implementation

uses
  System.Rtti, FMX.Platform;

class function TTerminalClipboard.CopyText(const Text: string): Boolean;
var
  ClipboardService: IFMXClipboardService;
begin
  Result := False;
  if Text = '' then
    Exit;

  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService,
    ClipboardService) then
  begin
    ClipboardService.SetClipboard(Text);
    Result := True;
  end;
end;

class function TTerminalClipboard.ReadText(out Text: string): Boolean;
var
  ClipboardService: IFMXClipboardService;
  Value: TValue;
begin
  Text := '';
  Result := False;

  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService,
    ClipboardService) then
  begin
    Value := ClipboardService.GetClipboard;
    if not Value.IsEmpty then
      Text := Value.ToString;
    Result := Text <> '';
  end;
end;

class function TTerminalClipboard.WrapBracketedPaste(
  const Text: string): string;
begin
  Result := #27'[200~' + Text + #27'[201~';
end;

end.
