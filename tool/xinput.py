#!/usr/bin/env python3
"""Inject real mouse/keyboard input into the headless display (:99) via XTEST.

  tool/xinput.py move 640 400
  tool/xinput.py click 640 400 [button]
  tool/xinput.py drag 300 300 500 400 [steps]
  tool/xinput.py type "hello"          # printable characters
  tool/xinput.py key ctrl+z | Delete | Escape | ctrl+shift+s
  tool/xinput.py scroll 640 400 -3     # negative = up (zoom in)
  tool/xinput.py shot out.png          # real X screenshot of the display

Coordinates are window pixels on the 1440x900 virtual screen.
"""
import ctypes, ctypes.util, os, subprocess, sys, time

x11 = ctypes.CDLL("libX11.so.6")
xtst = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XStringToKeysym.restype = ctypes.c_ulong
x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
x11.XKeysymToKeycode.restype = ctypes.c_ubyte
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XFlush.argtypes = [ctypes.c_void_p]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

d = x11.XOpenDisplay(os.environ.get("DISPLAY", ":99").encode())
if not d:
    sys.exit("cannot open display")

def flush(delay=0.02):
    x11.XFlush(d)
    time.sleep(delay)

def move(x, y):
    xtst.XTestFakeMotionEvent(d, -1, int(x), int(y), 0)
    flush()

def button(b, down):
    xtst.XTestFakeButtonEvent(d, b, 1 if down else 0, 0)
    flush()

NAMED = {" ": "space", "\n": "Return", "\t": "Tab", "?": "question", "!": "exclam", ".": "period", ",": "comma", "'": "apostrophe", "-": "minus", "_": "underscore", ":": "colon", ";": "semicolon", "(": "parenleft", ")": "parenright", "/": "slash"}

def keycode(name):
    ks = x11.XStringToKeysym(name.encode())
    if not ks:
        sys.exit(f"unknown key {name}")
    return x11.XKeysymToKeycode(d, ks)

def press(name, down):
    xtst.XTestFakeKeyEvent(d, keycode(name), 1 if down else 0, 0)
    flush(0.01)

def tap(name, mods=()):
    for m in mods:
        press(m, True)
    press(name, True)
    press(name, False)
    for m in reversed(mods):
        press(m, False)

def type_text(s):
    for ch in s:
        name = NAMED.get(ch, ch)
        if ch.isupper():
            tap(name, ["Shift_L"])
        elif ch in "?!:_()":
            tap(name, ["Shift_L"])
        else:
            tap(name)

MODS = {"ctrl": "Control_L", "shift": "Shift_L", "alt": "Alt_L"}

def key(spec):
    parts = spec.split("+")
    mods = [MODS[p.lower()] for p in parts[:-1]]
    k = parts[-1]
    tap(k if len(k) > 1 else NAMED.get(k, k), mods)

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "move":
    move(*map(float, args[:2]))
elif cmd == "click":
    move(*map(float, args[:2]))
    b = int(args[2]) if len(args) > 2 else 1
    button(b, True); button(b, False)
elif cmd == "drag":
    x1, y1, x2, y2 = map(float, args[:4])
    steps = int(args[4]) if len(args) > 4 else 12
    move(x1, y1); button(1, True)
    for i in range(1, steps + 1):
        move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
    button(1, False)
elif cmd == "type":
    type_text(args[0])
elif cmd == "key":
    key(args[0])
elif cmd == "scroll":
    move(float(args[0]), float(args[1]))
    n = int(args[2])
    b = 4 if n < 0 else 5
    for _ in range(abs(n)):
        button(b, True); button(b, False)
elif cmd == "shot":
    subprocess.run(["import", "-window", "root", args[0]], check=True, env={**os.environ, "DISPLAY": ":99"})
else:
    sys.exit(__doc__)
x11.XFlush(d)
