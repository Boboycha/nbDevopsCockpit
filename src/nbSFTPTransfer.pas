unit nbSFTPTransfer;

(*
  TnbSFTPTransfer — перекачка одного файла между двумя SFTP-серверами.
  libssh2 не умеет прямой server-to-server обмен, поэтому делается relay
  через локальный временный файл: download(A → temp) → upload(temp → B) →
  удалить temp.

  На время операции компонент временно перехватывает события OnProgress /
  OnTransferDone / OnError у задействованного клиента и восстанавливает их
  по завершении фазы. Поэтому одновременно может идти только одна передача
  (Busy = True).
*)

interface

uses
  System.Classes, System.SysUtils, System.IOUtils,
  nbSFTPClient;

type
  TnbTransferPhase = (tpIdle, tpDownload, tpUpload);

  TnbTransferProgressEvent = procedure(Sender: TObject;
    APhase: TnbTransferPhase; ADone, ATotal: Int64) of object;
  TnbTransferErrorEvent = procedure(Sender: TObject; const AMsg: string) of object;

  TnbSFTPTransfer = class(TComponent)
  private
    FSource: TnbSFTPClient;
    FTarget: TnbSFTPClient;
    FTempFile: string;
    FDstPath: string;
    FPhase: TnbTransferPhase;

    (* Сохранённые события активного клиента — восстанавливаются после фазы. *)
    FOldProgress: TSFTPProgressEvent;
    FOldTransferDone: TSFTPTransferDoneEvent;
    FOldError: TSFTPErrorEvent;

    FOnProgress: TnbTransferProgressEvent;
    FOnDone: TNotifyEvent;
    FOnError: TnbTransferErrorEvent;

    procedure HookClient(AClient: TnbSFTPClient);
    procedure UnhookClient(AClient: TnbSFTPClient);
    procedure HandleProgress(Sender: TObject; ADone, ATotal: Int64);
    procedure HandleDownloadDone(Sender: TObject; const APath: string);
    procedure HandleUploadDone(Sender: TObject; const APath: string);
    procedure HandleError(Sender: TObject; const AMsg: string);
    procedure Finish;
  public
    function Busy: Boolean;

    (* Запустить передачу ARemoteSrc (на сервере ASource) в ADstPath
       (на сервере ATarget). Оба пути — абсолютные пути на серверах. *)
    procedure Start(ASource: TnbSFTPClient; const ARemoteSrc: string;
      ATarget: TnbSFTPClient; const ADstPath: string);

    property OnProgress: TnbTransferProgressEvent read FOnProgress write FOnProgress;
    property OnDone: TNotifyEvent read FOnDone write FOnDone;
    property OnError: TnbTransferErrorEvent read FOnError write FOnError;
  end;

implementation

{ TnbSFTPTransfer }

function TnbSFTPTransfer.Busy: Boolean;
begin
  Result := FPhase <> tpIdle;
end;

procedure TnbSFTPTransfer.HookClient(AClient: TnbSFTPClient);
begin
  FOldProgress := AClient.OnProgress;
  FOldTransferDone := AClient.OnTransferDone;
  FOldError := AClient.OnError;
  AClient.OnProgress := HandleProgress;
  AClient.OnError := HandleError;
  (* OnTransferDone назначается отдельно — разный обработчик для фаз. *)
end;

procedure TnbSFTPTransfer.UnhookClient(AClient: TnbSFTPClient);
begin
  if AClient = nil then Exit;
  AClient.OnProgress := FOldProgress;
  AClient.OnTransferDone := FOldTransferDone;
  AClient.OnError := FOldError;
end;

procedure TnbSFTPTransfer.Start(ASource: TnbSFTPClient;
  const ARemoteSrc: string; ATarget: TnbSFTPClient; const ADstPath: string);
begin
  if Busy then Exit;
  if (ASource = nil) or (ATarget = nil) then Exit;

  FSource := ASource;
  FTarget := ATarget;
  FDstPath := ADstPath;
  FTempFile := TPath.Combine(TPath.GetTempPath,
    'nbxfer_' + TPath.GetGUIDFileName(False) + '_' +
    TPath.GetFileName(ARemoteSrc));

  FPhase := tpDownload;
  HookClient(FSource);
  FSource.OnTransferDone := HandleDownloadDone;
  FSource.Download(ARemoteSrc, FTempFile);
end;

procedure TnbSFTPTransfer.HandleProgress(Sender: TObject; ADone, ATotal: Int64);
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FPhase, ADone, ATotal);
end;

procedure TnbSFTPTransfer.HandleDownloadDone(Sender: TObject;
  const APath: string);
begin
  (* Фаза download завершена — отцепляемся от источника, цепляем цель. *)
  UnhookClient(FSource);

  FPhase := tpUpload;
  HookClient(FTarget);
  FTarget.OnTransferDone := HandleUploadDone;
  FTarget.Upload(FTempFile, FDstPath);
end;

procedure TnbSFTPTransfer.HandleUploadDone(Sender: TObject;
  const APath: string);
begin
  UnhookClient(FTarget);
  Finish;
  if Assigned(FOnDone) then
    FOnDone(Self);
end;

procedure TnbSFTPTransfer.HandleError(Sender: TObject; const AMsg: string);
var
  Msg: string;
begin
  Msg := AMsg;
  (* Откатываем перехват на том клиенте, чья фаза активна. *)
  if FPhase = tpDownload then
    UnhookClient(FSource)
  else if FPhase = tpUpload then
    UnhookClient(FTarget);
  Finish;
  if Assigned(FOnError) then
    FOnError(Self, Msg);
end;

procedure TnbSFTPTransfer.Finish;
begin
  FPhase := tpIdle;
  if (FTempFile <> '') and TFile.Exists(FTempFile) then
    try
      TFile.Delete(FTempFile);
    except
      (* временный файл не удалился — не критично *)
    end;
  FTempFile := '';
  FSource := nil;
  FTarget := nil;
end;

end.
