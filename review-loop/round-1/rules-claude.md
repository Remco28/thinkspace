# Rules reader, round 1 (Claude subagent; drove the real app through the inspector and wrote scratch tests)

Summary: every rule PASS except C6/C16 (F1). Old files: 0 of 3,840,000 bytes of export differ; the document saves back identical. New file (border + curved connector) opens in the old build (3a80cad unpacked) with the line where the new build drew it.

F1 — MEDIUM (C6/C16): dragging the body of an ALREADY-SELECTED connector that sits over a picture moves it instead of bending it. The tip moves and re-pins to another spot of the screenshot (0.22,0.02 → 0.28,−0.51). Between two text boxes the same drag does nothing (both ends snap back). Unselected, or nothing beneath: bends correctly. Cause: _downSelect (interactor.dart ~326) — a press on the selected top object with something beneath sets _clickOnSelectedTop, and the bend branch is skipped. Visible and undoable, but Frank's arrows nearly always sit over a screenshot.
F2 — LOW (C8, C9 one target copied, C10): a curved connector changes shape when one target goes away (tail slides ~2 px, middle ~8–16 px): the curve was measured from the deleted box's centre; relink then measures it from the line's own end. Straight connectors and pins: 0 px.
F3 — LOW (B5): no Border row when the selection mixes pictures/text with anything else (three screenshots + one arrow).
F4 — LOW (C2): a text box's border/backdrop has round corners, ends ride a square outline: an arrow aimed at a corner stops 4–8 px short.
F5 — LOW (B8 nit): borderWidth is written whenever it isn't 4, even with no border.
Clean: export and copy match the canvas; undo/redo stay in step; merge and its undo restore attachments; new files open in the old build.
Scratch: /tmp/claude-3645/r1/claude/test/zz_probe_test.dart, zz_probe3_test.dart; /tmp/claude-3645/r1/probe/.
