unit Reg_nbDevOpsCockpit;

(*
  Design-time registration for nbDevOpsCockpit.

  Runtime units live in nbDevOpsCockpit. This unit is compiled only into
  dclnbDevOpsCockpit and may depend on DesignIDE/ToolsAPI units.
*)

interface

procedure Register;

implementation

uses
  System.Classes,
  FMX.Types,
  DesignIntf,
  ModernSSHClient,
  Terminal.Control,
  nbFilePane.Controls,
  nbFilePane;

const
  PaletteName = 'nb DevOps';
  SshCategory = 'nb DevOps SSH';
  TerminalCategory = 'nb DevOps Terminal';
  TerminalBehaviorCategory = 'nb DevOps Behavior';
  DevOpsEventsCategory = 'nb DevOps Events';
  FilePaneCategory = 'nb DevOps File Pane';
  FilePaneEventsCategory = 'nb DevOps File Pane Events';

procedure RegisterSSHDesignTime;
begin
  RegisterPropertiesInCategory(SshCategory, TnbSSHClient, [
    'Host',
    'Port',
    'User',
    'Password',
    'KeyPath',
    'Passphrase',
    'InitialCols',
    'InitialRows',
    'ConnectionTimeoutMs',
    'WakeOnConnect'
  ]);

  RegisterPropertiesInCategory(DevOpsEventsCategory, TnbSSHClient, [
    'OnStatusChange',
    'OnReadData',
    'OnConnecting',
    'OnAuthenticating',
    'OnConnected',
    'OnDisconnected',
    'OnError',
    'OnVerifyHostKey'
  ]);
end;

procedure RegisterTerminalDesignTime;
begin
  RegisterPropertiesInCategory(TerminalCategory, TnbTerminalControl, [
    'FontSize',
    'FontFamily',
    'FontBold',
    'FontItalic',
    'Theme',
    'SSHClient'
  ]);

  RegisterPropertiesInCategory(TerminalBehaviorCategory, TnbTerminalControl, [
    'EnableSyntaxHighlighting',
    'AutoCopySelection',
    'PasteOnRightClick'
  ]);

  RegisterPropertiesInCategory(DevOpsEventsCategory, TnbTerminalControl, [
    'OnData',
    'OnUserInput',
    'OnHostOutput'
  ]);
end;

procedure RegisterFilePaneDesignTime;
begin
  RegisterPropertiesInCategory(FilePaneCategory, TnbFilePane, [
    'Align',
    'Anchors',
    'Margins',
    'Padding',
    'TabStop'
  ]);

  RegisterPropertiesInCategory(FilePaneEventsCategory, TnbFilePane, [
    'OnTransfer',
    'OnActivated',
    'OnError',
    'OnFileDrop'
  ]);
end;

procedure Register;
begin
  RegisterFmxClasses([
    TnbSSHClient,
    TnbTerminalControl,
    TnbFilePane,
    TnbToolButton
  ]);

  RegisterComponents(PaletteName, [
    TnbSSHClient,
    TnbTerminalControl,
    TnbFilePane
  ]);

  RegisterSSHDesignTime;
  RegisterTerminalDesignTime;
  RegisterFilePaneDesignTime;
end;

end.
