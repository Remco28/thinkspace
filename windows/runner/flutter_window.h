#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |start_hidden|: started by the screenshot shortcut with no window open;
  // the app shows the window once a screenshot has come in.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool start_hidden = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Covers the whole monitor without a frame, or goes back to how it was.
  void SetFullscreen(bool on);

  // Step aside, let the person pick part of the screen, and come back.
  void TakeScreenshot(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void FinishScreenshot(const std::wstring& png);

  bool start_hidden_ = false;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> shot_result_;
  bool shot_was_shown_ = false;
  bool shot_was_minimised_ = false;

  bool fullscreen_ = false;
  LONG saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_ = {sizeof(WINDOWPLACEMENT)};

  // "thinkspace/window": lets the app put the file name and an unsaved dot
  // in the title bar, switch full screen, take screenshots and set the
  // screenshot shortcut; and tells it when the shortcut was pressed.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> title_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
