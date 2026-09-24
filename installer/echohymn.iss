; ============================================================
; EchoHymn · 聆听赞美诗 Windows 安装包 — Inno Setup 6
; 架构: Inno 向导壳（环境检查 / 目录选择 / 使用誓言）+ AES-256 加密 7z 载荷
; 编译入口: tools/build_installer.ps1（勿手工编译，需版本注入与载荷预生成）
; ============================================================
#ifndef AppVersion
  #define AppVersion "1.6.2"
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
; 2026-09-22: 安装包 exe 的「文件版本」此前为空——Inno 的 VersionInfoVersion 需 4 段式，
; 而 AppVersion 是 3 段（1.6.2），缺省未设置导致资源里无 FileVersion；这里补 .0 使其显示 1.6.2.0。
VersionInfoVersion={#AppVersion}.0
SetupIconFile=app_icon.ico
Compression={#Comp}
SolidCompression=yes
WizardStyle=modern
; CloseApplications 只覆盖安装程序自身 [Files]/[InstallDelete] 条目（走 Restart Manager）；
; 主程序与素材由 ExtractArchive 直接释放，不在其感知范围 → 运行中的实例改由 [Code] 显式
; 检测并结束（不采用 AppMutex：其官方交互允许「确定继续」，仍会留下残留文件）
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
  CopyFile(Src, Dst, False);
end;

{ ── 运行中实例处理（2026-09-24 修复：程序在运行时卸载/升级导致文件残留）──
  背景：`CloseApplications=yes` 只覆盖安装程序自身 [Files] / [InstallDelete] 条目（走 Windows
  Restart Manager），而本安装包的主程序与素材都由 ExtractArchive 直接释放、卸载时由 DelTree
  整树删除——两种情况都不在 Restart Manager 感知范围内。若 EchoHymn 正在运行（含最小化到
  系统托盘：窗口隐藏但进程仍在），echo_hymn.exe 与进程当前目录被占用 → DelTree 静默失败
  → 安装目录残留；且 Inno 仍会删除 unins000.exe 与注册表卸载项，用户再也无法通过
  「设置 → 应用」清理。故安装前（PrepareToInstall）与卸载前（InitializeUninstall）都显式
  检测并结束进程，删除后再复核结果。 }

const
  EH_EXE = 'echo_hymn.exe';
  EH_MUTEX = 'EchoHymn_SingleInstanceMutex';  { 与 hymn_app/windows/runner/main.cpp 一致 }
  EH_WINDOW = 'echo_hymn';

function EHAppRunning: Boolean;
begin
  { 双通道判定：单实例互斥体（可靠）+ 窗口标题（兜底） }
  Result := CheckForMutexes(EH_MUTEX) or (FindWindowByWindowName(EH_WINDOW) <> 0);
end;

function EHCloseApp: Boolean;
var
  ResultCode: Integer;
begin
  { /F 强制结束：软件可能处于托盘隐藏状态，或首次关闭会弹出「直接关闭 / 进入系统托盘」
    询问框，平滑关闭（不带 /F）会被这两个分支阻断而无法结束进程；/T 连带结束子进程。 }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM ' + EH_EXE, '',
       SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(600);
  Result := not EHAppRunning;
end;

{ 确保运行中的实例已关闭。Silent=True（/SILENT、/VERYSILENT 或静默卸载）不弹窗、直接结束；
  返回 False 表示不应继续（用户选择取消，或进程无法结束）。 }
function EHEnsureAppClosed(Silent: Boolean): Boolean;
begin
  Result := True;
  if not EHAppRunning then Exit;
  if not Silent then
    if MsgBox('检测到 EchoHymn 正在运行（可能已最小化到系统托盘）。' + #13#10 + #13#10 +
      '请先关闭它；或点击「是」由本程序立即结束该进程并继续。' + #13#10 +
      '（个人歌单与设置保存在 state.json 中，不受影响；未保存的播放进度不保留。）',
      mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
      Exit;
    end;
  if not EHCloseApp then
  begin
    Result := False;
    if not Silent then
      MsgBox('无法结束正在运行的 EchoHymn 进程，操作已中止。' + #13#10 +
        '请在任务管理器中结束 echo_hymn.exe（含托盘图标）后重试。',
        mbCriticalError, MB_OK);
  end;
end;

{ 整树删除 + 占用重试（进程刚退出时文件句柄/目录句柄可能尚未释放）}
function EHDeleteTree(const Dir: String): Boolean;
var
  I: Integer;
begin
  Result := DelTree(Dir, True, True, True);
  I := 0;
  while (not Result) and (I < 5) do
  begin
    Sleep(500);
    if EHAppRunning then EHCloseApp;
    Result := DelTree(Dir, True, True, True);
    I := I + 1;
  end;
end;

{ 列出残留条目（最多 Max 条），供删除失败时向用户指明清理对象 }
function EHResidueList(const Dir: String; Max: Integer): String;
var
  SR: TFindRec;
  N: Integer;
begin
  Result := '';
  N := 0;
  if FindFirst(Dir + '\*', SR) then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        Result := Result + '  ' + SR.Name + #13#10;
        N := N + 1;
        if N >= Max then
        begin
          Result := Result + '  …' + #13#10;
          Break;
        end;
      end;
    until not FindNext(SR);
  finally
    FindClose(SR);
  end;
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

{ 升级安装前的占用检查：主程序与素材由 ExtractArchive 直接释放，CloseApplications 覆盖不到，
  运行中会因文件占用而释放失败。返回非空字符串 → 安装中止并显示该提示。 }
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not EHEnsureAppClosed(WizardSilent) then
    Result := '检测到 EchoHymn 正在运行，安装已取消。请先关闭软件（含系统托盘图标）后重试。';
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
  { 卸载前必须先结束运行中的实例：否则 echo_hymn.exe 与进程当前工作目录被占用，
    整树删除失败留下残留文件，而 Inno 仍会删掉 unins000.exe 与注册表卸载项，
    用户将失去「设置 → 应用」里的卸载入口。返回 False = 干净中止（不动任何文件）。 }
  if not EHEnsureAppClosed(UninstallSilent) then
  begin
    Result := False;
    Exit;
  end;
  if UninstallSilent then
    KeepUserData := True
  else
    KeepUserData := (MsgBox('是否保留个人数据？' + #13#10 + '（个人歌单数据库与 state.json 使用设置；选「否」将彻底删除整个安装目录）', mbConfirmation, MB_YESNO) = IDYES);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  App, KeepDir, P, L: string;
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
    { 用户可能在向导期间又重新启动了软件；删除失败（文件/目录仍被占用）时重试并复核结果，
      绝不静默留下半截目录 —— 否则注册表卸载项与 unins000.exe 已删除，用户无从再卸 }
    if EHAppRunning then EHCloseApp;
    if not EHDeleteTree(App) then
    begin
      L := EHResidueList(App, 8);
      if L = '' then
        L := '  （目录已不存在）' + #13#10;
      if not UninstallSilent then
        MsgBox('卸载未能删除全部文件（仍被占用）。' + #13#10 + #13#10 +
          '残留位置：' + App + #13#10 + '残留内容：' + #13#10 + L + #13#10 +
          '请在关闭 EchoHymn（含任务栏托盘图标）后手动删除上述目录。',
          mbError, MB_OK);
    end;
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

