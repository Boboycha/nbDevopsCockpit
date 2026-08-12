unit Syntax.Code.Shell;

interface

uses
  System.SysUtils, Syntax.Code, FMX.TextLayout, FMX.Graphics, System.UITypes;

(* Регистрация вызывается явно из nbCodeEditor.pas - см. комментарий в
   Syntax.Code.Pascal.pas (риск отбрасывания юнита smart-linker'ом). *)
procedure RegisterShellSyntax;

type
  TCodeSyntaxShell = class(TCodeSyntax)
  private
    FKeyWords: TKeyWords;
    FStringKey, FNumberKey, FCommentKey, FVariableKey, FPunctuationKey: TKeyWord;
    procedure AddRange(var AResult: TArray<TTextAttributedRangeData>;
      AStart, ALength: Integer; AKey: TKeyWord);
  public
    constructor Create(DefaultFont: TFont; DefaultColor: TAlphaColor); override;
    destructor Destroy; override;
    function GetAttributesForLine(const Line: string;
      const Index: Integer): TArray<TTextAttributedRangeData>; override;
  end;

implementation

constructor TCodeSyntaxShell.Create(DefaultFont: TFont; DefaultColor: TAlphaColor);
var
  KeyWord: TKeyWord;
begin
  inherited;

  FKeyWords := TKeyWords.Create;

  KeyWord := TKeyWord.Create;
  KeyWord.Word := ['if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until',
    'do', 'done', 'case', 'esac', 'in', 'function', 'select', 'time'];
  KeyWord.Color := TCodeSyntax.Palette.KeywordAlt;
  KeyWord.Font.Assign(FDefaultFont);
  KeyWord.Font.Style := [TFontStyle.fsBold];
  FKeyWords.Add(KeyWord);

  KeyWord := TKeyWord.Create;
  KeyWord.Word := ['true', 'false', 'return', 'exit', 'break', 'continue',
    'local', 'readonly', 'export', 'set', 'unset', 'shift', 'trap', 'source',
    'eval', 'exec', 'test'];
  KeyWord.Color := TCodeSyntax.Palette.Keyword;
  KeyWord.Font.Assign(FDefaultFont);
  KeyWord.Font.Style := [TFontStyle.fsBold];
  FKeyWords.Add(KeyWord);

  KeyWord := TKeyWord.Create;
  KeyWord.Word := ['echo', 'printf', 'cat', 'grep', 'egrep', 'fgrep', 'awk',
    'sed', 'cut', 'sort', 'uniq', 'head', 'tail', 'xargs', 'find', 'ls', 'cd',
    'pwd', 'mkdir', 'rm', 'mv', 'cp', 'chmod', 'chown', 'ln', 'tar', 'gzip',
    'curl', 'wget', 'ssh', 'scp', 'rsync', 'systemctl', 'journalctl',
    'docker', 'podman', 'kubectl', 'psql', 'python', 'python3', 'node', 'npm',
    'git', 'sudo'];
  KeyWord.Color := TCodeSyntax.Palette.FunctionColor;
  KeyWord.Font.Assign(FDefaultFont);
  FKeyWords.Add(KeyWord);

  FStringKey := TKeyWord.Create;
  FStringKey.Color := TCodeSyntax.Palette.StringColor;
  FStringKey.Font.Assign(FDefaultFont);

  FNumberKey := TKeyWord.Create;
  FNumberKey.Color := TCodeSyntax.Palette.NumberColor;
  FNumberKey.Font.Assign(FDefaultFont);

  FCommentKey := TKeyWord.Create;
  FCommentKey.Color := TCodeSyntax.Palette.CommentColor;
  FCommentKey.Font.Assign(FDefaultFont);

  FVariableKey := TKeyWord.Create;
  FVariableKey.Color := TCodeSyntax.Palette.FieldColor;
  FVariableKey.Font.Assign(FDefaultFont);

  FPunctuationKey := TKeyWord.Create;
  FPunctuationKey.Color := TCodeSyntax.Palette.PunctuationColor;
  FPunctuationKey.Font.Assign(FDefaultFont);
end;

destructor TCodeSyntaxShell.Destroy;
begin
  FPunctuationKey.Free;
  FVariableKey.Free;
  FCommentKey.Free;
  FNumberKey.Free;
  FStringKey.Free;
  FKeyWords.Free;
  inherited;
end;

procedure TCodeSyntaxShell.AddRange(var AResult: TArray<TTextAttributedRangeData>;
  AStart, ALength: Integer; AKey: TKeyWord);
begin
  if (AKey = nil) or (ALength <= 0) then
    Exit;
  AResult := AResult + [TTextAttributedRangeData.Create(
    TTextRange.Create(AStart, ALength),
    TTextAttribute.Create(AKey.Font, AKey.Color))];
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-', '/']);
end;

function IsDigitChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

function TCodeSyntaxShell.GetAttributesForLine(const Line: string;
  const Index: Integer): TArray<TTextAttributedRangeData>;
var
  I, Start, Len: Integer;
  Quote: Char;
  Word: string;
  KeyWord: TKeyWord;
begin
  if FCached.TryGetValue(Index, Result) then
    Exit;

  try
    SetLength(Result, 0);
    I := 1;
    while I <= Line.Length do
    begin
      if (Line[I] = '#') then
      begin
        if (I = 1) and (Line.Length >= 2) and (Line[2] = '!') then
          AddRange(Result, 0, Line.Length, FVariableKey)
        else
          AddRange(Result, I - 1, Line.Length - I + 1, FCommentKey);
        Break;
      end;

      if CharInSet(Line[I], ['''', '"']) then
      begin
        Quote := Line[I];
        Start := I;
        Inc(I);
        while I <= Line.Length do
        begin
          if (Quote = '"') and (Line[I] = '\') and (I < Line.Length) then
          begin
            Inc(I, 2);
            Continue;
          end;
          if Line[I] = Quote then
          begin
            Inc(I);
            Break;
          end;
          Inc(I);
        end;
        AddRange(Result, Start - 1, I - Start, FStringKey);
        Continue;
      end;

      if Line[I] = '$' then
      begin
        Start := I;
        Inc(I);
        if (I <= Line.Length) and (Line[I] = '{') then
        begin
          Inc(I);
          while (I <= Line.Length) and (Line[I] <> '}') do
            Inc(I);
          if I <= Line.Length then
            Inc(I);
        end
        else if (I <= Line.Length) and (Line[I] = '(') then
        begin
          Inc(I);
          while (I <= Line.Length) and (Line[I] <> ')') do
            Inc(I);
          if I <= Line.Length then
            Inc(I);
        end
        else
          while (I <= Line.Length) and CharInSet(Line[I],
            ['A'..'Z', 'a'..'z', '0'..'9', '_', '?', '#', '@', '*', '!']) do
            Inc(I);
        AddRange(Result, Start - 1, I - Start, FVariableKey);
        Continue;
      end;

      if IsDigitChar(Line[I]) then
      begin
        Start := I;
        while (I <= Line.Length) and CharInSet(Line[I], ['0'..'9', '.']) do
          Inc(I);
        AddRange(Result, Start - 1, I - Start, FNumberKey);
        Continue;
      end;

      if IsWordChar(Line[I]) then
      begin
        Start := I;
        while (I <= Line.Length) and IsWordChar(Line[I]) do
          Inc(I);
        Len := I - Start;
        Word := Copy(Line, Start, Len);
        if FKeyWords.FindWord(Word, KeyWord) then
          AddRange(Result, Start - 1, Len, KeyWord);
        Continue;
      end;

      if CharInSet(Line[I], ['|', '&', ';', '<', '>', '(', ')', '{', '}',
        '[', ']', '=', '!', '*']) then
        AddRange(Result, I - 1, 1, FPunctuationKey);
      Inc(I);
    end;
  finally
    FCached.AddOrSetValue(Index, Result);
  end;
end;

procedure RegisterShellSyntax;
begin
  TCodeSyntax.RegisterSyntax(['shell', 'sh', 'bash', 'zsh'], TCodeSyntaxShell);
end;

end.
