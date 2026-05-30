unit Reg_nbFilePane;

interface

procedure Register;

implementation

uses
  System.Classes,
  FMX.Types,
  DesignIntf,
  nbFilePane.Controls,
  nbFilePane;

const
  PaletteName = 'nb File Pane';
  FilePaneCategory = 'nb File Pane';
  FilePaneEventsCategory = 'nb File Pane Events';

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
    TnbFilePane,
    TnbToolButton
  ]);

  RegisterComponents(PaletteName, [
    TnbFilePane
  ]);

  RegisterFilePaneDesignTime;
end;

end.
