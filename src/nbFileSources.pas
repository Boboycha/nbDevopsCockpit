unit nbFileSources;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.IOUtils,
  nbSFTPClient;

type
  TnbFileEntry = record
    Name: string;
    IsDir: Boolean;
    Size: Int64;
    Modified: TDateTime;
    Permissions: Cardinal;
  end;
  TnbFileEntryArray = array of TnbFileEntry;

  TnbFileListingEvent = procedure(Sender: TObject; const APath: string;
    const AEntries: TnbFileEntryArray) of object;
  TnbFileErrorEvent = procedure(Sender: TObject; const AMsg: string) of object;

  InbFileSource = interface
    ['{6F1B6A20-2C44-4E2C-9E51-1B8D7F2A9C01}']
    procedure ListDir(const APath: string);
    function ParentDir(const APath: string): string;
    function Combine(const ADir, AName: string): string;
    procedure MakeDir(const APath: string);
    procedure Rename(const AOldPath, ANewPath: string);
    procedure Delete(const APath: string; AIsDir: Boolean);

    function GetOnListing: TnbFileListingEvent;
    procedure SetOnListing(const AValue: TnbFileListingEvent);
    function GetOnError: TnbFileErrorEvent;
    procedure SetOnError(const AValue: TnbFileErrorEvent);
    function GetOnChanged: TNotifyEvent;
    procedure SetOnChanged(const AValue: TNotifyEvent);

    property OnListing: TnbFileListingEvent read GetOnListing write SetOnListing;
    property OnError: TnbFileErrorEvent read GetOnError write SetOnError;
    property OnChanged: TNotifyEvent read GetOnChanged write SetOnChanged;
  end;

  TnbFileSourceBase = class(TInterfacedObject, InbFileSource)
  protected
    FOnListing: TnbFileListingEvent;
    FOnError: TnbFileErrorEvent;
    FOnChanged: TNotifyEvent;
    procedure DoListing(const APath: string; const AEntries: TnbFileEntryArray);
    procedure DoError(const AMsg: string);
    procedure DoChanged;
  public
    procedure ListDir(const APath: string); virtual; abstract;
    function ParentDir(const APath: string): string; virtual; abstract;
    function Combine(const ADir, AName: string): string; virtual; abstract;
    procedure MakeDir(const APath: string); virtual; abstract;
    procedure Rename(const AOldPath, ANewPath: string); virtual; abstract;
    procedure Delete(const APath: string; AIsDir: Boolean); virtual; abstract;

    function GetOnListing: TnbFileListingEvent;
    procedure SetOnListing(const AValue: TnbFileListingEvent);
    function GetOnError: TnbFileErrorEvent;
    procedure SetOnError(const AValue: TnbFileErrorEvent);
    function GetOnChanged: TNotifyEvent;
    procedure SetOnChanged(const AValue: TNotifyEvent);
  end;

  TnbLocalFileSource = class(TnbFileSourceBase)
  public
    procedure ListDir(const APath: string); override;
    function ParentDir(const APath: string): string; override;
    function Combine(const ADir, AName: string): string; override;
    procedure MakeDir(const APath: string); override;
    procedure Rename(const AOldPath, ANewPath: string); override;
    procedure Delete(const APath: string; AIsDir: Boolean); override;
  end;

  TnbSFTPFileSource = class(TnbFileSourceBase)
  private
    FClient: TnbSFTPClient;
    FPendingPath: string;
    procedure HandleDirListing(Sender: TObject; const APath: string;
      const AEntries: TSFTPEntryArray);
    procedure HandleOpDone(Sender: TObject);
    procedure HandleError(Sender: TObject; const AMsg: string);
  public
    constructor Create(AClient: TnbSFTPClient);
    procedure ListDir(const APath: string); override;
    function ParentDir(const APath: string): string; override;
    function Combine(const ADir, AName: string): string; override;
    procedure MakeDir(const APath: string); override;
    procedure Rename(const AOldPath, ANewPath: string); override;
    procedure Delete(const APath: string; AIsDir: Boolean); override;
  end;

implementation

{ TnbFileSourceBase }

procedure TnbFileSourceBase.DoListing(const APath: string;
  const AEntries: TnbFileEntryArray);
begin
  if Assigned(FOnListing) then
    FOnListing(Self, APath, AEntries);
end;

procedure TnbFileSourceBase.DoError(const AMsg: string);
begin
  if Assigned(FOnError) then
    FOnError(Self, AMsg);
end;

procedure TnbFileSourceBase.DoChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TnbFileSourceBase.GetOnListing: TnbFileListingEvent;
begin
  Result := FOnListing;
end;

procedure TnbFileSourceBase.SetOnListing(const AValue: TnbFileListingEvent);
begin
  FOnListing := AValue;
end;

function TnbFileSourceBase.GetOnError: TnbFileErrorEvent;
begin
  Result := FOnError;
end;

procedure TnbFileSourceBase.SetOnError(const AValue: TnbFileErrorEvent);
begin
  FOnError := AValue;
end;

function TnbFileSourceBase.GetOnChanged: TNotifyEvent;
begin
  Result := FOnChanged;
end;

procedure TnbFileSourceBase.SetOnChanged(const AValue: TNotifyEvent);
begin
  FOnChanged := AValue;
end;

{ TnbLocalFileSource }

procedure TnbLocalFileSource.ListDir(const APath: string);
var
  Dirs, Files: TStringDynArray;
  Entries: TnbFileEntryArray;
  I, N: Integer;
begin
  if Trim(APath) = '' then
  begin
    Dirs := TDirectory.GetLogicalDrives;
    SetLength(Entries, Length(Dirs));
    for I := 0 to High(Dirs) do
    begin
      Entries[I].Name := IncludeTrailingPathDelimiter(Dirs[I]);
      Entries[I].IsDir := True;
      Entries[I].Size := 0;
      Entries[I].Modified := 0;
      Entries[I].Permissions := 0;
    end;
    DoListing('', Entries);
    Exit;
  end;

  try
    Dirs := TDirectory.GetDirectories(APath);
    Files := TDirectory.GetFiles(APath);
  except
    on E: Exception do
    begin
      DoError(E.Message);
      Exit;
    end;
  end;

  SetLength(Entries, Length(Dirs) + Length(Files));
  N := 0;
  for I := 0 to High(Dirs) do
  begin
    Entries[N].Name := System.IOUtils.TPath.GetFileName(Dirs[I]);
    Entries[N].IsDir := True;
    Entries[N].Size := 0;
    Entries[N].Modified := 0;
    Entries[N].Permissions := 0;
    Inc(N);
  end;
  for I := 0 to High(Files) do
  begin
    Entries[N].Name := System.IOUtils.TPath.GetFileName(Files[I]);
    Entries[N].IsDir := False;
    try
      Entries[N].Size := TFile.GetSize(Files[I]);
    except
      Entries[N].Size := 0;
    end;
    Entries[N].Modified := 0;
    Entries[N].Permissions := 0;
    Inc(N);
  end;

  DoListing(APath, Entries);
end;

function TnbLocalFileSource.ParentDir(const APath: string): string;
begin
  if Trim(APath) = '' then
    Exit('');

  if SameText(IncludeTrailingPathDelimiter(APath),
    IncludeTrailingPathDelimiter(ExtractFileDrive(APath))) then
    Exit('');

  Result := TDirectory.GetParent(ExcludeTrailingPathDelimiter(APath));
end;

function TnbLocalFileSource.Combine(const ADir, AName: string): string;
begin
  if Trim(ADir) = '' then
    Result := AName
  else
    Result := System.IOUtils.TPath.Combine(ADir, AName);
end;

procedure TnbLocalFileSource.MakeDir(const APath: string);
begin
  try
    TDirectory.CreateDirectory(APath);
    DoChanged;
  except
    on E: Exception do DoError(E.Message);
  end;
end;

procedure TnbLocalFileSource.Rename(const AOldPath, ANewPath: string);
begin
  try
    if TDirectory.Exists(AOldPath) then
      TDirectory.Move(AOldPath, ANewPath)
    else
      TFile.Move(AOldPath, ANewPath);
    DoChanged;
  except
    on E: Exception do DoError(E.Message);
  end;
end;

procedure TnbLocalFileSource.Delete(const APath: string; AIsDir: Boolean);
begin
  try
    if AIsDir then
      TDirectory.Delete(APath, True)
    else
      TFile.Delete(APath);
    DoChanged;
  except
    on E: Exception do DoError(E.Message);
  end;
end;

{ TnbSFTPFileSource }

constructor TnbSFTPFileSource.Create(AClient: TnbSFTPClient);
begin
  inherited Create;
  FClient := AClient;
  FClient.OnDirListing := HandleDirListing;
  FClient.OnOpDone := HandleOpDone;
  FClient.OnError := HandleError;
end;

procedure TnbSFTPFileSource.HandleDirListing(Sender: TObject;
  const APath: string; const AEntries: TSFTPEntryArray);
var
  Entries: TnbFileEntryArray;
  I: Integer;
begin
  SetLength(Entries, Length(AEntries));
  for I := 0 to High(AEntries) do
  begin
    Entries[I].Name := AEntries[I].Name;
    Entries[I].IsDir := AEntries[I].IsDir;
    Entries[I].Size := AEntries[I].Size;
    Entries[I].Modified := AEntries[I].Modified;
    Entries[I].Permissions := AEntries[I].Permissions;
  end;
  DoListing(APath, Entries);
end;

procedure TnbSFTPFileSource.HandleOpDone(Sender: TObject);
begin
  DoChanged;
end;

procedure TnbSFTPFileSource.HandleError(Sender: TObject; const AMsg: string);
begin
  DoError(AMsg);
end;

procedure TnbSFTPFileSource.ListDir(const APath: string);
begin
  FPendingPath := APath;
  FClient.ListDir(APath);
end;

function TnbSFTPFileSource.ParentDir(const APath: string): string;
var
  P: Integer;
  S: string;
begin
  S := APath;
  if (Length(S) > 1) and (S[High(S)] = '/') then
    SetLength(S, Length(S) - 1);
  P := S.LastDelimiter('/');
  if P <= 0 then
    Result := '/'
  else
    Result := Copy(S, 1, P);
  if Result = '' then
    Result := '/';
end;

function TnbSFTPFileSource.Combine(const ADir, AName: string): string;
begin
  if (ADir = '') or (ADir = '/') then
    Result := '/' + AName
  else if ADir[High(ADir)] = '/' then
    Result := ADir + AName
  else
    Result := ADir + '/' + AName;
end;

procedure TnbSFTPFileSource.MakeDir(const APath: string);
begin
  FClient.MakeDir(APath);
end;

procedure TnbSFTPFileSource.Rename(const AOldPath, ANewPath: string);
begin
  FClient.Rename(AOldPath, ANewPath);
end;

procedure TnbSFTPFileSource.Delete(const APath: string; AIsDir: Boolean);
begin
  if AIsDir then
    FClient.RemoveDir(APath)
  else
    FClient.Delete(APath);
end;

end.
