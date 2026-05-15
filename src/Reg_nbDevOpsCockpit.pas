unit Reg_nbDevOpsCockpit;

(*
  Регистрация компонентов пакета nbDevOpsCockpit в палитре Delphi.

  Пакет содержит компоненты для построения DevOps-инструментов
  на базе FMX (Windows / Linux / macOS).

  Текущие компоненты:
    TnbSSHClient       - SSH-соединение через libssh2
    TnbTerminalControl - визуальный xterm-256color терминал

  Запланировано добавить:
    TnbGitLabClient    - REST-клиент для GitLab API
    TnbServerInventory - инвентарь серверов с привязкой к проектам
    TnbSnippetRunner   - выполнение скриптов на удалённых серверах
    ...

  Палитра: "nb DevOps"
*)

interface

procedure Register;

implementation

uses
  System.Classes,
  ModernSSHClient,
  Terminal.Control;

procedure Register;
begin
  RegisterComponents('nb DevOps', [
    TnbSSHClient,
    TnbTerminalControl
  ]);

  (* По мере появления новых компонентов добавлять сюда:

  RegisterComponents('nb DevOps', [
    TnbGitLabClient,
    TnbServerInventory
  ]);

  Можно регистрировать в нескольких подгруппах одной палитры:
  RegisterComponents('nb DevOps SSH',  [TnbSSHClient, TnbTerminalControl]);
  RegisterComponents('nb DevOps Git',  [TnbGitLabClient]);
  RegisterComponents('nb DevOps Data', [TnbServerInventory]);
  *)
end;

end.
