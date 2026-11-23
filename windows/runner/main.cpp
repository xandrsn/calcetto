#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
  // Portrait phone-shaped window so the mobile-first UI looks native on
  // desktop rather than stretched across a landscape canvas. Size is logical;
  // Win32Window::Create scales it for the monitor DPI.
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(460, 900);
  if (!window.Create(L"Calcetto", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Center on the work area of the monitor the window opened on. Done before
  // the window is shown (Show() fires on the first Flutter frame), so there is
  // no visible jump.
  if (HWND hwnd = window.GetHandle()) {
    RECT wr;
    GetWindowRect(hwnd, &wr);
    const int win_w = wr.right - wr.left;
    const int win_h = wr.bottom - wr.top;
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{};
    mi.cbSize = sizeof(mi);
    if (GetMonitorInfo(monitor, &mi)) {
      const int work_w = mi.rcWork.right - mi.rcWork.left;
      const int work_h = mi.rcWork.bottom - mi.rcWork.top;
      const int x = mi.rcWork.left + (work_w - win_w) / 2;
      const int y = mi.rcWork.top + (work_h - win_h) / 2;
      SetWindowPos(hwnd, nullptr, x, y, 0, 0,
                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
