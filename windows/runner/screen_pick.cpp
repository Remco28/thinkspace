#include "screen_pick.h"

#include <wincodec.h>
#include <windowsx.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <utility>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kPickClass[] = L"THINKSPACE_SCREEN_PICK";
// The app's accent (kAccent in lib/ui/design.dart).
constexpr COLORREF kAccent = RGB(0x2F, 0x6B, 0xFF);

// One overlay: the frozen screen, bright and dimmed, and the box being
// dragged. Lives from PickScreenArea until the overlay window is destroyed.
struct Pick {
  std::function<void(const std::wstring&)> done;
  int x = 0, y = 0, w = 0, h = 0;  // the virtual screen, in pixels
  HDC bright = nullptr, dim = nullptr, back = nullptr;
  HBITMAP bright_bmp = nullptr, dim_bmp = nullptr, back_bmp = nullptr;
  HGDIOBJ bright_old = nullptr, dim_old = nullptr, back_old = nullptr;
  const unsigned char* bits = nullptr;  // the bright pixels, top-down BGRA
  HFONT font = nullptr;
  bool dragging = false;
  bool was_active = false;
  bool finished = false;
  POINT from = {}, to = {};
};

RECT Box(POINT a, POINT b) {
  return {std::min(a.x, b.x), std::min(a.y, b.y), std::max(a.x, b.x),
          std::max(a.y, b.y)};
}

HBITMAP Dib(HDC ref, int w, int h, void** bits) {
  BITMAPINFO bi = {};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;  // top-down rows
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  return CreateDIBSection(ref, &bi, DIB_RGB_COLORS, bits, nullptr, 0);
}

void FreeGdi(Pick* p) {
  if (p->bright) {
    SelectObject(p->bright, p->bright_old);
    DeleteDC(p->bright);
  }
  if (p->dim) {
    SelectObject(p->dim, p->dim_old);
    DeleteDC(p->dim);
  }
  if (p->back) {
    SelectObject(p->back, p->back_old);
    DeleteDC(p->back);
  }
  if (p->bright_bmp) DeleteObject(p->bright_bmp);
  if (p->dim_bmp) DeleteObject(p->dim_bmp);
  if (p->back_bmp) DeleteObject(p->back_bmp);
  if (p->font) DeleteObject(p->font);
  p->bright = p->dim = p->back = nullptr;
  p->bright_bmp = p->dim_bmp = p->back_bmp = nullptr;
  p->font = nullptr;
}

// The box as a PNG in the temp folder; empty on failure.
std::wstring Save(const Pick* p, RECT r) {
  const int w = r.right - r.left, h = r.bottom - r.top;
  std::vector<unsigned char> out(static_cast<size_t>(w) * h * 4);
  for (int row = 0; row < h; ++row) {
    const unsigned char* src =
        p->bits + (static_cast<size_t>(r.top + row) * p->w + r.left) * 4;
    unsigned char* dst = out.data() + static_cast<size_t>(row) * w * 4;
    std::memcpy(dst, src, static_cast<size_t>(w) * 4);
    // GDI leaves the fourth byte at zero; the picture is fully opaque.
    for (int i = 3; i < w * 4; i += 4) dst[i] = 255;
  }
  wchar_t dir[MAX_PATH + 1];
  const DWORD n = GetTempPathW(MAX_PATH + 1, dir);
  if (n == 0 || n > MAX_PATH) return L"";
  std::wstring path = std::wstring(dir) + L"thinkspace-screenshot-" +
                      std::to_wstring(GetTickCount64()) + L".png";
  return WritePng(path, out.data(), w, h, w * 4) ? path : L"";
}

// Close the overlay and report: the box, or nothing (null) if cancelled.
void Finish(HWND hwnd, Pick* p, const RECT* box) {
  if (p->finished) return;
  p->finished = true;
  const std::wstring path = box ? Save(p, *box) : L"";
  auto done = std::move(p->done);
  DestroyWindow(hwnd);  // WM_NCDESTROY frees |p|
  if (done) done(path);
}

void PaintHint(Pick* p, HWND hwnd) {
  const UINT dpi = GetDpiForWindow(hwnd);
  const int s = dpi > 0 ? static_cast<int>(dpi) : 96;  // pixels per inch
  if (!p->font) {
    p->font = CreateFontW(-MulDiv(15, s, 96), 0, 0, 0, FW_NORMAL, FALSE, FALSE,
                          FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                          CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                          DEFAULT_PITCH, L"Segoe UI");
  }
  const wchar_t* text = L"Drag over what you want.   Esc cancels.";
  HGDIOBJ old_font = SelectObject(p->back, p->font);
  RECT t = {0, 0, 0, 0};
  DrawTextW(p->back, text, -1, &t, DT_CALCRECT | DT_SINGLELINE);
  const int pad_x = MulDiv(14, s, 96), pad_y = MulDiv(7, s, 96);
  const int tw = t.right - t.left + pad_x * 2, th = t.bottom - t.top + pad_y * 2;
  // Top middle of the main monitor, which sits at (0, 0) on the desktop.
  const int cx = -p->x + GetSystemMetrics(SM_CXSCREEN) / 2;
  const int top = -p->y + MulDiv(28, s, 96);
  RECT pill = {cx - tw / 2, top, cx + tw / 2, top + th};
  HBRUSH brush = CreateSolidBrush(RGB(0x22, 0x24, 0x2A));
  HGDIOBJ old_brush = SelectObject(p->back, brush);
  HGDIOBJ old_pen = SelectObject(p->back, GetStockObject(NULL_PEN));
  RoundRect(p->back, pill.left, pill.top, pill.right, pill.bottom, th, th);
  SelectObject(p->back, old_pen);
  SelectObject(p->back, old_brush);
  DeleteObject(brush);
  SetBkMode(p->back, TRANSPARENT);
  SetTextColor(p->back, RGB(0xFF, 0xFF, 0xFF));
  DrawTextW(p->back, text, -1, &pill, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(p->back, old_font);
}

void Paint(HWND hwnd, Pick* p) {
  PAINTSTRUCT ps;
  HDC dc = BeginPaint(hwnd, &ps);
  const RECT& a = ps.rcPaint;
  const int aw = a.right - a.left, ah = a.bottom - a.top;
  BitBlt(p->back, a.left, a.top, aw, ah, p->dim, a.left, a.top, SRCCOPY);
  if (p->dragging) {
    const RECT r = Box(p->from, p->to);
    RECT lit;
    if (IntersectRect(&lit, &r, &a)) {
      BitBlt(p->back, lit.left, lit.top, lit.right - lit.left,
             lit.bottom - lit.top, p->bright, lit.left, lit.top, SRCCOPY);
    }
    HPEN pen = CreatePen(PS_SOLID, 2, kAccent);
    HGDIOBJ old_pen = SelectObject(p->back, pen);
    HGDIOBJ old_brush = SelectObject(p->back, GetStockObject(NULL_BRUSH));
    Rectangle(p->back, r.left - 1, r.top - 1, r.right + 1, r.bottom + 1);
    SelectObject(p->back, old_brush);
    SelectObject(p->back, old_pen);
    DeleteObject(pen);
  } else {
    PaintHint(p, hwnd);
  }
  BitBlt(dc, a.left, a.top, aw, ah, p->back, a.left, a.top, SRCCOPY);
  EndPaint(hwnd, &ps);
}

POINT Clamp(const Pick* p, LPARAM lparam) {
  return {std::clamp(static_cast<LONG>(GET_X_LPARAM(lparam)), 0L,
                     static_cast<LONG>(p->w)),
          std::clamp(static_cast<LONG>(GET_Y_LPARAM(lparam)), 0L,
                     static_cast<LONG>(p->h))};
}

LRESULT CALLBACK PickProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  auto* p = reinterpret_cast<Pick*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (p == nullptr) return DefWindowProc(hwnd, msg, wparam, lparam);
  switch (msg) {
    case WM_PAINT:
      Paint(hwnd, p);
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_CROSS));
      return TRUE;
    case WM_DPICHANGED:
      return 0;  // it covers every monitor; never resize it
    case WM_LBUTTONDOWN:
      p->dragging = true;
      p->from = p->to = Clamp(p, lparam);
      SetCapture(hwnd);
      InvalidateRect(hwnd, nullptr, FALSE);  // the hint goes
      return 0;
    case WM_MOUSEMOVE:
      if (p->dragging) {
        RECT changed = Box(p->from, p->to);
        p->to = Clamp(p, lparam);
        const RECT now = Box(p->from, p->to);
        UnionRect(&changed, &changed, &now);
        InflateRect(&changed, 4, 4);
        InvalidateRect(hwnd, &changed, FALSE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (p->dragging) {
        p->to = Clamp(p, lparam);
        p->dragging = false;
        ReleaseCapture();
        const RECT r = Box(p->from, p->to);
        if (r.right - r.left >= 4 && r.bottom - r.top >= 4) {
          Finish(hwnd, p, &r);
        } else {
          InvalidateRect(hwnd, nullptr, FALSE);  // a click: keep picking
        }
      }
      return 0;
    case WM_CAPTURECHANGED:
      if (p->dragging && reinterpret_cast<HWND>(lparam) != hwnd) {
        p->dragging = false;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_RBUTTONUP:
      Finish(hwnd, p, nullptr);
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) Finish(hwnd, p, nullptr);
      return 0;
    case WM_ACTIVATE:
      // Switching to another window (Alt+Tab, Win key) cancels.
      if (LOWORD(wparam) == WA_INACTIVE) {
        if (p->was_active) Finish(hwnd, p, nullptr);
      } else {
        p->was_active = true;
      }
      return 0;
    case WM_CLOSE:
      Finish(hwnd, p, nullptr);
      return 0;
    case WM_NCDESTROY: {
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      auto done = std::move(p->done);
      const bool tell = !p->finished;
      FreeGdi(p);
      delete p;
      if (tell && done) done(L"");
      return 0;
    }
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

}  // namespace

void PickScreenArea(std::function<void(const std::wstring& png)> done) {
  static bool registered = false;
  HINSTANCE instance = GetModuleHandle(nullptr);
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = PickProc;
    wc.hInstance = instance;
    wc.lpszClassName = kPickClass;
    wc.hCursor = LoadCursor(nullptr, IDC_CROSS);
    registered = RegisterClassW(&wc) != 0;
  }
  auto p = std::make_unique<Pick>();
  p->done = std::move(done);
  p->x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  p->y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  p->w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  p->h = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  HDC screen = GetDC(nullptr);
  void* bright_bits = nullptr;
  void* dim_bits = nullptr;
  bool ok = registered && screen != nullptr && p->w > 0 && p->h > 0;
  if (ok) {
    p->bright_bmp = Dib(screen, p->w, p->h, &bright_bits);
    p->dim_bmp = Dib(screen, p->w, p->h, &dim_bits);
    p->back_bmp = CreateCompatibleBitmap(screen, p->w, p->h);
    p->bright = CreateCompatibleDC(screen);
    p->dim = CreateCompatibleDC(screen);
    p->back = CreateCompatibleDC(screen);
    ok = p->bright_bmp && p->dim_bmp && p->back_bmp && p->bright && p->dim &&
         p->back;
  }
  if (ok) {
    p->bright_old = SelectObject(p->bright, p->bright_bmp);
    p->dim_old = SelectObject(p->dim, p->dim_bmp);
    p->back_old = SelectObject(p->back, p->back_bmp);
    ok = BitBlt(p->bright, 0, 0, p->w, p->h, screen, p->x, p->y,
                SRCCOPY | CAPTUREBLT) != 0;
  }
  if (screen) ReleaseDC(nullptr, screen);
  if (ok) {
    GdiFlush();
    p->bits = static_cast<const unsigned char*>(bright_bits);
    // The dimmed copy behind the box: a little over half as bright.
    auto* d = static_cast<unsigned char*>(dim_bits);
    const size_t n = static_cast<size_t>(p->w) * p->h * 4;
    for (size_t i = 0; i < n; ++i) d[i] = (p->bits[i] * 9) >> 4;
  }
  HWND hwnd = nullptr;
  if (ok) {
    hwnd = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kPickClass,
                           L"Thinkspace screenshot", WS_POPUP, p->x, p->y,
                           p->w, p->h, nullptr, nullptr, instance, nullptr);
  }
  if (hwnd == nullptr) {
    FreeGdi(p.get());
    auto report = std::move(p->done);
    if (report) report(L"");
    return;
  }
  // From here the window owns the pick; WM_NCDESTROY frees it.
  SetWindowLongPtr(hwnd, GWLP_USERDATA,
                   reinterpret_cast<LONG_PTR>(p.release()));
  ShowWindow(hwnd, SW_SHOW);
  SetForegroundWindow(hwnd);
  SetFocus(hwnd);
}

bool WritePng(const std::wstring& path, const unsigned char* bgra, int width,
              int height, int stride) {
  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  const UINT size = static_cast<UINT>(stride) * static_cast<UINT>(height);
  bool ok =
      SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(factory.GetAddressOf()))) &&
      SUCCEEDED(factory->CreateStream(stream.GetAddressOf())) &&
      SUCCEEDED(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE));
  if (!ok) return false;
  ok = SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                        encoder.GetAddressOf())) &&
       SUCCEEDED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache)) &&
       SUCCEEDED(encoder->CreateNewFrame(frame.GetAddressOf(), nullptr)) &&
       SUCCEEDED(frame->Initialize(nullptr)) &&
       SUCCEEDED(frame->SetSize(width, height)) &&
       SUCCEEDED(frame->SetPixelFormat(&format)) &&
       IsEqualGUID(format, GUID_WICPixelFormat32bppBGRA) &&
       SUCCEEDED(frame->WritePixels(height, stride, size,
                                    const_cast<BYTE*>(bgra))) &&
       SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit());
  frame.Reset();
  encoder.Reset();
  stream.Reset();  // closes the file
  if (!ok) DeleteFileW(path.c_str());
  return ok;
}
