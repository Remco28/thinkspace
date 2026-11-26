#ifndef RUNNER_CAPTURE_H_
#define RUNNER_CAPTURE_H_

#include <windows.h>

// `thinkspace --capture`, which the screenshot shortcut runs, hands the
// screenshot to the Thinkspace window used last with this WM_COPYDATA tag.
constexpr ULONG_PTR kCaptureMessage = 0x54534350;  // "TSCP"

// Finds the Thinkspace window used last (the highest in the stacking order)
// and asks it to take a screenshot. False if none is open or it didn't
// answer, in which case this process takes the screenshot itself.
bool ForwardCapture();

// The screenshot shortcut is a "Thinkspace screenshot" entry in the
// person's Start menu that runs `thinkspace --capture`, with Windows' own
// shortcut keys on it. Explorer listens for those keys, so nothing of ours
// runs in the background. Hotkeys are IShellLink's: the key code in the low
// byte, HOTKEYF_SHIFT/CONTROL/ALT in the high byte.
bool ReadScreenshotHotkey(WORD* hotkey);  // false: there is no shortcut
bool WriteScreenshotShortcut(WORD hotkey);
bool RemoveScreenshotShortcut();

#endif  // RUNNER_CAPTURE_H_
