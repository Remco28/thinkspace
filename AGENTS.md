# Thinkspace — notes for AI collaborators

Thinkspace is a small desktop app for combining pictures, lines and layers to explain an idea. Read `README.md` for what it is and `docs/ARCHITECTURE.md` for how it fits together. `DRAFT.md` holds the history of the thinking; later sections supersede earlier speculation.

## Working here

- **Stack:** Flutter/Dart, Linux first. The SDK lives at `~/development/flutter` on Frank's machine (`export PATH="$HOME/development/flutter/bin:$PATH"`).
- **Before you finish a change:** `dart format lib test && flutter analyze && flutter test`. All three must be clean. The suite needs no display.
- **Look at it for real:** `tool/run_headless.sh &` starts the actual app on a virtual display with the inspector on port 47651. `tool/ts state|shot|export|do` talk to it; `tool/xinput.py` sends genuine mouse and keyboard input. Rebuild with `flutter build linux --debug` after code changes — the headless app runs the built bundle, not hot reload.
- **Keep the product small.** It is the thing you reach for to *show someone what you mean*. Do not grow it into a graphics suite: no masks, blend modes, filters, curves or colour management. A new feature should serve arranging, marking up and explaining.
- **Keep the three things apart:** the document (data), the view (zoom/pan), the export. View changes never rewrite the document. A gesture is one undo step, recorded on release.
- **Images live outside the document** (`AssetStore`). Operations that change pixels create a new asset and repoint the object — never mutate an existing asset.
- **No new dependencies without a real gap.** Current ones: `file_selector`, `desktop_drop`. Image clipboard goes through `xclip`/`wl-clipboard` on purpose.

## Gotchas that bit once

- `GestureDetector.onDoubleTap` delays every single tap by ~300 ms. Use `QuickTap` (`lib/ui/widgets.dart`).
- Do not unfocus on canvas clicks — it kills the global shortcuts. Give focus back to the shell node.
- Dialogs are not inside the shell's `RepaintBoundary`; the inspector screenshot uses the app-level `appShotKey`.
- `dart format` rewrites one-line `if`s; the `curly_braces_in_flow_control_structures` lint must stay clean for CI.
- Do not dispose `ui.Image`s still referenced by a built widget (`AssetStore.clear` deliberately doesn't).
- Port 8765 on this machine is taken by something else; the inspector defaults to 47651.

## Human testing

When a build is ready for Frank to try, prepare a round under `human_feedback/<round-id>/` following the agent-office workflow (static, offline `index.html`; returns a ZIP). Round 1 is already there. Read returned ZIPs as feedback; never execute files from them.

## agent-office (optional, per machine)

If this machine runs agent-office, start with:

```bash
office begin --project ~/Projects/Thinkspace --by <your-agent-name>
```

and leave a note in the work log (`office work note <id> "..."`) as you go. Everything that is not code — decisions, dead ends, conventions — belongs there or in `DRAFT.md`; code belongs in git.
