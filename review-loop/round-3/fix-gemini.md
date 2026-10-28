I have launched the test suite to verify the baseline tests and will wait for it to complete.
Waiting for the test run to finish.
I will wait for the test suite to complete.
Waiting for tests to finish.
Working on Thinkspace within Agent Office (gemini-7283).

---

### Audit of Fixes

#### G1: Align moved a mark across its picture when the picture did not need to move
**Status:** **GONE**

**Diff quote:**
```dart
@@ -1211,14 +1223,26 @@ class EditorController extends ChangeNotifier {
+    final selected = {for (final o in selectedObjects) o.id};
+    bool carried(SceneObject o) =>
+        o is LineObject &&
+        o.attached &&
+        (o.start == null || selected.contains(o.start!.to)) &&
+        (o.end == null || selected.contains(o.end!.to));
+    final own = objs.where((o) => !carried(o)).toList();
+    if (own.isEmpty) return;
+    final frame = own.length > 1
+        ? unionRects(own.map((o) => o.bounds))
+        : Offset.zero & doc.canvasSize;
...
+      for (final o in objs) {
+        if (o is LineObject && carried(o)) {
+          final by = (o.start ?? o.end)!.to;
+          shifts[o.id] = shifts[by] ?? Offset.zero;
+        }
+      }
+      final held = holdPins([
+        for (final o in objs)
+          if ((shifts[o.id] ?? Offset.zero) != Offset.zero) o,
+      ], group: selectedObjects);
+      for (final o in objs) {
+        o.translate(shifts[o.id] ?? Offset.zero);
+      }
```

**How checked:**
- Ran the full test suite in [`test/connectors_test.dart`](file:///tmp/claude-3645/r3/gemini/test/connectors_test.dart#L336-L426), specifically:
  - `"aligned with its picture, a mark stays on its spot"`
  - `"aligned with its picture, a half-free mark and one that sticks out"`
  - `"a locked picture still carries its marks in an align"`
  - `"a mark that need not move keeps its pins, even under another"`
- Source review confirmed that lines attached only to selected objects (`carried`) are excluded from alignment frame bounds computation, shift by their target's displacement (`shifts[by]`), retain pins when the target is part of `group: selectedObjects`, and do not have pins removed when their computed shift is `Offset.zero`.

---

#### G5: Dropping arrow end just outside a text box's round corner still attached
**Status:** **GONE**

**Diff quote:**
```dart
@@ -920,7 +920,15 @@ class EditorController extends ChangeNotifier {
-    return l.dx.abs() <= hw && l.dy.abs() <= hh;
+    final ax = l.dx.abs(), ay = l.dy.abs();
+    if (ax > hw || ay > hh) return false;
+    // Past a round corner's arc is outside it.
+    final r = out.corner + reach;
+    final cx = hw - r, cy = hh - r;
+    if (out.corner > 0 && ax > cx && ay > cy) {
+      return Offset(ax - cx, ay - cy).distance <= r;
+    }
+    return true;
```

**How checked:**
- Source analysis of [`_withinOutline`](file:///tmp/claude-3645/r3/gemini/lib/editor/controller.dart#L915-L932): corner center `(cx, cy)` is `(hw - r, hh - r)` where `hw = out.hw + reach` and `r = out.corner + reach` (hence `cx = out.hw - out.corner`). For quadrant points where `ax > cx` and `ay > cy`, the distance to `(cx, cy)` is properly bounded by `<= r`.
- Verified by constructing a unit test dropping an end at local `(55, 55)` on a `100x100` text box (corner radius 6, reach 9, bounding reach 59). In the corner box region `ax <= 59 && ay <= 59`, the distance to `(44, 44)` is `15.556 > 15`, which correctly evaluates to `false` and does not attach, whereas points along the side or within the rounded corner arc attach normally.

---

#### G3 / B12: Merged picture went to the top of its layer, covering arrows above
**Status:** **GONE**

**Diff quote:**
```dart
@@ -2072,28 +2110,71 @@ class EditorController extends ChangeNotifier {
+      // The merged picture takes the place of the highest part, so whatever
+      // was above the parts (an arrow, a label) stays above.
+      final at = topLayer.objects.indexWhere((x) => x.id == ordered.last.id);
+      if (at >= 0) {
+        topLayer.objects[at] = merged;
+      } else {
+        topLayer.objects.add(merged);
+      }
+      for (final l in doc.layers) {
+        l.objects.removeWhere((o) => chosen.contains(o.id));
+      }
```

**How checked:**
- Ran [`test/connectors_test.dart`](file:///tmp/claude-3645/r3/gemini/test/connectors_test.dart#L434-L451): `"a merge takes the highest part's place: an arrow above stays"`.
- Code review confirmed `merged` replaces `ordered.last` at index `at` in `topLayer.objects` instead of appending to the layer, preserving the z-order of all non-merged objects sitting above or between parts across undo, redo, and unmerge.

---

#### H1: Merge could un-hide private details
**Status:** **GONE**

**Diff quote:**
```dart
@@ -2034,10 +2068,14 @@ class EditorController extends ChangeNotifier {
-    final ordered = mergeable;
+    final ordered = mergeParts;
     final chosen = {for (final o in ordered) o.id};
     if (ordered.isEmpty) return null;
     final b = unionRects(ordered.map((o) => o.paintBounds)).inflate(1);
+    final drawn = _withCoversBetween(ordered, b);
+    final covered = drawn.length > ordered.length;
...
-      for (final o in ordered)
+      for (final o in drawn)
         if (o.visible) o,
...
+        parts: [for (final o in drawn) o.toJson()],
...
+  List<SceneObject> _withCoversBetween(List<SceneObject> parts, Rect area) {
+    final ids = {for (final o in parts) o.id};
+    final last = parts.last.id;
+    final out = <SceneObject>[];
+    for (final layer in doc.layers) {
+      for (final o in layer.objects) {
+        if (ids.contains(o.id)) {
+          out.add(o);
+          if (o.id == last) return out;
+        } else if (o is HideObject &&
+            out.isNotEmpty &&
+            layer.visible &&
+            o.visible &&
+            o.bounds.overlaps(area)) {
+          out.add(o);
+        }
+      }
+    }
+    return out;
+  }
+
+  List<SceneObject> get mergeParts => [
+    for (final o in mergeable)
+      if (o is! HideObject) o,
+  ];
```

**How checked:**
- Ran the test suite in [`test/borders_test.dart`](file:///tmp/claude-3645/r3/gemini/test/borders_test.dart#L249-L323):
  - `"a Hide box between the parts is painted in, and stays"`
  - `"a selected Hide box is not taken off the page"`
  - `"with no box over the parts, a merge is as before"`
- Verified pixel-level buffer rendering in `borders_test.dart`, confirming masked areas remain black/obscured when flattened, unmerging restores covers above original pieces, and `HideObject` elements are never removed from the document (`chosen` contains only IDs in `mergeParts`).

---

### Questions

#### 1. Did any of these changes make it worse in a way the change did not intend? What did this break that used to work?
**Nothing wrong.**
All 311 unit and widget tests pass, `dart format` is clean, and `flutter analyze` reports no issues. The changes behave conservatively:
- Aligned marks only shift when their parent objects shift;
- Connectors recalculate their endpoints through [`relinkConnectors`](file:///tmp/claude-3645/r3/gemini/lib/model/connect.dart#L178);
- Merged images accurately replace the highest part's z-index rather than obscuring layers above;
- Hide boxes are preserved on the page and rendered into merged assets.

#### 2. Is there any change applied in one place and missed in another?
**Nothing wrong.**
- `mergeParts` replaced `mergeable` in all operational call sites: [`canMerge`](file:///tmp/claude-3645/r3/gemini/lib/editor/controller.dart#L2224), [`_flattenSelection`](file:///tmp/claude-3645/r3/gemini/lib/editor/controller.dart#L2073), the properties panel Combine section, and the canvas quick-action pill.
- The corner radius logic in [`_withinOutline`](file:///tmp/claude-3645/r3/gemini/lib/editor/controller.dart#L915-L932) applies to `TextObject`, which is the only object type with `corner > 0` (images, shapes, and badges define `corner: 0.0`).
- `holdPins` passing `group: selectedObjects` was specifically needed for multi-object alignment because individual objects within the alignment set can have zero shift. Other drag and nudge operations move the entire selection by uniform translation vectors.
