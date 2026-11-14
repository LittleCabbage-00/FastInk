#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <cstdint>
#include <memory>
#include <string>

#include "win32_window.h"

// 仅承载 Flutter 视图的宿主窗口。
class FlutterWindow : public Win32Window {
 public:
  // 创建新的 FlutterWindow，承载运行 |project| 的 Flutter 视图。
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window 基类接口：
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static LRESULT CALLBACK PenSubclassProc(HWND window, UINT message,
                                          WPARAM wparam, LPARAM lparam,
                                          UINT_PTR subclass_id,
                                          DWORD_PTR reference_data);
  void HandlePointerMessage(UINT message, WPARAM wparam);
  void UpdatePenButtons(bool primary, bool secondary,
                        const std::string& source);
  void EmitPenButton(int button, bool pressed, const std::string& source);
  void EmitPenPressure(UINT32 pointer_id, float pressure);

  // 待运行的 Flutter 项目。
  flutter::DartProject project_;

  // 本窗口承载的 Flutter 实例。
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> pen_channel_;
  HWND flutter_view_window_ = nullptr;
  bool primary_pen_button_down_ = false;
  bool secondary_pen_button_down_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
