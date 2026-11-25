#include "capture.h"

#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <string>

using Microsoft::WRL::ComPtr;

namespace {

// Win32Window's class (win32_window.cpp).
constexpr wchar_t kAppWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

std::wstring ThisProgram() {
  std::wstring path(MAX_PATH, L'\0');
  for (;;) {
    const DWORD n = GetModuleFileNameW(nullptr, path.data(),
                                       static_cast<DWORD>(path.size()));
    if (n == 0) return L"";
    if (n < path.size()) {
      path.resize(n);
      return path;
    }
    path.resize(path.size() * 2);
  }
}

std::wstring ProgramOf(DWORD pid) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return L"";
  std::wstring path(32768, L'\0');
  DWORD n = static_cast<DWORD>(path.size());
  const bool ok = QueryFullProcessImageNameW(process, 0, path.data(), &n);
  CloseHandle(process);
  if (!ok) return L"";
  path.resize(n);
  return path;
}

struct Search {
  std::wstring program;
  HWND found = nullptr;
};

// EnumWindows goes from the top of the stacking order down, so the first
// window of this same program is the one used last.
BOOL CALLBACK Consider(HWND hwnd, LPARAM data) {
  auto* search = reinterpret_cast<Search*>(data);
  wchar_t cls[64];
  if (GetClassNameW(hwnd, cls, 64) == 0 || wcscmp(cls, kAppWindowClass) != 0) {
    return TRUE;
  }
  // A window started hidden by a shortcut is still busy with its own.
  if (!IsWindowVisible(hwnd)) return TRUE;
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == GetCurrentProcessId()) return TRUE;
  if (_wcsicmp(ProgramOf(pid).c_str(), search->program.c_str()) != 0) {
    return TRUE;  // some other Flutter app
  }
  search->found = hwnd;
  return FALSE;
}

std::wstring LinkPath() {
  PWSTR programs = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &programs))) {
    return L"";
  }
  std::wstring path = std::wstring(programs) + L"\\Thinkspace screenshot.lnk";
  CoTaskMemFree(programs);
  return path;
}

}  // namespace

bool ForwardCapture() {
  Search search;
  search.program = ThisProgram();
  if (search.program.empty()) return false;
  EnumWindows(Consider, reinterpret_cast<LPARAM>(&search));
  if (search.found == nullptr) return false;
  DWORD pid = 0;
  GetWindowThreadProcessId(search.found, &pid);
  // Pressing the keys gave this process the right to come to the front;
  // pass it on, so the screenshot overlay and then the window can.
  AllowSetForegroundWindow(pid);
  COPYDATASTRUCT data = {kCaptureMessage, 0, nullptr};
  DWORD_PTR reply = 0;
  if (!SendMessageTimeoutW(search.found, WM_COPYDATA, 0,
                           reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                           3000, &reply)) {
    return false;
  }
  return reply == kCaptureMessage;
}

bool ReadScreenshotHotkey(WORD* hotkey) {
  const std::wstring path = LinkPath();
  if (path.empty() || GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  ComPtr<IShellLinkW> link;
  ComPtr<IPersistFile> file;
  return SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(link.GetAddressOf()))) &&
         SUCCEEDED(link.As(&file)) &&
         SUCCEEDED(file->Load(path.c_str(), STGM_READ)) &&
         SUCCEEDED(link->GetHotkey(hotkey));
}

bool WriteScreenshotShortcut(WORD hotkey) {
  const std::wstring path = LinkPath();
  const std::wstring program = ThisProgram();
  if (path.empty() || program.empty()) return false;
  const bool existed =
      GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
  ComPtr<IShellLinkW> link;
  ComPtr<IPersistFile> file;
  const bool ok =
      SUCCEEDED(CoCreateInstance(CLSID_ShellLink, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(link.GetAddressOf()))) &&
      SUCCEEDED(link->SetPath(program.c_str())) &&
      SUCCEEDED(link->SetArguments(L"--capture")) &&
      SUCCEEDED(link->SetDescription(L"Take a screenshot into Thinkspace")) &&
      SUCCEEDED(link->SetIconLocation(program.c_str(), 0)) &&
      SUCCEEDED(link->SetHotkey(hotkey)) && SUCCEEDED(link.As(&file)) &&
      SUCCEEDED(file->Save(path.c_str(), TRUE));
  // Tell Explorer, which watches Start menu shortcuts for their keys.
  if (ok) {
    SHChangeNotify(existed ? SHCNE_UPDATEITEM : SHCNE_CREATE, SHCNF_PATHW,
                   path.c_str(), nullptr);
  }
  return ok;
}

bool RemoveScreenshotShortcut() {
  const std::wstring path = LinkPath();
  if (path.empty()) return false;
  if (!DeleteFileW(path.c_str())) {
    return GetLastError() == ERROR_FILE_NOT_FOUND;
  }
  SHChangeNotify(SHCNE_DELETE, SHCNF_PATHW, path.c_str(), nullptr);
  return true;
}
