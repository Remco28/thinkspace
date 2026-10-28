**1. Does the plan fix it in every case? No.** It fixes the plain-drag cases where the connector remains the single selection: the existing flags currently suppress bending even when the press hits that connector. But the double-click-on-text check returns earlier, and Alt or Shift can change the selection before the bend branch is reached. Those presses won’t bend the originally selected connector.

There’s also a mismatch in the proposed click behavior: once the branch sets `_mode` to `lineEnd`, `pointerUp` does not call `_finishClick`. It calls that only for `move` gestures. So keeping the flags does not, by itself, preserve click behavior.

**2. What changes or breaks:**

- **MEDIUM — click-to-cycle and pick-the-top-on-release stop working on a no-movement press.** If the selected connector is under another hit, a plain click should select the top object; if it is selected at the top of a stack, a click should cycle down. Starting `lineEnd` skips `_finishClick`, so neither selection change happens. The user can recover by clicking elsewhere or changing selection, but the click appears ineffective. See the current click handling in [`interactor.dart`](/home/frank/Projects/Thinkspace/lib/editor/interactor.dart:945) and [`_finishClick`](/home/frank/Projects/Thinkspace/lib/editor/interactor.dart:1000).

- **Double-click on text remains intact if its early check stays ahead of the new branch.** For example, double-clicking text above a selected connector still enters text editing. That means the plan does not bend the connector on every press that hits it, but moving the bend check ahead of the text check would break the existing edit gesture.

- **Alt-click and Shift-click are not automatically broken if the bend check still uses the selection after modifier handling.** Alt may select the object below the current one; Shift may add an object to the selection. In those cases, the connector may no longer be the single selection, so bending should not start. If the intent is to bend based on the selection *before* modifier handling, those gestures could instead bend the connector and defeat the requested selection action.

Dragging a selected connector beneath another object will now bend it, which matches the stated connector rule. For other selected objects, the existing drag behavior is unaffected. The key implementation detail is to route an unmoved `lineEnd` press through the appropriate click-finishing behavior; the flags alone won’t preserve it.
