; ============================================================
; EchoHymn · 聆听赞美诗 Windows 安装包 — Inno Setup 6
; 架构: Inno 向导壳（环境检查 / 目录选择 / 使用誓言）+ AES-256 加密 7z 载荷
; 编译入口: tools/build_installer.ps1（勿手工编译，需版本注入与载荷预生成）
; ============================================================
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Comp
  #define Comp "lzma2/max"
#endif
#ifndef PayloadBytes
  #define PayloadBytes 68157440
#endif
#ifndef PayloadMBStr
  #define PayloadMBStr "65"
#endif
#ifndef DataBytes
  #define DataBytes 3215023906
#endif
#ifndef DataGBStr
  #define DataGBStr "3.0"
#endif
#ifndef DataFileName
  #define DataFileName "EchoHymn_Data.7z"
#endif
#define AppGuid "B7F3E0D2-8C4A-4E5F-9A61-2D3C4B5A6970"
#define HasIsl FileExists(AddBackslash(SourcePath) + "ChineseSimplified.isl")

[Setup]
AppId={{{#AppGuid}}
AppName=EchoHymn
AppVersion={#AppVersion}
AppVerName=EchoHymn · 聆听赞美诗 {#AppVersion}
AppPublisher=EchoHymn
DefaultDirName={code:GetDefaultRoot}\EchoHymn
DefaultGroupName=EchoHymn · 聆听赞美诗
DisableWelcomePage=yes
DisableProgramGroupPage=yes
UninstallDisplayName=EchoHymn · 聆听赞美诗
UninstallDisplayIcon={app}\echo_hymn.exe
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=output
OutputBaseFilename=EchoHymn_Setup_v{#AppVersion}
SetupIconFile=app_icon.ico
Compression={#Comp}
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
ArchiveExtraction=enhanced

[CustomMessages]
EHPayloadMB={#PayloadMBStr} MB
EHDataGB=约 {#DataGBStr} GB

#if HasIsl
[Languages]
Name: "chs"; MessagesFile: "{#AddBackslash(SourcePath)}ChineseSimplified.isl"
#else
[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
#endif

[Files]
Source: "{#AddBackslash(SourcePath)}payload.7z"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"

[Icons]
Name: "{group}\EchoHymn · 聆听赞美诗"; Filename: "{app}\echo_hymn.exe"
Name: "{group}\卸载 EchoHymn"; Filename: "{uninstallexe}"
Name: "{autodesktop}\EchoHymn · 聆听赞美诗"; Filename: "{app}\echo_hymn.exe"; Tasks: desktopicon

[Run]
Filename: "{sys}\icacls.exe"; Parameters: """{app}"" /grant *S-1-5-32-545:(OI)(CI)M /T /Q /C"; Flags: runhidden; StatusMsg: "正在配置目录写入权限"
Filename: "{app}\echo_hymn.exe"; Description: "立即运行 EchoHymn"; Flags: postinstall nowait skipifsilent

[Code]
const
  OATH_TEXT = '主啊，求你鉴察：愿我歌唱不是徒然的声音，乃有敬虔、有感恩；愿这诗歌本只滋养我的生命，不归于任何世俗的益处。';

var
  EnvPage, OathPage: TWizardPage;
  EnvMemo, OathInput: TNewMemo;
  OathMemo, OathErr: TNewStaticText;
  KeepUserData, EnvOK: Boolean;
  OathBuf: string;
  OathKeyOK, OathRevert: Boolean;

function GetDefaultRoot(Param: string): string;
var F, T: Int64;
begin
  Result := ExpandConstant('{commonpf}');
  { D 盘不存在时 GetSpaceOnDisk64 返回 False，天然完成盘符探测 }
  if GetSpaceOnDisk64('D:\', F, T) and (F >= 8589934592) then
    Result := 'D:\Program Files';
end;

function XorChar(C: Integer): string;
begin
  Result := Chr(C xor $5A);
end;

function DecodeKey: string;
begin
  { "EchoHymn2026" 逐字符 XOR $5A 后的混淆字节 }
  Result := XorChar($1F) + XorChar($39) + XorChar($32) + XorChar($35) +
            XorChar($12) + XorChar($23) + XorChar($37) + XorChar($34) +
            XorChar($68) + XorChar($6A) + XorChar($68) + XorChar($6C);
end;

procedure ClipGuard(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ssCtrl in Shift) and ((Key = 65) or (Key = 67) or (Key = 86) or (Key = 88) or (Key = 90) or (Key = 45)) then Key := 0;
  if (ssShift in Shift) and (Key = 45) then Key := 0;
end;

{ ── 誓言输入守卫：Pascal Script 无法屏蔽编辑框原生右键菜单（无 OnContextPopup/TPopupMenu），
   改为"非键盘引发的内容变化一律回滚"——右键粘贴/菜单删除/撤消/拖放均被还原为
   用户逐字键入的内容，效果等同拦截；IME 中文输入走键事件通道不受影响 ── }

procedure OathInputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  ClipGuard(Sender, Key, Shift);
  OathKeyOK := (Key <> 0);
end;

procedure OathInputKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  OathKeyOK := False;
end;

procedure OathInputKeyPress(Sender: TObject; var Key: Char);
begin
  OathKeyOK := True;
end;

procedure OathInputChange(Sender: TObject);
begin
  if OathRevert then Exit;
  if OathKeyOK then
  begin
    OathBuf := OathInput.Text;
    if OathErr.Visible then
    begin
      OathErr.Caption := '✘ 宣誓词输入有误，安装尚未开始——请逐字对照上方文本（含全部标点）重新输入。';
      OathErr.Visible := False;
    end;
  end
  else
  begin
    OathRevert := True;
    try
      OathInput.Text := OathBuf;
    finally
      OathRevert := False;
    end;
    OathErr.Caption := '✘ 检测到非键盘输入（粘贴 / 右键菜单操作 / 拖放），已被拦截——誓言须逐字手输。';
    OathErr.Visible := True;
  end;
end;

function NormalizeOath(const S: string): string;
var i: Integer; C: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    if (C = ' ') or (C = #9) or (C = #13) or (C = #10) or (C = #12288) then Continue;
    case C of
      ',': C := '，';
      '.': C := '。';
      ':': C := '：';
      ';': C := '；';
      '(': C := '（';
      ')': C := '）';
      '!': C := '！';
      '?': C := '？';
    end;
    Result := Result + C;
  end;
end;

function EnvFreeGBText(Path: string): string;
var F, T: Int64;
begin
  Result := '0';
  if GetSpaceOnDisk64(Path, F, T) then
    Result := IntToStr(F div 1073741824) + '.' + IntToStr((F div 107374182) mod 10);
end;

procedure EnvShow(Sender: TObject);
var L, S, D: string; Maj: Cardinal; F, T: Int64; Critical: Boolean;
begin
  Critical := False;
  L := '';
  if IsWin64 then
    L := L + '✔  64 位 Windows 系统' + #13#10
  else
  begin
    L := L + '✘  本程序需要 64 位 Windows' + #13#10;
    Critical := True;
  end;
  Maj := 0;
  if RegQueryDwordValue(HKLM64, 'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'CurrentMajorVersionNumber', Maj) and (Maj >= 10) then
    L := L + '✔  Windows 10 或更新系统' + #13#10
  else
  begin
    L := L + '✘  需要 Windows 10 或更新版本' + #13#10;
    Critical := True;
  end;
  if FileExists(ExpandConstant('{sys}\mfplat.dll')) then
    L := L + '✔  媒体播放组件 Media Foundation 可用' + #13#10
  else
  begin
    L := L + '✘  缺少 Media Foundation（N/KN 版请到 设置-应用-可选功能 安装媒体功能包）' + #13#10;
    Critical := True;
  end;
  { 诗歌素材为外置加密数据文件，必须与本安装包放在同一目录 }
  D := AddBackslash(ExpandConstant('{src}')) + '{#DataFileName}';
  if FileExists(D) then
    L := L + '✔  诗歌素材数据文件已就绪（与安装包同目录，' + CustomMessage('EHDataGB') + '）' + #13#10
  else
  begin
    L := L + '✘  未找到诗歌素材数据文件「{#DataFileName}」——请向分发者索取，并将其与本安装包放入同一目录后点「重新检测」' + #13#10;
    Critical := True;
  end;
  { 磁盘需求（编译期由构建脚本注入真实字节数）：
    系统盘 = 2GB 缓冲（主载荷仅数十 MB，素材不经临时目录）；
    目标盘 = 素材释放 + 主程序释放 + 5GB 缓冲 }
  if GetSpaceOnDisk64(AddBackslash(ExpandConstant('{sd}')), F, T) and (F >= 2147483648) and
     GetSpaceOnDisk64(ExtractFileDrive(GetDefaultRoot('')), F, T) and (F >= {#DataBytes} + {#PayloadBytes} + 5368709120) then
    L := L + '✔  磁盘空间充足（系统盘剩 ' + EnvFreeGBText(AddBackslash(ExpandConstant('{sd}'))) + ' GB，'
        + '安装盘剩 ' + EnvFreeGBText(ExtractFileDrive(GetDefaultRoot(''))) + ' GB，约需 ' + CustomMessage('EHDataGB') + ' 素材 + ' + CustomMessage('EHPayloadMB') + ' 程序 + 5GB 缓冲）' + #13#10
  else
  begin
    L := L + '✘  磁盘空间不足（安装盘约需 ' + CustomMessage('EHDataGB') + ' 素材 + 5GB 缓冲，系统盘需 2GB 缓冲）' + #13#10;
    Critical := True;
  end;
  L := L + '✔  VC++ 运行库随包内置，系统无需另装' + #13#10;
  S := '';
  if RegQueryStringValue(HKLM64, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B7F3E0D2-8C4A-4E5F-9A61-2D3C4B5A6970}_is1', 'DisplayName', S) then
    L := L + 'ℹ  检测到旧版本（' + S + '），继续将升级安装，个人数据保留' + #13#10;
  EnvMemo.Text := L;
  EnvOK := not Critical;
  WizardForm.NextButton.Enabled := EnvOK;
end;

procedure ForceCopy(Src, Dst: string);
begin
  ForceDirectories(ExtractFileDir(Dst));
  DeleteFile(Dst);
  FileCopy(Src, Dst, False);
end;

procedure InitializeWizard;
var
  T: TNewStaticText;
begin
  { ── 第 1 页：系统兼容性检查（紧随欢迎页之后，欢迎页已禁用故为首屏） ── }
  EnvPage := CreateCustomPage(wpWelcome, '第一步 · 系统兼容性检查', '安装前请确认本机环境满足 EchoHymn 的运行要求（全部 ✔ 后才能继续）：');
  EnvMemo := TNewMemo.Create(EnvPage.Surface);
  with EnvMemo do
  begin
    Parent := EnvPage.Surface;
    Left := 0; Top := ScaleY(8); Width := EnvPage.Surface.ClientWidth; Height := ScaleY(150);
    ReadOnly := True; TabStop := False; WordWrap := True;
  end;
  T := TNewStaticText.Create(EnvPage.Surface);
  with T do
  begin
    Parent := EnvPage.Surface;
    Left := 0; Top := ScaleY(166); Caption := '修复环境问题后，可点击下方按钮重新检测。';
  end;
  with TNewButton.Create(EnvPage.Surface) do
  begin
    Parent := EnvPage.Surface;
    Left := 0; Top := ScaleY(190); Width := ScaleX(120); Height := ScaleY(28);
    Caption := '重新检测';
    OnClick := @EnvShow;
  end;
  EnvOK := False;
  EnvShow(nil);

  { ── 第 3 页：誓言宣誓（第 2 页为内置目录选择页 wpSelectDir） ── }
  OathPage := CreateCustomPage(wpSelectDir, '第三步 · 誓言宣誓', '此程序为宗教敬拜用途。请照下方宣誓词逐字输入（不支持复制粘贴），校验通过才会开始安装：');
  { 宣誓词展示框改用静态文本：编辑控件自带右键"复制"菜单，静态文本无菜单可弹，杜绝复制源头 }
  OathMemo := TNewStaticText.Create(OathPage.Surface);
  with OathMemo do
  begin
    Parent := OathPage.Surface;
    Left := 0; Top := ScaleY(10); Width := OathPage.Surface.ClientWidth; Height := ScaleY(48);
    AutoSize := False; WordWrap := True;
    Font.Style := [fsBold];
    Caption := OATH_TEXT;
  end;
  T := TNewStaticText.Create(OathPage.Surface);
  with T do
  begin
    Parent := OathPage.Surface;
    Left := 0; Top := ScaleY(64); Caption := '请在下方输入框逐字输入宣誓词（标点在上方文本中为全角中文标点）：';
  end;
  OathInput := TNewMemo.Create(OathPage.Surface);
  with OathInput do
  begin
    Parent := OathPage.Surface;
    Left := 0; Top := ScaleY(84); Width := OathPage.Surface.ClientWidth; Height := ScaleY(96);
    WordWrap := True; WantReturns := False;
    OnKeyDown := @OathInputKeyDown;
    OnKeyUp := @OathInputKeyUp;
    OnKeyPress := @OathInputKeyPress;
    OnChange := @OathInputChange;
  end;
  OathBuf := '';
  OathErr := TNewStaticText.Create(OathPage.Surface);
  with OathErr do
  begin
    Parent := OathPage.Surface;
    Left := 0; Top := ScaleY(188); Width := OathPage.Surface.ClientWidth; WordWrap := True;
    Font.Color := clRed; Visible := False;
    Caption := '✘ 宣誓词输入有误，安装尚未开始——请逐字对照上方文本（含全部标点）重新输入。';
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (EnvPage <> nil) and (CurPageID = EnvPage.ID) then
    Result := EnvOK;
  if (OathPage <> nil) and (CurPageID = OathPage.ID) then
  begin
    { /SILENT 静默安装属发布者与批量部署通道，跳过誓言交互校验 }
    if WizardSilent then
      Result := True
    else
    begin
      Result := NormalizeOath(OathInput.Text) = NormalizeOath(OATH_TEXT);
      OathErr.Visible := not Result;
    end;
  end;
end;

var
  ExtractPhase: string;

function EHProgress(const ArchiveName, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  if ProgressMax > 0 then
    WizardForm.StatusLabel.Caption := ExtractPhase + '… ' +
      IntToStr((Progress * 100) div ProgressMax) + '%（' + FileName + '）';
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  DbPath, BakPath, DataArc: string;
begin
  if CurStep = ssInstall then
  begin
    { 升级安装：先备份用户歌单数据库（内含 playlist_hymn 个人歌单） }
    DbPath := ExpandConstant('{app}\data\tjc_hymn.db');
    if FileExists(DbPath) then
      ForceCopy(DbPath, ExpandConstant('{tmp}\user_db_keep.bak'));
  end
  else if CurStep = ssPostInstall then
  begin
    { 第一段：释放内嵌主程序载荷（数十 MB，来自临时目录） }
    ExtractPhase := '正在解密并释放程序文件';
    WizardForm.StatusLabel.Caption := ExtractPhase + '，请稍候…';
    try
      ExtractArchive(ExpandConstant('{tmp}\payload.7z'), ExpandConstant('{app}'), DecodeKey(), True, @EHProgress);
    except
      MsgBox('程序文件解包失败，安装中止。请确认磁盘空间充足后重试；若仍失败，请核对安装包 SHA256 是否完整。', mbCriticalError, MB_OK);
      WizardForm.Close;
      Exit;
    end;
    { 第二段：从安装包同级目录直接解密释放外置诗歌素材（约 3 GB，不经临时目录；
        归档内路径为 data/Hymn_Downloads/...，FullPaths 解包天然落到安装目录的 data 子目录下） }
    DataArc := AddBackslash(ExpandConstant('{src}')) + '{#DataFileName}';
    if not FileExists(DataArc) then
    begin
      MsgBox('诗歌素材数据文件「{#DataFileName}」不在安装包同级目录，无法完成安装。' + #13#10 +
        '请将其与安装包放入同一目录后重新运行安装程序（程序文件已释放，素材补齐后重装即可）。', mbCriticalError, MB_OK);
      WizardForm.Close;
      Exit;
    end;
    ExtractPhase := '正在解密并释放诗歌素材（约 {#DataGBStr} GB，视磁盘速度需数分钟）';
    WizardForm.StatusLabel.Caption := ExtractPhase + '…';
    try
      ExtractArchive(DataArc, ExpandConstant('{app}'), DecodeKey(), True, @EHProgress);
    except
      MsgBox('诗歌素材解包失败，安装中止。请确认磁盘空间充足、数据文件完整（可核对 .sha256）后重试。', mbCriticalError, MB_OK);
      WizardForm.Close;
      Exit;
    end;
    { 升级安装：还原用户数据库（覆盖刚释放的出厂库） }
    BakPath := ExpandConstant('{tmp}\user_db_keep.bak');
    if FileExists(BakPath) then
      ForceCopy(BakPath, ExpandConstant('{app}\data\tjc_hymn.db'));
  end;
end;

{ ── 卸载：默认保留个人数据（歌单库 / state.json 设置） ── }

function InitializeUninstall(): Boolean;
begin
  Result := True;
  if UninstallSilent then
    KeepUserData := True
  else
    KeepUserData := (MsgBox('是否保留个人数据？' + #13#10 + '（个人歌单数据库与 state.json 使用设置；选「否」将彻底删除整个安装目录）', mbConfirmation, MB_YESNO) = IDYES);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  App, KeepDir, P: string;
  SR: TFindRec;
begin
  if CurUninstallStep = usUninstall then
  begin
    App := ExpandConstant('{app}');
    KeepDir := ExpandConstant('{tmp}\keep');
    if KeepUserData then
    begin
      ForceDirectories(KeepDir);
      P := App + '\data\tjc_hymn.db';
      if FileExists(P) then ForceCopy(P, KeepDir + '\tjc_hymn.db');
      P := App + '\state.json';
      if FileExists(P) then ForceCopy(P, KeepDir + '\state.json');
      { 日志目录整体暂存 }
      if FindFirst(App + '\logs\*', SR) then
      begin
        ForceDirectories(KeepDir + '\logs');
        repeat
          if (SR.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
            ForceCopy(App + '\logs\' + SR.Name, KeepDir + '\logs\' + SR.Name);
        until not FindNext(SR);
        FindClose(SR);
      end;
    end;
    { 载荷解包的文件不在安装日志中，由 Inno 逐条删除会残留——直接整树清理 }
    DelTree(App, True, True, True);
  end
  else if (CurUninstallStep = usPostUninstall) and KeepUserData then
  begin
    App := ExpandConstant('{app}');
    KeepDir := ExpandConstant('{tmp}\keep');
    if (ExtractFileDir(App) <> '') and not ForceDirectories(App) then Exit;
    if FileExists(KeepDir + '\tjc_hymn.db') then
      ForceCopy(KeepDir + '\tjc_hymn.db', App + '\data\tjc_hymn.db');
    if FileExists(KeepDir + '\state.json') then
      ForceCopy(KeepDir + '\state.json', App + '\state.json');
    if FindFirst(KeepDir + '\logs\*', SR) then
    begin
      ForceDirectories(App + '\logs');
      repeat
        if (SR.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
          ForceCopy(KeepDir + '\logs\' + SR.Name, App + '\logs\' + SR.Name);
      until not FindNext(SR);
      FindClose(SR);
    end;
  end;
end;

