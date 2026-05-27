unit nbSSH.KeyValidation;

interface

uses
  System.SysUtils;

function SSHDetectPublicKeyAlgo(const FirstPubLine: string): string;
function SSHValidatePrivateKeyContent(const KeyText, PubText: string;
  out ErrorMsg: string): Boolean;

implementation

uses
  System.Classes,
  nbSSH.LibSSH2;

function SSHDetectPublicKeyAlgo(const FirstPubLine: string): string;
begin
  Result := '';
  if FirstPubLine.StartsWith('ssh-ed25519 ') then Result := 'ssh-ed25519'
  else if FirstPubLine.StartsWith('ssh-rsa ') then Result := 'ssh-rsa'
  else if FirstPubLine.StartsWith('ecdsa-sha2-nistp256') then Result := 'ecdsa-sha2-nistp256'
  else if FirstPubLine.StartsWith('ecdsa-sha2-nistp384') then Result := 'ecdsa-sha2-nistp384'
  else if FirstPubLine.StartsWith('ecdsa-sha2-nistp521') then Result := 'ecdsa-sha2-nistp521'
  else if FirstPubLine.StartsWith('ssh-dss ') then Result := 'ssh-dss';
end;

function SSHValidatePrivateKeyContent(const KeyText, PubText: string;
  out ErrorMsg: string): Boolean;
const
  MIN_KEY_SIZE = 100;
var
  L, PL: TStringList;
  FirstLine, LastLine: string;
  KeyAlgo, PubLine, PubAlgo, SupportedAlgs: string;
begin
  Result := False;
  ErrorMsg := '';

  if Length(KeyText) < MIN_KEY_SIZE then
  begin
    ErrorMsg := Format('Key data too small (%d bytes) - probably truncated', [Length(KeyText)]);
    Exit;
  end;

  L := TStringList.Create;
  try
    L.Text := KeyText;
    if L.Count = 0 then
    begin
      ErrorMsg := 'Key data is empty';
      Exit;
    end;
    FirstLine := Trim(L[0]);
    LastLine := Trim(L[L.Count - 1]);

    if SSHDetectPublicKeyAlgo(FirstLine) <> '' then
    begin
      ErrorMsg := 'This is a PUBLIC key (' + SSHDetectPublicKeyAlgo(FirstLine) + '). Need PRIVATE key';
      Exit;
    end;

    if Pos('PuTTY-User-Key-File', FirstLine) > 0 then
    begin
      ErrorMsg := 'PuTTY format not supported by libssh2.' + sLineBreak +
                  'Convert: puttygen <file> -O private-openssh -o <file>.openssh';
      Exit;
    end;

    KeyAlgo := '';
    if Pos('-----BEGIN OPENSSH PRIVATE KEY-----', FirstLine) > 0 then
      KeyAlgo := 'openssh'
    else if Pos('-----BEGIN RSA PRIVATE KEY-----', FirstLine) > 0 then
      KeyAlgo := 'ssh-rsa'
    else if Pos('-----BEGIN DSA PRIVATE KEY-----', FirstLine) > 0 then
      KeyAlgo := 'ssh-dss'
    else if Pos('-----BEGIN EC PRIVATE KEY-----', FirstLine) > 0 then
      KeyAlgo := 'ecdsa'
    else if Pos('-----BEGIN ENCRYPTED PRIVATE KEY-----', FirstLine) > 0 then
      KeyAlgo := 'pkcs8-encrypted'
    else if Pos('-----BEGIN PRIVATE KEY-----', FirstLine) > 0 then
      KeyAlgo := 'pkcs8'
    else
    begin
      ErrorMsg := 'Unknown key format. First line: ' + Copy(FirstLine, 1, 60);
      Exit;
    end;

    if Pos('-----END', LastLine) = 0 then
    begin
      ErrorMsg := 'Key data has no END marker - incomplete or corrupted';
      Exit;
    end;

    if (KeyAlgo = 'openssh') and (PubText <> '') then
    begin
      PL := TStringList.Create;
      try
        try
          PL.Text := PubText;
          if PL.Count > 0 then
          begin
            PubLine := Trim(PL[0]);
            PubAlgo := SSHDetectPublicKeyAlgo(PubLine);
            if PubAlgo <> '' then
              KeyAlgo := PubAlgo;
          end;
        except
        end;
      finally
        PL.Free;
      end;
    end;

    SupportedAlgs := LibSSH2_GetSupportedHostKeyAlgs;
    if SupportedAlgs <> '' then
    begin
      if (KeyAlgo = 'ssh-ed25519') and (Pos('ssh-ed25519', SupportedAlgs) = 0) then
      begin
        ErrorMsg := 'Current libssh2 does NOT support ed25519 keys.' + sLineBreak +
                    'Supported: ' + SupportedAlgs;
        Exit;
      end
      else if (KeyAlgo = 'ssh-rsa') and (Pos('ssh-rsa', SupportedAlgs) = 0) and
              (Pos('rsa-sha2', SupportedAlgs) = 0) then
      begin
        ErrorMsg := 'libssh2 does not support RSA. Supported: ' + SupportedAlgs;
        Exit;
      end
      else if (KeyAlgo = 'ssh-dss') and (Pos('ssh-dss', SupportedAlgs) = 0) then
      begin
        ErrorMsg := 'libssh2 does not support DSA. Supported: ' + SupportedAlgs;
        Exit;
      end
      else if ((KeyAlgo = 'ecdsa') or KeyAlgo.StartsWith('ecdsa-')) and
              (Pos('ecdsa', SupportedAlgs) = 0) then
      begin
        ErrorMsg := 'libssh2 does not support ECDSA. Supported: ' + SupportedAlgs;
        Exit;
      end;
    end;

    Result := True;
  finally
    L.Free;
  end;
end;

end.
