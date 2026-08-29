#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // ---- 单实例保护（UI 测试 A02）----
  // 已有实例运行时，再次启动只聚焦已有窗口并退出本进程，
  // 避免音频播放应用出现多实例。
  {
    HANDLE single_mutex =
        ::CreateMutexW(nullptr, FALSE, L"EchoHymn_SingleInstanceMutex");
    if (single_mutex != nullptr &&
        ::GetLastError() == ERROR_ALREADY_EXISTS) {
      HWND existing = ::FindWindowW(nullptr, L"echo_hymn");
      if (existing != nullptr) {
        ::ShowWindow(existing, SW_RESTORE);
        ::SetForegroundWindow(existing);
      }
      return EXIT_SUCCESS;
    }
    // mutex 句柄由系统持有至进程退出，届时自动释放
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // 基座画面（最简播放画面）：850×890 客户区物理像素（左右侧栏收起时）
  Win32Window::Size size(850, 890);
  if (!window.Create(L"echo_hymn", origin, size)) {
    return EXIT_FAILURE;
  }
  // 客户区精确设为 850×890 物理像素（不受系统 DPI 缩放影响）。
  // 注意：不要再单独调用 SetMinClientSize(850,890)——
  // SetClientSize 内部已设置最小客户区；若此处再显式设置一次，
  // 其执行时序可能在 Dart 恢复侧栏展开（setClientSize）之后，
  // 把已随展开同步更新的最小尺寸覆盖回基座尺寸（UI 测试 K10b）。
  window.SetClientSize(850, 890);
  // 窗口居中显示在主屏工作区（上下左右均居中）
  {
    HWND hwnd = window.GetHandle();
    if (hwnd != nullptr) {
      RECT rc;
      GetWindowRect(hwnd, &rc);
      const int w = rc.right - rc.left;
      const int h = rc.bottom - rc.top;
      RECT work{0, 0, 0, 0};
      if (SystemParametersInfo(SPI_GETWORKAREA, 0, &work, 0)) {
        const int left = work.left + (work.right - work.left - w) / 2;
        const int top = work.top + (work.bottom - work.top - h) / 2;
        SetWindowPos(hwnd, nullptr, left, top, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
      }
    }
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
