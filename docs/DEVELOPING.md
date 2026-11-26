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

All three must be clean. The test suite runs without a display. CI runs the same checks on every push and pull request, on the Flutter version pinned in `.github/workflows/`. A newer Flutter can deprecate things and fail `flutter analyze`, so raise the pin on purpose, together with any code changes it asks for.

## Package

```bash
tool/package_linux.sh                  # dist/thinkspace-linux-x64.tar.gz
tool/test_install.sh                   # install.sh leaves no trace (sandboxed)
```

The installer is `packaging/install.sh`. Anything it adds or changes goes in the README's "What the installer changes" table, gets undone by `--remove`, and gets a case in `tool/test_install.sh`, which runs the real installer in a throwaway home folder with a throwaway GNOME settings store.

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
tool/ts do '{"cmd":"openImages","paths":["/path/a.png","/path/b.png"]}'   # one layer per image
tool/ts do '{"cmd":"drag","from":[100,500],"to":[300,380]}'
tool/ts state                              # layers, objects, selection and history as JSON
tool/ts shot window.png                    # what the window looks like
tool/ts export page.png 2                  # the page itself, at 2x
DISPLAY=:99 tool/xinput.py drag 420 320 700 420   # real mouse input into the real window
```

`GET /state`, `GET /screenshot`, `GET /export` and `POST /do` are documented at the top of `lib/dev/inspector.dart`.

The headless app runs the built bundle, not hot reload. Run `flutter build linux --debug` after a code change, or you will test the old build.

## Refreshing the README images

The images in the README are screenshots of the real app (`tool/ts shot`), cropped. `layers.png` and `collection.png` are animated PNGs made from two or three such shots. The furniture and room images in them were generated for the README and are not part of the repository.

To retake them, start the headless app with its own data folder, open a few images with `openImages`, put more in the collection with `importFile` and `"collection": true`, and drive the rest with `tool/ts do` and `tool/xinput.py`. Typing with `tool/xinput.py` only reaches the app when the page has keyboard focus, so click an empty part of the canvas first. Renaming many objects is easier in the saved `.thinkspace` file, which is plain JSON, than through the interface.
