#include "flutter_window.h"

#include <optional>

#include <endpointvolume.h>
#include <mmdeviceapi.h>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"

namespace {

// 读取系统默认音频输出设备的音量（0.0~1.0）与静音状态（Core Audio / WASAPI）。
// 用于「应用初始化音量 = 系统音量」，避免启动时固定 100% 与系统不一致。
bool GetSystemVolume(double* volume, bool* muted) {
  *volume = 1.0;
  *muted = false;
  HRESULT hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  // S_OK = 本线程新初始化（需配套 CoUninitialize）；S_FALSE = 已初始化过
  const bool need_uninit = hr == S_OK;
  if (!SUCCEEDED(hr)) return false;

  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioEndpointVolume* endpoint = nullptr;
  hr = ::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                          IID_PPV_ARGS(&enumerator));
  if (SUCCEEDED(hr)) {
    hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
  }
  if (SUCCEEDED(hr)) {
    hr = device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr,
                          reinterpret_cast<void**>(&endpoint));
  }
  if (SUCCEEDED(hr) && endpoint != nullptr) {
    float level = 1.0f;
    BOOL is_muted = FALSE;
    endpoint->GetMasterVolumeLevelScalar(&level);
    endpoint->GetMute(&is_muted);
    *volume = static_cast<double>(level);
    *muted = is_muted != FALSE;
  }
  if (endpoint != nullptr) endpoint->Release();
  if (device != nullptr) device->Release();
  if (enumerator != nullptr) enumerator->Release();
  if (need_uninit) ::CoUninitialize();
  return SUCCEEDED(hr);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // MethodChannel：Dart 侧控制窗口客户区尺寸（侧栏展开/收起时加宽窗口）
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "echo_hymn/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "setClientSize") {
          int width = 850;
          int height = 890;
          int left_panel = 0;
          int right_panel = 0;
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args != nullptr) {
            auto it = args->find(flutter::EncodableValue("width"));
            if (it != args->end()) {
              if (auto* v = std::get_if<int>(&it->second)) width = *v;
            }
            auto it_h = args->find(flutter::EncodableValue("height"));
            if (it_h != args->end()) {
              if (auto* v = std::get_if<int>(&it_h->second)) height = *v;
            }
            auto it_l = args->find(flutter::EncodableValue("leftPanelWidth"));
            if (it_l != args->end()) {
              if (auto* v = std::get_if<int>(&it_l->second)) left_panel = *v;
            }
            auto it_r = args->find(flutter::EncodableValue("rightPanelWidth"));
            if (it_r != args->end()) {
              if (auto* v = std::get_if<int>(&it_r->second)) right_panel = *v;
            }
          }
          this->SetClientSize(static_cast<unsigned int>(width),
                              static_cast<unsigned int>(height),
                              static_cast<unsigned int>(left_panel),
                              static_cast<unsigned int>(right_panel));
          result->Success();
        } else if (method == "minimize") {
          // 自定义标题栏最小化按钮（等价系统最小化，音频播放不中断）
          ::ShowWindow(this->GetHandle(), SW_MINIMIZE);
          result->Success();
        } else if (method == "maximizeToggle") {
          // 自定义标题栏最大化/还原按钮（拖到屏幕顶部/ Win+↑ 等同理）
          HWND hwnd = this->GetHandle();
          if (::IsZoomed(hwnd)) {
            ::ShowWindow(hwnd, SW_RESTORE);
          } else {
            ::ShowWindow(hwnd, SW_MAXIMIZE);
          }
          result->Success();
        } else if (method == "close") {
          // 自定义标题栏关闭按钮（走 WM_CLOSE 正常关闭流程，状态落盘）
          ::PostMessage(this->GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
        } else if (method == "startWindowDrag") {
          // 让系统进入标题栏拖拽循环：窗口跟随鼠标移动；
          // 最大化状态下拖拽会自动还原为浮动窗口（系统默认行为）。
          ::ReleaseCapture();
          ::SendMessage(this->GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (method == "getSystemVolume") {
          // 初始化音量 = 系统默认输出设备音量（非固定 100%）
          double volume = 1.0;
          bool muted = false;
          GetSystemVolume(&volume, &muted);
          flutter::EncodableMap map;
          map[flutter::EncodableValue("volume")] =
              flutter::EncodableValue(volume);
          map[flutter::EncodableValue("muted")] =
              flutter::EncodableValue(muted);
          result->Success(flutter::EncodableValue(map));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SIZE: {
      // 最大化/还原状态变化时通知 Dart（切换最大化按钮图标）。
      // 处理完仍会落入 Win32Window::MessageHandler 走默认子窗口铺满逻辑。
      const bool zoomed = ::IsZoomed(hwnd) != FALSE;
      if (zoomed != last_maximized_) {
        last_maximized_ = zoomed;
        if (window_channel_) {
          window_channel_->InvokeMethod(
              "onWindowMaximizedChanged",
              std::make_unique<flutter::EncodableValue>(zoomed));
        }
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
