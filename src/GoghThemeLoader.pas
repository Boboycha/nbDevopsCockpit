unit GoghThemeLoader;

(*
  Загрузчик цветовых тем терминала из файлов формата Gogh (YAML).
  Проект Gogh: https://github.com/Gogh-Co/Gogh

  Ожидаемая структура .yml файла:

    ---
    name: 'Dracula'
    author: '...'
    variant: 'dark'

    color_01: '#000000'  # Black
    color_02: '#ff5555'  # Red
    ...
    color_16: '#e6e6e6'  # Bright White

    background: '#282a36'
    foreground: '#f8f8f2'
    cursor: '#f8f8f0'

  Использование:

    // Список тем в папке (для выпадающего списка в UI)
    Names := TGoghThemeLoader.EnumThemes('themes\');

    // Загрузка конкретной темы
    TGoghThemeLoader.LoadIntoTheme('themes\Dracula.yml', MyTheme);

  Парсер намеренно упрощён: формат Gogh — это плоский набор пар "ключ: значение",
  поэтому полноценный YAML-разбор не нужен.
*)

interface

uses
  System.Classes, System.SysUtils, System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Terminal.Theme;

type
  TGoghThemeInfo = record
    FileName: string;     // Полный путь к .yml файлу
    Name: string;         // Значение поля name:, либо имя файла как запасной вариант
    Variant: string;      // 'dark' / 'light' / ''
  end;

  TGoghThemeInfoArray = TArray<TGoghThemeInfo>;

  TGoghThemeLoader = class
  private
    class function StripQuotes(const S: string): string; static;
    class function StripComment(const S: string): string; static;
    class function NormalizeHex(const AHex: string): string; static;
    class function HexToAlphaColor(const AHex: string): UInt32; static;
  public
    // Загружает .yml и применяет цвета к TTerminalTheme.
    // Возвращает True при успехе; AErrorMsg содержит причину отказа.
    class function LoadIntoTheme(const AFileName: string;
      ATheme: TTerminalTheme; out AErrorMsg: string): Boolean; overload; static;
    class function LoadIntoTheme(const AFileName: string;
      ATheme: TTerminalTheme): Boolean; overload; static;

    // Быстро читает только метаданные темы (name, variant) без разбора цветов.
    // Используется для построения списка доступных тем.
    class function PeekInfo(const AFileName: string;
      out AInfo: TGoghThemeInfo): Boolean; static;

    // Перечисляет все .yml/.yaml темы в указанной папке, отсортированные по имени.
    class function EnumThemes(const AFolder: string): TGoghThemeInfoArray; static;
  end;

implementation

class function TGoghThemeLoader.StripQuotes(const S: string): string;
begin
  Result := Trim(S);
  if Length(Result) < 2 then Exit;
  if (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2)
  else if (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

// Отрезает хвостовой YAML-комментарий '# ...', не задевая '#' внутри кавычек
// (символ '#' встречается в hex-кодах цветов вида '#282a36').
class function TGoghThemeLoader.StripComment(const S: string): string;
var
  i: Integer;
  InQuote: Char;
begin
  Result := S;
  InQuote := #0;
  for i := 1 to Length(S) do
  begin
    if InQuote <> #0 then
    begin
      if S[i] = InQuote then
        InQuote := #0;
    end
    else
    begin
      if (S[i] = '''') or (S[i] = '"') then
        InQuote := S[i]
      else if S[i] = '#' then
      begin
        Result := Trim(Copy(S, 1, i - 1));
        Exit;
      end;
    end;
  end;
end;

// Приводит hex-цвет к виду AARRGGBB (8 символов). 6-значный RGB дополняется
// непрозрачной альфой; некорректное значение превращается в чёрный.
class function TGoghThemeLoader.NormalizeHex(const AHex: string): string;
var
  S: string;
begin
  S := StripQuotes(AHex);
  if S.StartsWith('#') then
    Delete(S, 1, 1);
  S := UpperCase(Trim(S));

  if Length(S) = 6 then
    Result := 'FF' + S
  else if Length(S) = 8 then
    Result := S
  else
    Result := 'FF000000';
end;

class function TGoghThemeLoader.HexToAlphaColor(const AHex: string): UInt32;
var
  S: string;
begin
  S := NormalizeHex(AHex);
  Result := $FF000000;
  try
    Result := StrToUInt64('$' + S);
  except
    // некорректное значение — оставляем чёрный по умолчанию
  end;
end;

class function TGoghThemeLoader.LoadIntoTheme(const AFileName: string;
  ATheme: TTerminalTheme; out AErrorMsg: string): Boolean;
var
  Lines: TStringList;
  Line, Key, Value, IdxStr: string;
  ColonPos, ColorIdx, FilledColors, i: Integer;
  HasBG, HasFG: Boolean;
  ColorValues: array[0..15] of string;
  BGValue, FGValue: string;
begin
  Result := False;
  AErrorMsg := '';
  HasBG := False;
  HasFG := False;
  FilledColors := 0;
  for i := 0 to 15 do
    ColorValues[i] := '';

  if not TFile.Exists(AFileName) then
  begin
    AErrorMsg := 'File not found: ' + AFileName;
    Exit;
  end;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFileName, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        AErrorMsg := 'Cannot read file: ' + E.Message;
        Exit;
      end;
    end;

    for Line in Lines do
    begin
      var L := Trim(Line);
      if L = '' then Continue;
      if L = '---' then Continue;
      if L.StartsWith('#') then Continue;

      L := StripComment(L);
      if L = '' then Continue;

      ColonPos := Pos(':', L);
      if ColonPos < 2 then Continue;

      Key := LowerCase(Trim(Copy(L, 1, ColonPos - 1)));
      Value := Trim(Copy(L, ColonPos + 1, MaxInt));

      if Key = 'name' then
        // Имя темы здесь не применяем: у TTerminalTheme.Name нет публичного
        // сеттера. Для списка тем имя извлекает PeekInfo.
      else if Key = 'background' then
      begin
        BGValue := Value;
        HasBG := True;
      end
      else if Key = 'foreground' then
      begin
        FGValue := Value;
        HasFG := True;
      end
      else if Key.StartsWith('color_') then
      begin
        IdxStr := Copy(Key, 7, MaxInt);
        if not TryStrToInt(IdxStr, ColorIdx) then Continue;
        Dec(ColorIdx); // в Gogh нумерация с 1, в палитре ANSI — с 0
        if (ColorIdx < 0) or (ColorIdx > 15) then Continue;
        if ColorValues[ColorIdx] = '' then
          Inc(FilledColors);
        ColorValues[ColorIdx] := Value;
      end;
      // поля author, variant, cursor игнорируем
    end;

    if not HasBG or not HasFG then
    begin
      AErrorMsg := 'Missing required field background or foreground';
      Exit;
    end;
    if FilledColors < 16 then
    begin
      AErrorMsg := Format('Missing %d of 16 ANSI colors', [16 - FilledColors]);
      Exit;
    end;

    // Все поля собраны — переносим цвета в тему
    ATheme.DefaultBG := HexToAlphaColor(BGValue);
    ATheme.DefaultFG := HexToAlphaColor(FGValue);
    for i := 0 to 15 do
      ATheme.AnsiColors[i] := HexToAlphaColor(ColorValues[i]);

    Result := True;
  finally
    Lines.Free;
  end;
end;

class function TGoghThemeLoader.LoadIntoTheme(const AFileName: string;
  ATheme: TTerminalTheme): Boolean;
var
  Dummy: string;
begin
  Result := LoadIntoTheme(AFileName, ATheme, Dummy);
end;

class function TGoghThemeLoader.PeekInfo(const AFileName: string;
  out AInfo: TGoghThemeInfo): Boolean;
var
  Lines: TStringList;
  Line, Key, Value: string;
  ColonPos, LineNo: Integer;
begin
  Result := False;
  AInfo := Default(TGoghThemeInfo);
  AInfo.FileName := AFileName;
  AInfo.Name := TPath.GetFileNameWithoutExtension(AFileName);

  if not TFile.Exists(AFileName) then Exit;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(AFileName, TEncoding.UTF8);
    except
      Exit;
    end;

    LineNo := 0;
    for Line in Lines do
    begin
      Inc(LineNo);
      if LineNo > 30 then Break;  // метаданные всегда в начале файла — дальше не читаем

      var L := Trim(Line);
      if L = '' then Continue;
      if L = '---' then Continue;
      if L.StartsWith('#') then Continue;

      L := StripComment(L);
      ColonPos := Pos(':', L);
      if ColonPos < 2 then Continue;

      Key := LowerCase(Trim(Copy(L, 1, ColonPos - 1)));
      Value := StripQuotes(Trim(Copy(L, ColonPos + 1, MaxInt)));

      if Key = 'name' then
        AInfo.Name := Value
      else if Key = 'variant' then
        AInfo.Variant := Value;
    end;

    Result := True;
  finally
    Lines.Free;
  end;
end;

class function TGoghThemeLoader.EnumThemes(const AFolder: string): TGoghThemeInfoArray;
var
  Files: TArray<string>;
  Info: TGoghThemeInfo;
  List: TList<TGoghThemeInfo>;
  F: string;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then Exit;

  List := TList<TGoghThemeInfo>.Create;
  try
    Files := TDirectory.GetFiles(AFolder, '*.yml');
    for F in Files do
    begin
      if PeekInfo(F, Info) then
        List.Add(Info);
    end;

    // заодно подхватываем .yaml — встречается как альтернативное расширение
    Files := TDirectory.GetFiles(AFolder, '*.yaml');
    for F in Files do
    begin
      if PeekInfo(F, Info) then
        List.Add(Info);
    end;

    // сортируем по имени темы — для удобного выбора в UI
    List.Sort(TComparer<TGoghThemeInfo>.Construct(
      function(const A, B: TGoghThemeInfo): Integer
      begin
        Result := CompareText(A.Name, B.Name);
      end));

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
