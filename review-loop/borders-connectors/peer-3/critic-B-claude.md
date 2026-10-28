# Critic B, pass 3 (Claude subagent, general-purpose; fresh, did not see earlier reports)

1. MEDIUM — re-pinning after a move uses attachTargetAt, which returns text/shapes/markers too: a mark on a picture dragged so an end lands on a label or near a frame's outline silently becomes a connector (then bends on the next drag) — or, if it goes free, is left behind when the screenshot moves. Fix: re-pin looks for pictures only, passing through other objects.
2. MEDIUM — the bend handle on a connector is unspecified: _doBend writes bend over p1–p2, relink rebuilds from anchorBend, so the handle does nothing or swims. Fix: route the handle through the same fixed-t anchorBend solve as the body drag; snap-straight over the anchor chord.
3. MEDIUM (rare) — flip and unmerge don't update anchorBend: flipping a picture with a curved mark pinned at both ends mirrors the pins but leaves the bulge on the old side; unmerge maps p1/p2/mid but not anchorBend. Fix: negate anchorBend.dy on flip for lines pinned at both ends to that picture; map anchorBend in unmerge as mid is.
4. LOW — a frozen edge end (hidden target) anchors at its stored outline point, not the centre, so a curved connector changes shape while the target is hidden. Fix: keep the hidden target's centre as the anchor.
5. LOW — clamping pins to -0.5..0.5 conflicts with B11: a drop on the border band is pulled in to the picture edge. Fix: allow at up to the border's outer edge.
6. LOW — define "target is being moved" (selected and unlocked); don't put the border band into ImageObject.hitTest (imageAt is used by cut-out and remove-colour); read anchorBend defensively.
On the questions: the re-pin rule is right apart from 1 and 6. Keep anchorBend: relink then depends only on targets and stored data (idempotent); older builds drop start/end/anchorBend together; cost: every reshaping operation must update it (2, 3).
Cut: nothing important.
