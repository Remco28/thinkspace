#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "capture.h"
#include "flutter/generated_plugin_registrant.h"
#include "screen_pick.h"

namespace {

// How long to wait after hiding the window before freezing the screen, so
// it is really gone from the picture.
constexpr UINT_PTR kShotTimer = 0x5453;
constexpr UINT kShotDelayMs = 250;

std::string Utf8(const std::wstring& wide) {
  if (wide.empty()) return {};
  const int n = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0,
                                    nullptr, nullptr);
  if (n <= 1) return {};
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, out.data(), n, nullptr,
                      nullptr);
  out.resize(static_cast<size_t>(n) - 1);
  return out;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

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
        } else if (call.method_name() == "takeScreenshot") {
          TakeScreenshot(std::move(result));
        } else if (call.method_name() == "showWindow") {
          start_hidden_ = false;
          ::ShowWindow(GetHandle(), SW_SHOWNORMAL);
          ::SetForegroundWindow(GetHandle());
          result->Success();
        } else if (call.method_name() == "quit") {
          // After the reply: closing tears down the engine that sent it.
          ::PostMessage(GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
        } else if (call.method_name() == "getShortcut") {
          WORD hotkey = 0;
          if (ReadScreenshotHotkey(&hotkey) && hotkey != 0) {
            result->Success(flutter::EncodableValue(static_cast<int>(hotkey)));
          } else {
            result->Success();
          }
        } else if (call.method_name() == "setShortcut") {
          const auto* hotkey = call.arguments()
                                   ? std::get_if<int>(call.arguments())
                                   : nullptr;
          result->Success(flutter::EncodableValue(
              hotkey != nullptr &&
              WriteScreenshotShortcut(static_cast<WORD>(*hotkey))));
        } else if (call.method_name() == "removeShortcut") {
          result->Success(flutter::EncodableValue(RemoveScreenshotShortcut()));
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

// Hide (if shown), wait for the window to be gone, then freeze the screen
// for the person to pick an area (screen_pick.cpp).
void FlutterWindow::TakeScreenshot(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (shot_result_) {
    result->Error("busy", "A screenshot is already being taken");
    return;
  }
  HWND hwnd = GetHandle();
  shot_result_ = std::move(result);
  shot_was_minimised_ = ::IsIconic(hwnd) != 0;
  shot_was_shown_ = ::IsWindowVisible(hwnd) && !shot_was_minimised_;
  if (shot_was_shown_) ::ShowWindow(hwnd, SW_HIDE);
  ::SetTimer(hwnd, kShotTimer, shot_was_shown_ ? kShotDelayMs : 10, nullptr);
}

void FlutterWindow::FinishScreenshot(const std::wstring& png) {
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    if (shot_was_shown_) {
      ::ShowWindow(hwnd, SW_SHOW);
      ::SetForegroundWindow(hwnd);
    } else if (shot_was_minimised_ && !png.empty()) {
      // A shortcut from elsewhere: the picture brings the window back.
      ::ShowWindow(hwnd, SW_RESTORE);
      ::SetForegroundWindow(hwnd);
    }
  }
  auto result = std::move(shot_result_);
  if (!result) return;
  if (png.empty()) {
    result->Success();  // cancelled
  } else {
    result->Success(flutter::EncodableValue(Utf8(png)));
  }
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
  shot_result_ = nullptr;  // the engine that asked is going away
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
    case WM_TIMER:
      if (wparam == kShotTimer) {
        ::KillTimer(hwnd, kShotTimer);
        PickScreenArea(
            [this](const std::wstring& png) { FinishScreenshot(png); });
        return 0;
      }
      break;
    case WM_COPYDATA: {
      // `thinkspace --capture` from the screenshot shortcut (capture.cpp).
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data != nullptr && data->dwData == kCaptureMessage && title_channel_) {
        title_channel_->InvokeMethod("capture", nullptr);
        return static_cast<LRESULT>(kCaptureMessage);
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
