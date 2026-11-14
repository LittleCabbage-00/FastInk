#include "flutter_window.h"

#include <commctrl.h>
#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <cstdint>
#include <algorithm>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // 此尺寸必须与窗口尺寸一致，避免启动期间无谓地
  // 创建和销毁渲染表面。
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // 确认控制器基础初始化成功。
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  pen_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "fastink/pen",
          &flutter::StandardMethodCodec::GetInstance());

  flutter_view_window_ = flutter_controller_->view()->GetNativeWindow();
  SetWindowSubclass(flutter_view_window_, PenSubclassProc, 1,
                    reinterpret_cast<DWORD_PTR>(this));
  SetChildContent(flutter_view_window_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter 可能在注册“显示窗口”回调前已经完成首帧；
  // 下面的调用确保仍有一帧待处理，窗口能够显示，
  // 若首帧尚未完成则不做额外处理。
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_view_window_) {
    RemoveWindowSubclass(flutter_view_window_, PenSubclassProc, 1);
    flutter_view_window_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 先让 Flutter 及其插件有机会处理窗口消息。
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

LRESULT CALLBACK FlutterWindow::PenSubclassProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR reference_data) {
  auto* self = reinterpret_cast<FlutterWindow*>(reference_data);
  if (self) {
    switch (message) {
      case WM_POINTERDOWN:
      case WM_POINTERUPDATE:
      case WM_POINTERUP:
      case WM_POINTERENTER:
      case WM_POINTERLEAVE:
        self->HandlePointerMessage(message, wparam);
        break;
      case WM_RBUTTONDOWN:
        self->EmitPenButton(1, true, "right-button");
        break;
      case WM_RBUTTONUP:
        self->EmitPenButton(1, false, "right-button");
        break;
      case WM_MBUTTONDOWN:
        self->EmitPenButton(2, true, "middle-button");
        break;
      case WM_MBUTTONUP:
        self->EmitPenButton(2, false, "middle-button");
        break;
      case WM_XBUTTONDOWN:
        self->EmitPenButton(GET_XBUTTON_WPARAM(wparam) == XBUTTON1 ? 1 : 2,
                            true, "extended-button");
        break;
      case WM_XBUTTONUP:
        self->EmitPenButton(GET_XBUTTON_WPARAM(wparam) == XBUTTON1 ? 1 : 2,
                            false, "extended-button");
        break;
      case WM_KEYDOWN:
        if ((wparam >= VK_F13 && wparam <= VK_F24) ||
            wparam == VK_BROWSER_BACK || wparam == VK_BROWSER_FORWARD) {
          if ((lparam & (1LL << 30)) == 0) {
            self->EmitPenButton(2, true, "keyboard-mapped");
          }
        }
        break;
      case WM_KEYUP:
        if ((wparam >= VK_F13 && wparam <= VK_F24) ||
            wparam == VK_BROWSER_BACK || wparam == VK_BROWSER_FORWARD) {
          self->EmitPenButton(2, false, "keyboard-mapped");
        }
        break;
      case WM_APPCOMMAND:
        if (GET_APPCOMMAND_LPARAM(lparam) == APPCOMMAND_BROWSER_BACKWARD ||
            GET_APPCOMMAND_LPARAM(lparam) == APPCOMMAND_BROWSER_FORWARD ||
            GET_APPCOMMAND_LPARAM(lparam) == APPCOMMAND_UNDO) {
          self->EmitPenButton(2, true, "app-command");
          self->EmitPenButton(2, false, "app-command");
        }
        break;
    }
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

void FlutterWindow::HandlePointerMessage(UINT message, WPARAM wparam) {
  if (message == WM_POINTERUP || message == WM_POINTERLEAVE) {
    UpdatePenButtons(false, false, "windows-ink");
    return;
  }
  const UINT32 pointer_id = GET_POINTERID_WPARAM(wparam);
  POINTER_INPUT_TYPE pointer_type = PT_POINTER;
  if (!GetPointerType(pointer_id, &pointer_type) || pointer_type != PT_PEN) {
    return;
  }

  POINTER_PEN_INFO pen_info{};
  if (!GetPointerPenInfo(pointer_id, &pen_info)) {
    return;
  }
  const UINT32 flags = pen_info.pointerInfo.pointerFlags;
  EmitPenPressure(pointer_id,
                  static_cast<float>(pen_info.pressure) / 1024.0f);
  const bool primary =
      (flags & POINTER_FLAG_SECONDBUTTON) != 0 ||
      (pen_info.penFlags & PEN_FLAG_BARREL) != 0;
  const bool secondary =
      (flags & (POINTER_FLAG_THIRDBUTTON | POINTER_FLAG_FOURTHBUTTON |
                POINTER_FLAG_FIFTHBUTTON)) != 0 ||
      (pen_info.penFlags & PEN_FLAG_ERASER) != 0;
  UpdatePenButtons(primary, secondary, "windows-ink");
}

void FlutterWindow::UpdatePenButtons(bool primary, bool secondary,
                                     const std::string& source) {
  if (primary && !primary_pen_button_down_) {
    EmitPenButton(1, true, source);
  } else if (!primary && primary_pen_button_down_) {
    EmitPenButton(1, false, source);
  }
  if (secondary && !secondary_pen_button_down_) {
    EmitPenButton(2, true, source);
  } else if (!secondary && secondary_pen_button_down_) {
    EmitPenButton(2, false, source);
  }
  primary_pen_button_down_ = primary;
  secondary_pen_button_down_ = secondary;
}

void FlutterWindow::EmitPenButton(int button, bool pressed,
                                  const std::string& source) {
  if (!pen_channel_) {
    return;
  }

  flutter::EncodableMap event;
  event[flutter::EncodableValue("button")] =
      flutter::EncodableValue(static_cast<int32_t>(button));
  event[flutter::EncodableValue("pressed")] =
      flutter::EncodableValue(pressed);
  event[flutter::EncodableValue("source")] = flutter::EncodableValue(source);
  pen_channel_->InvokeMethod(
      "button", std::make_unique<flutter::EncodableValue>(event));
}

void FlutterWindow::EmitPenPressure(UINT32 pointer_id, float pressure) {
  if (!pen_channel_) return;
  flutter::EncodableMap event;
  event[flutter::EncodableValue("pointer")] =
      flutter::EncodableValue(static_cast<int32_t>(pointer_id));
  event[flutter::EncodableValue("pressure")] =
      flutter::EncodableValue(static_cast<double>(std::clamp(pressure, 0.01f, 1.0f)));
  pen_channel_->InvokeMethod(
      "pressure", std::make_unique<flutter::EncodableValue>(event));
}
