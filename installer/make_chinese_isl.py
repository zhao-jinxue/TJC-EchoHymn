# -*- coding: utf-8 -*-
"""从 Inno 自带 Default.isl 生成简体中文语言文件（离线，不依赖外部下载）

用法: python make_chinese_isl.py <Default.isl路径> <输出isl路径>
原理: 仅对 Default.isl 中【已存在】的消息键替换中文值——Inno 对语言文件中的
未知消息键会报编译错误，因此不新增键；未翻译的键自动回退英文原文。
"""
import sys

# 目标翻译（键名以 Default.isl 实际存在的为准，跑完看报告校正）
TRANS = {
    "SetupAppTitle": "安装 - %1",
    "UninstallAppTitle": "卸载 %1",
    "ButtonBack": "< 上一步(&B)",
    "ButtonNext": "下一步(&N) >",
    "ButtonInstall": "安装(&I)",
    "ButtonCancel": "取消(&C)",
    "ButtonFinish": "完成(&F)",
    "ButtonOK": "确定",
    "ButtonYes": "是(&Y)",
    "ButtonNo": "否(&N)",
    "ButtonClose": "关闭",
    "SelectDirLabel3": "%1 将安装到以下文件夹。",
    "SelectDirBrowseLabel": "要继续请点击「下一步」。若要安装到其他文件夹，请点击「浏览」。",
    "DiskSpaceGBLabel": "所需空间:  %1 GB%n1$2可用空间:  %2 GB",
    "DiskSpaceMBLabel": "所需空间:  %1 MB%n1$2可用空间:  %2 MB",
    "StatusExecutingFileOperation": "正在执行文件操作…",
    "StatusDownloadFiles": "正在释放文件…",
    "StatusExtractFiles": "正在解密并释放程序文件…",
    "StatusCreateDirs": "正在创建文件夹…",
    "StatusCreateRegistryEntries": "正在写入注册表…",
    "StatusRegisterFiles": "正在注册组件…",
    "StatusRunProgram": "正在运行安装后任务…",
    "StatusSavingUninstall": "正在保存卸载信息…",
    "StatusRollback": "正在撤消变更…",
    "ExtractingLabel": "正在解密并释放文件…",
    "ErrorExtracting": "释放文件时出错。安装程序可能已损坏。",
    "SetupAborted": "安装程序尚未完成。",
    "UninstalledMost": "%1 卸载完成。",
    "UninstallAppRunningError": "EchoHymn 正在运行，请先退出程序后再卸载。",
    "UninstalledAll": "%1 已被成功的从您的计算机中移除。",
    "UninstallAppTitle": "卸载 %1",
    "ConfirmUninstall": "确实要完全移除 %1 及其全部组件吗？",
    "ClickFinish": "点击「完成」退出安装向导。",
    "FinishedHeadingLabel": "%1 安装完成",
    "FinishedLabel": "安装向导已在您的计算机上安装了 %1。点击「完成」退出安装向导。",
    "FinishedLabelNoIcons": "安装向导已在您的计算机上安装了 %1。点击「完成」退出安装向导。",
    "FinishedRestartLabel": "要使 %1 的更改生效，安装程序必须重新启动您的计算机。是否立即重新启动？",
    "SelectLanguageTitle": "选择安装语言",
    "SelectLanguageLabel": "选择安装过程使用的语言：",
    "WindowsVersionNotSupported": "此程序不支持您当前的 Windows 版本。",
    "AdminPrivilegesRequired": "必须以管理员身份运行此安装程序。",
    "ErrorCopying": "向下列位置复制文件时出错:%n1$2%1%n1$2请确认该目录存在且您对其有写入权限。",
    "CloseApplications": "安装前需要关闭正在使用相关文件的程序。",
    "ErrorRegisterServer": "无法注册 DLL/OCX。",
    "NameAndVersion": "%1 版本 %2",
}


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8-sig") as f:
        lines = f.read().splitlines()

    final, seen = [], set()
    for line in lines:
        s = line.strip()
        if s and not s.startswith(("[", ";")) and "=" in s:
            k = s.split("=", 1)[0]
            if k in TRANS:
                line = f"{k}={TRANS[k]}"
                seen.add(k)
        final.append(line)

    skipped = sorted(set(TRANS) - seen)
    with open(dst, "w", encoding="utf-8-sig", newline="\r\n") as f:
        f.write("\n".join(final) + "\n")
    print(f"ISL_OUT {dst}")
    print(f"已翻译 {len(seen)} 键 / 未命中 {len(skipped)} 键（保留英文回退）")
    print("SKIPPED:", ", ".join(skipped) if skipped else "无")
    return 0


if __name__ == "__main__":
    sys.exit(main())
