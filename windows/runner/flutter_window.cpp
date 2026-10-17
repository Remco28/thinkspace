#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

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

  title_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "thinkspace/window",
          &flutter::StandardMethodCodec::GetInstance());
  title_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setTitle") {
          const auto* title =
              call.arguments() ? std::get_if<std::string>(call.arguments())
                               : nullptr;
          if (title != nullptr) {
            int n = ::MultiByteToWideChar(CP_UTF8, 0, title->c_str(), -1,
                                          nullptr, 0);
            if (n > 0) {
              std::wstring wide(static_cast<size_t>(n), L'\0');
              ::MultiByteToWideChar(CP_UTF8, 0, title->c_str(), -1,
                                    wide.data(), n);
              ::SetWindowTextW(GetHandle(), wide.c_str());
            }
          }
          result->Success();
        } else if (call.method_name() == "setFullscreen") {
          const auto* on = call.arguments()
                               ? std::get_if<bool>(call.arguments())
                               : nullptr;
          SetFullscreen(on != nullptr && *on);
          result->Success(flutter::EncodableValue(fullscreen_));
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

// Full screen the usual Win32 way: remember where the window was, drop its
// frame and stretch it over the monitor it is on; put it all back on the way
// out.
void FlutterWindow::SetFullscreen(bool on) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || on == fullscreen_) {
    return;
  }
  if (on) {
    MONITORINFO monitor = {sizeof(monitor)};
    saved_style_ = ::GetWindowLong(hwnd, GWL_STYLE);
    if (!::GetWindowPlacement(hwnd, &saved_placement_) ||
        !::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                          &monitor)) {
      return;
    }
    ::SetWindowLong(hwnd, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
    const RECT& r = monitor.rcMonitor;
    ::SetWindowPos(hwnd, HWND_TOP, r.left, r.top, r.right - r.left,
                   r.bottom - r.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    ::SetWindowLong(hwnd, GWL_STYLE, saved_style_);
    ::SetWindowPlacement(hwnd, &saved_placement_);
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  fullscreen_ = on;
}

void FlutterWindow::OnDestroy() {
  title_channel_ = nullptr;
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
