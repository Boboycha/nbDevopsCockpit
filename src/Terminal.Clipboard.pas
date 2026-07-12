unit Terminal.Clipboard;

interface

type
  TTerminalClipboard = record
  public
    class function CopyText(const Text: string): Boolean; static;
    class function ReadText(out Text: string): Boolean; static;
    class function NormalizeLineEndings(const Text: string): string; static;
    class function WrapBracketedPaste(const Text: string): string; static;
  end;

implementation

uses
  System.Rtti, System.SysUtils, System.Classes, FMX.Platform;

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

class function TTerminalClipboard.NormalizeLineEndings(
  const Text: string): string;
var
  I: Integer;
  Builder: TStringBuilder;
begin
  if Pos(#10, Text) = 0 then
    Exit(Text);

  Builder := TStringBuilder.Create(Length(Text));
  try
    I := 1;
    while I <= Length(Text) do
    begin
      if Text[I] = #10 then
        Builder.Append(#13)
      else if (Text[I] = #13) and (I < Length(Text)) and
        (Text[I + 1] = #10) then
      begin
        Builder.Append(#13);
        Inc(I);
      end
      else
        Builder.Append(Text[I]);
      Inc(I);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
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
