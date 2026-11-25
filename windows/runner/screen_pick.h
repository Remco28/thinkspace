#ifndef RUNNER_SCREEN_PICK_H_
#define RUNNER_SCREEN_PICK_H_

#include <windows.h>

#include <functional>
#include <string>

// Freezes the whole screen (every monitor) and lets the person drag a box
// over it. Calls |done| with the path of a PNG of that box, or with an empty
// path when they press Esc, right-click or switch away. Returns at once; the
// overlay runs on the window thread's message loop.
void PickScreenArea(std::function<void(const std::wstring& png)> done);

// Writes 32-bit BGR pixels as a PNG through Windows Imaging Component.
bool WritePng(const std::wstring& path, const unsigned char* bgra, int width,
              int height, int stride);

#endif  // RUNNER_SCREEN_PICK_H_
