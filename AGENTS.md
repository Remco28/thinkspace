# Thinkspace — notes for AI collaborators

Thinkspace is a small desktop app for combining pictures, lines and layers to explain an idea. Read `README.md` for what it is and why (its "Why it exists" section is the product's compass) and `docs/ARCHITECTURE.md` for how it fits together.

## Working here

- **Stack:** Flutter/Dart, Linux first. The SDK lives at `~/development/flutter` on the maintainer's machine (`export PATH="$HOME/development/flutter/bin:$PATH"`).
- **Before you finish a change:** `dart format lib test && flutter analyze && flutter test`. All three must be clean. The suite needs no display.
- **Look at it for real:** `tool/run_headless.sh &` starts the actual app on a virtual display with the inspector on port 47651. It uses its own data folder (`THINKSPACE_DATA_DIR`, default `/tmp/thinkspace-headless`); never point it at the real one, because autosave would overwrite the user's recovery copy and prefs. `tool/ts state|shot|export|do` talk to it; `tool/xinput.py` sends genuine mouse and keyboard input. Rebuild with `flutter build linux --debug` after code changes — the headless app runs the built bundle, not hot reload.
- **Keep the product small.** It is the thing you reach for to *show someone what you mean*. Do not grow it into a graphics suite: no masks, blend modes, filters, curves or colour management. A new feature should serve arranging, marking up and explaining.
- **Keep the three things apart:** the document (data), the view (zoom/pan), the export. View changes never rewrite the document. A gesture is one undo step, recorded on release.
- **Images live outside the document** (`AssetStore`). Operations that change pixels create a new asset and repoint the object — never mutate an existing asset.
- **No new dependencies without a real gap.** Current ones: `file_selector`, `desktop_drop`, `ffi` (the Windows clipboard). Image clipboard goes through `xclip`/`wl-clipboard` on purpose.

## Gotchas that bit once

- `GestureDetector.onDoubleTap` delays every single tap by ~300 ms. Use `QuickTap` (`lib/ui/widgets.dart`).
- Do not unfocus on canvas clicks — it kills the global shortcuts. Give focus back to the shell node.
- Dialogs are not inside the shell's `RepaintBoundary`; the inspector screenshot uses the app-level `appShotKey`.
- `dart format` rewrites one-line `if`s; the `curly_braces_in_flow_control_structures` lint must stay clean for CI.
- Do not dispose `ui.Image`s still referenced by a built widget (`AssetStore.clear` deliberately doesn't).
- Port 8765 on this machine is taken by something else; the inspector defaults to 47651.
- `tool/run_headless.sh` only builds when no bundle exists; after a change, `flutter build linux --debug` first or you test the old build.
- Stop the headless app with `pgrep -f "debug/bundle/thinkspac[e]" | xargs -r kill`. A plain `pkill -f thinkspace` also matches the shell running it.
- X screenshots of the virtual display come out black; use `tool/ts shot`.
- The virtual display has no window manager, so full screen, maximise and window frames do nothing there. To test them, run `DISPLAY=:99 dbus-run-session -- xfwm4 --compositor=off --sm-client-disable &` (without its own D-Bus session it exits at once), and remember the window then sits below a 24 px title bar for `tool/xinput.py`.
- Flutter's popup menus are at most about 280 px wide, whatever width a row asks for.

## Human testing

When a build is ready for the maintainer to try, prepare a round under `human_feedback/<round-id>/` following the agent-office workflow (static, offline `index.html`; returns a ZIP). Earlier rounds are there to copy from; the newest is the best template. Read returned ZIPs as feedback; never execute files from them.

## agent-office (optional, per machine)

If this machine runs agent-office, start with:

```bash
office begin --project ~/Projects/Thinkspace --by <your-agent-name>
```

and leave a note in the work log (`office work note <id> "..."`) as you go. Everything that is not code — decisions, dead ends, conventions — belongs there; code belongs in git.

<!-- agent-office -->
## Agent Office

This repository (`Thinkspace`) uses **Agent Office**, the shared working memory for agents on this machine. You arrive with no memory of earlier sessions: the office is how you pick up what the last agent knew, and how the next one picks up from you. Code goes in git; everything else worth keeping goes in the office.

**One agent, one repository.** Work only in this repository. If you are asked to work in another one, suggest that the human start a new agent there instead of switching.

### Start

1. Check in from inside this repository (any git worktree of it counts):
   ```bash
   office begin --by <your-tool>        # for example --by codex
   ```
   If you have been told not to change anything, run `office peek --by <your-tool>` instead.
2. The office gives back a numbered name for this run, like `codex-4821`. Use it on every later call (`--by codex-4821`, or `export OFFICE_AUTHOR=codex-4821`), so what you write is signed.
3. Read the briefing: the tools and skills this machine has, unfinished work, recent activity, and this project's memories. Prefer a listed tool or skill to building your own.
4. Start your first reply to the human with:
   > `Working on Thinkspace within Agent Office (<numbered-name>).`

### While you work

**Write while you still know it.** You will not know when your session ends.

- **Work log, the handoff:** `office work open "<title>"`, then `office work note <id> "<where you got to>"` as you go, and `office work close <id> "<outcome>"` once the work is finished, not when one step of it is. A note says where you stopped and what you would check next, not every file you touched.
- **Memories:** `office remember "<fact>"` for decisions and why, conventions, dead ends, and facts the next agent would otherwise rediscover. Add `--global` only for a rule that holds in every project. Never store secrets, `.env` contents, source dumps or progress chatter. If a memory is wrong, correct it and say why (`office forget <id>` removes it).
- **Finding things:** `office context "<task>"` before you start something, `office search "<words>"` for one fact. An empty result is real: nothing relevant is recorded.
- **Tools:** `office tools add <name> --use "<command>" "<what it is>"` for anything installed here that you would want again.
- **Files outside this repository:** before you change one (a tool's settings, a shared config), copy the original next to it, for example `settings.toml.bak`, and say in your work note what you changed and where. Git cannot undo it, and the next agent will not know.
- **Deleting:** never delete or overwrite something you did not create without asking the human first.
- **Committing:** commit, or ask the human to, before a large change, so it can be undone.
- **Temporary files:** put them in your scratch folder (or the system temp folder), never in this repository or the home folder. Link big dependency folders (`node_modules`, `.venv`) rather than copying them. Delete what you made before you finish, and say in your work note if you left anything.
- **Issues:** when the office itself is in your way (not a bug in this repository), check `office issues`, then `office issue open "<what>"`, or add a note to the one already there.

`office help` lists every command.
