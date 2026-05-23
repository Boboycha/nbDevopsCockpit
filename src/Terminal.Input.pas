unit Terminal.Input;

interface

uses
  System.SysUtils, System.Classes, System.UITypes, FMX.Types, FMX.Consts,
  Terminal.Types;

type
  TMouseButtonState = (mbsDown, mbsUp, mbsMove);

  TTerminalInput = record
  public
    class function TranslateKey(Key: Word; KeyChar: WideChar;
      Shift: TShiftState; AppCursorKeys: Boolean): string; static;
    class function BuildMouseReport(AButton, ACol, ARow: Integer;
      AShift: TShiftState; AState: TMouseButtonState;
      AMouseModes: TMouseTrackingModes): string; static;
  end;

implementation

uses
  System.Math;

class function TTerminalInput.TranslateKey(Key: Word; KeyChar: WideChar;
  Shift: TShiftState; AppCursorKeys: Boolean): string;

  function ModifierParam: Integer;
  begin
    Result := 1;
    if ssShift in Shift then Inc(Result, 1);
    if ssAlt in Shift then Inc(Result, 2);
    if ssCtrl in Shift then Inc(Result, 4);
  end;

  function HasKeyModifier: Boolean;
  begin
    Result := (Shift * [ssShift, ssAlt, ssCtrl]) <> [];
  end;

  function SS3Key(const FinalChar: Char): string;
  begin
    if HasKeyModifier then
      Result := Format(#27'[1;%d%s', [ModifierParam, string(FinalChar)])
    else
      Result := #27 + 'O' + FinalChar;
  end;

  function TildeKey(const Code: Integer): string;
  begin
    if HasKeyModifier then
      Result := Format(#27'[%d;%d~', [Code, ModifierParam])
    else
      Result := Format(#27'[%d~', [Code]);
  end;

begin
  Result := '';

  if (ssCtrl in Shift) and (Key >= Ord('A')) and (Key <= Ord('Z')) then
  begin
    Result := string(Char(Key - Ord('A') + 1));
    Exit;
  end;

  if (ssAlt in Shift) and (KeyChar <> #0) then
  begin
    Result := #27 + string(KeyChar);
    Exit;
  end;

  case Key of
    vkReturn: Result := #13;
    vkBack: Result := #127;
    vkTab: Result := #9;
    vkEscape: Result := #27;

    vkUp:
      if AppCursorKeys then Result := #27 + 'OA' else Result := #27 + '[A';
    vkDown:
      if AppCursorKeys then Result := #27 + 'OB' else Result := #27 + '[B';
    vkRight:
      if AppCursorKeys then Result := #27 + 'OC' else Result := #27 + '[C';
    vkLeft:
      if AppCursorKeys then Result := #27 + 'OD' else Result := #27 + '[D';

    vkHome: Result := #27 + '[H';
    vkEnd: Result := #27 + '[F';
    vkInsert: Result := #27 + '[2~';
    vkDelete: Result := #27 + '[3~';
    vkPrior: Result := #27 + '[5~';
    vkNext: Result := #27 + '[6~';

    vkF1: Result := SS3Key('P');
    vkF2: Result := SS3Key('Q');
    vkF3: Result := SS3Key('R');
    vkF4: Result := SS3Key('S');
    vkF5: Result := TildeKey(15);
    vkF6: Result := TildeKey(17);
    vkF7: Result := TildeKey(18);
    vkF8: Result := TildeKey(19);
    vkF9: Result := TildeKey(20);
    vkF10: Result := TildeKey(21);
    vkF11: Result := TildeKey(23);
    vkF12: Result := TildeKey(24);
  else
    if (KeyChar <> #0) and (Ord(KeyChar) >= 32) then
      Result := string(KeyChar);
  end;
end;

class function TTerminalInput.BuildMouseReport(AButton, ACol, ARow: Integer;
  AShift: TShiftState; AState: TMouseButtonState;
  AMouseModes: TMouseTrackingModes): string;
var
  Cb, Cx, Cy, ShiftMod: Integer;
begin
  Result := '';
  ShiftMod := 0;
  if ssShift in AShift then Inc(ShiftMod, 4);
  if ssAlt in AShift then Inc(ShiftMod, 8);
  if ssCtrl in AShift then Inc(ShiftMod, 16);

  if mtm1006_SGR in AMouseModes then
  begin
    Cb := AButton + ShiftMod;
    case AState of
      mbsDown:
        Result := Format(#27'[<%d;%d;%dM', [Cb, ACol, ARow]);
      mbsUp:
        Result := Format(#27'[<%d;%d;%dm', [Cb, ACol, ARow]);
      mbsMove:
        if mtm1003_Any in AMouseModes then
          Result := Format(#27'[<%d;%d;%dM', [Cb, ACol, ARow]);
    end;
  end
  else if (mtm1000_Click in AMouseModes) or
     (mtm1002_Wheel in AMouseModes) or
     (mtm1003_Any in AMouseModes) then
  begin
    if (AButton = 64) and (mtm1002_Wheel in AMouseModes) then
      Cb := 64
    else if (AButton = 65) and (mtm1002_Wheel in AMouseModes) then
      Cb := 65
    else if (AState = mbsMove) and (mtm1003_Any in AMouseModes) then
      Cb := AButton + 32
    else if AState = mbsUp then
      Cb := 3
    else if AState = mbsDown then
      Cb := AButton
    else
      Exit;

    Cb := Cb + ShiftMod;
    Cx := Min(Max(1, ACol), 255 - 32) + 32;
    Cy := Min(Max(1, ARow), 255 - 32) + 32;

    Result := #27'[' + 'M' + Char(Cb + 32) + Char(Cx) + Char(Cy);
  end;
end;

end.
