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
      Result := #27'[1;' + IntToStr(ModifierParam) + FinalChar
    else
      Result := #27 + 'O' + FinalChar;
  end;

  function CSIKey(const FinalChar: Char): string;
  begin
    if HasKeyModifier then
      Result := #27'[1;' + IntToStr(ModifierParam) + FinalChar
    else
      Result := #27 + '[' + FinalChar;
  end;

  function TildeKey(const Code: Integer): string;
  begin
    if HasKeyModifier then
      Result := #27'[' + IntToStr(Code) + ';' + IntToStr(ModifierParam) + '~'
    else
      Result := #27'[' + IntToStr(Code) + '~';
  end;

  function ControlCharacter: string;
  var
    C: WideChar;
  begin
    Result := '';
    if not (ssCtrl in Shift) then
      Exit;

    case KeyChar of
      ' ', '@': C := #0;
      'a'..'z': C := WideChar(Ord(KeyChar) - Ord('a') + 1);
      'A'..'Z': C := WideChar(Ord(KeyChar) - Ord('A') + 1);
      '[': C := #27;
      '\': C := #28;
      ']': C := #29;
      '^': C := #30;
      '_': C := #31;
      '?': C := #127;
    else
      if (KeyChar <> #0) and (Ord(KeyChar) >= 32) then
        Exit;
      if (Key >= Ord('A')) and (Key <= Ord('Z')) then
        C := WideChar(Key - Ord('A') + 1)
      else
        Exit;
    end;
    Result := string(C);
  end;

begin
  Result := '';

  Result := ControlCharacter;
  if Result <> '' then
  begin
    if ssAlt in Shift then
      Result := #27 + Result;
    Exit;
  end;

  if (ssAlt in Shift) and (KeyChar <> #0) then
  begin
    if (ssCtrl in Shift) and (Ord(KeyChar) >= 32) then
      Result := string(KeyChar)
    else
      Result := #27 + string(KeyChar);
    Exit;
  end;

  case Key of
    vkReturn: Result := #13;
    vkBack: Result := #127;
    vkTab:
      if ssShift in Shift then
      begin
        if (Shift * [ssAlt, ssCtrl]) <> [] then
          Result := CSIKey('Z')
        else
          Result := #27 + '[Z';
      end
      else
        Result := #9;
    vkEscape: Result := #27;

    vkUp:
      if HasKeyModifier then Result := CSIKey('A')
      else if AppCursorKeys then Result := #27 + 'OA'
      else Result := #27 + '[A';
    vkDown:
      if HasKeyModifier then Result := CSIKey('B')
      else if AppCursorKeys then Result := #27 + 'OB'
      else Result := #27 + '[B';
    vkRight:
      if HasKeyModifier then Result := CSIKey('C')
      else if AppCursorKeys then Result := #27 + 'OC'
      else Result := #27 + '[C';
    vkLeft:
      if HasKeyModifier then Result := CSIKey('D')
      else if AppCursorKeys then Result := #27 + 'OD'
      else Result := #27 + '[D';

    vkHome:
      if AppCursorKeys and not HasKeyModifier then
        Result := SS3Key('H')
      else
        Result := CSIKey('H');
    vkEnd:
      if AppCursorKeys and not HasKeyModifier then
        Result := SS3Key('F')
      else
        Result := CSIKey('F');
    vkInsert: Result := TildeKey(2);
    vkDelete: Result := TildeKey(3);
    vkPrior: Result := TildeKey(5);
    vkNext: Result := TildeKey(6);

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

  function SGRReport(const Button: Integer; const FinalChar: Char): string;
  begin
    Result := #27'[<' + IntToStr(Button) + ';' + IntToStr(Cx) + ';' +
      IntToStr(Cy) + FinalChar;
  end;

begin
  Result := '';
  Cx := Max(1, ACol);
  Cy := Max(1, ARow);
  ShiftMod := 0;
  if ssShift in AShift then Inc(ShiftMod, 4);
  if ssAlt in AShift then Inc(ShiftMod, 8);
  if ssCtrl in AShift then Inc(ShiftMod, 16);

  if mtm1006_SGR in AMouseModes then
  begin
    Cb := AButton + ShiftMod;
    case AState of
      mbsDown:
        Result := SGRReport(Cb, 'M');
      mbsUp:
        Result := SGRReport(Cb, 'm');
      mbsMove:
        if (mtm1003_Any in AMouseModes) or
          ((mtm1002_Wheel in AMouseModes) and InRange(AButton, 0, 2)) then
          Result := SGRReport(Cb + 32, 'M');
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
    else if (AState = mbsMove) and
      ((mtm1003_Any in AMouseModes) or
      ((mtm1002_Wheel in AMouseModes) and InRange(AButton, 0, 2))) then
      Cb := AButton + 32
    else if AState = mbsUp then
      Cb := 3
    else if AState = mbsDown then
      Cb := AButton
    else
      Exit;

    Cb := Cb + ShiftMod;
    Cx := Min(Cx, 255 - 32) + 32;
    Cy := Min(Cy, 255 - 32) + 32;

    Result := #27'[' + 'M' + Char(Cb + 32) + Char(Cx) + Char(Cy);
  end;
end;

end.
