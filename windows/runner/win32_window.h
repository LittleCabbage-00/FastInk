#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// 支持高 DPI 的 Win32 窗口抽象；
// 需要自定义渲染与输入处理的窗口类
// 可继承此类。
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // 使用 |title|、|origin| 和 |size| 创建 Win32 窗口。
  // 新窗口创建在默认显示器上。
  // 操作系统使用物理像素；为保持一致的显示尺寸，
  // 按照默认显示器的缩放系数换算传入的宽度和高度。
  // 创建后窗口暂时隐藏，调用 Show 后才显示。
  // 创建成功时返回 true，调用 |Show| 后显示。
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // 显示当前窗口，成功显示时返回 true。
  bool Show();

  // 释放窗口关联的操作系统资源。
  void Destroy();

  // 将 |content| 插入窗口树。
  void SetChildContent(HWND content);

  // 返回底层窗口句柄，供调用方设置图标及其他窗口属性；
  // 窗口已销毁时返回 nullptr。
  HWND GetHandle();

  // 为 true 时，关闭此窗口同时退出整个应用。
  void SetQuitOnClose(bool quit_on_close);

  // 返回当前客户区边界的 RECT。
  RECT GetClientArea();

 protected:
  // 处理并分发鼠标、尺寸变化和 DPI 等窗口消息，
  // 委托给可由继承类覆盖的成员方法，
  // 以便子类定制处理行为。
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // 创建窗口时调用，供子类执行窗口相关初始化；
  // 初始化失败时子类应返回 false。
  virtual bool OnCreate();

  // 销毁窗口时调用。
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // 消息循环调用的系统回调：处理创建非客户区时的
  // WM_NCCREATE 消息并启用自动非客户区 DPI 缩放，
  // 让非客户区随 DPI 变化自动调整。
  // 其他消息均交给 MessageHandler 处理。
  // MessageHandler 保留为可覆盖的消息入口。
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // 获取 |window| 对应的类实例指针。
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // 更新窗口边框主题，使其与系统主题一致。
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // 顶层窗口句柄。
  HWND window_handle_ = nullptr;

  // 承载内容的子窗口句柄。
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
