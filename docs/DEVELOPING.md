# Developing Thinkspace

How to build, test and package the app, and how to watch it run. For how the code is organised, read [ARCHITECTURE.md](ARCHITECTURE.md). For interface decisions, read [DESIGN.md](DESIGN.md).

## Set up

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install/linux). On Linux you also need a C++ toolchain:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
flutter pub get
flutter run -d linux
```

Pasting images from the clipboard on Linux uses `xclip` or `wl-clipboard`, so install one of them to try that.

## Before you send a change

```bash
dart format lib test && flutter analyze && flutter test
```

All three must be clean. The test suite runs without a display. CI runs the same checks on every push and pull request.

## Package

```bash
tool/package_linux.sh                  # dist/thinkspace-linux-x64.tar.gz
```

### Windows

Build on a Windows machine with Flutter and Visual Studio's C++ tools, or let the `Windows release` workflow do it when a release is published.

```powershell
flutter pub get
flutter run -d windows
powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1   # zip and installer in dist\
```

## Project map

| Path | What is there |
|---|---|
| `lib/model/` | The document: objects, layers, collection, assets and geometry. Plain data, no UI. |
| `lib/editor/` | The controller (state, history, operations), the pointer interactor, painting and rendering, and image operations. |
| `lib/ui/` | The window: shell, toolbar, layers, collection, properties and menus. |
| `lib/io/` | Clipboard, file dialogs and the built-in sample. |
| `lib/dev/inspector.dart` | A localhost-only door for developers and agents. |
| `test/` | Model, interaction, layer, cut-out, project and widget tests. |
| `docs/` | Architecture, design decisions and these notes. |
| `AGENTS.md` | Notes for AI collaborators working in this repository. |

## Watching it run

Set `THINKSPACE_DEBUG_PORT` and the app listens on `127.0.0.1` only. `tool/run_headless.sh` does this for you on a virtual display (Xvfb) with its own data folder, so it never touches your real recovery copy or settings.

```bash
tool/run_headless.sh &                     # real window on a virtual display
tool/ts do '{"cmd":"sample"}'              # load the storefront sample
tool/ts do '{"cmd":"drag","from":[100,500],"to":[300,380]}'
tool/ts state                              # layers, objects, selection and history as JSON
tool/ts shot window.png                    # what the window looks like
tool/ts export page.png 2                  # the page itself, at 2x
DISPLAY=:99 tool/xinput.py drag 420 320 700 420   # real mouse input into the real window
```

`GET /state`, `GET /screenshot`, `GET /export` and `POST /do` are documented at the top of `lib/dev/inspector.dart`.

The headless app runs the built bundle, not hot reload. Run `flutter build linux --debug` after a code change, or you will test the old build.

## Refreshing the README images

The pictures in the README come from the running app. Load the storefront sample in the headless app, make the marks with `tool/ts do`, then take `tool/ts shot` for the whole window and `tool/ts export` for the page. The images in `docs/images/` are those captures on a soft background with rounded corners.
