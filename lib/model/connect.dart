import 'dart:math' as math;
import 'dart:ui';

import 'geometry.dart';
import 'scene.dart';

/// What a line's end may attach to: pictures, text boxes, rectangles,
/// ellipses and markers. Not pen marks, highlights, Hide boxes or lines.
bool canAttachTo(SceneObject o) =>
    o is ImageObject ||
    o is TextObject ||
    o is BadgeObject ||
    (o is ShapeObject && o.highlight == HighlightStyle.none);

/// The attachment an end dropped at [p] on [target] gets: pinned to that spot
/// of a picture, riding the outline of anything else.
Attachment attachmentFor(BoxObject target, Offset p) => target is ImageObject
    ? Attachment(target.id, pinAt(target, p))
    : Attachment(target.id);

/// Where the pin [at] of [t] is on the page.
Offset pinPoint(BoxObject t, Offset at) {
  final x = at.dx * t.size.width * (t.flipX ? -1 : 1);
  return t.toScene(Offset(x, at.dy * t.size.height));
}

/// The pin for page point [p] on [t]. It is kept on what is drawn of the
/// picture, its border included.
Offset pinAt(BoxObject t, Offset p) {
  final l = t.toLocal(p);
  final w = math.max(t.size.width, 1e-6), h = math.max(t.size.height, 1e-6);
  var u = l.dx / w;
  if (t.flipX) u = -u;
  final fw = t is Framed ? t.frameWidth : 0.0;
  final mu = 0.5 + fw / w, mv = 0.5 + fw / h;
  return Offset(u.clamp(-mu, mu), (l.dy / h).clamp(-mv, mv));
}

/// The outline an end rides, in the object's own frame: what is drawn, so an
/// arrow's tip touches the stroke or the border, not the edge inside it.
/// [corner] is the radius of a box's round corners (a text box's backdrop and
/// border are rounded).
({double hw, double hh, bool round, double corner}) outlineOf(BoxObject t) {
  final hw = t.size.width / 2, hh = t.size.height / 2;
  if (t is ShapeObject) {
    final s = t.strokeWidth / 2;
    return (hw: hw + s, hh: hh + s, round: t.ellipse, corner: 0.0);
  }
  if (t is BadgeObject) return (hw: hw, hh: hh, round: true, corner: 0.0);
  final f = t is Framed ? t.frameWidth : 0.0;
  final r = t is TextObject ? math.min(6 + f, math.min(hw + f, hh + f)) : 0.0;
  return (hw: hw + f, hh: hh + f, round: false, corner: r);
}

bool _inside(BoxObject t, Offset p) {
  final o = outlineOf(t);
  final l = t.toLocal(p);
  if (o.round) {
    final x = l.dx / o.hw, y = l.dy / o.hh;
    return x * x + y * y < 1;
  }
  final ax = l.dx.abs(), ay = l.dy.abs();
  if (ax >= o.hw || ay >= o.hh) return false;
  final r = o.corner;
  final cx = o.hw - r, cy = o.hh - r;
  if (r > 0 && ax > cx && ay > cy) {
    return (Offset(ax - cx, ay - cy)).distance < r;
  }
  return true;
}

/// Where a ray from [t]'s centre towards [aim] leaves its outline. Straight up
/// when [aim] is the centre itself.
Offset rayExit(BoxObject t, Offset aim) {
  final o = outlineOf(t);
  var v = rotateOffset(aim - t.center, -t.rotation);
  if (v.distance < 1e-9) v = const Offset(0, -1);
  final double k;
  if (o.round) {
    final x = v.dx / o.hw, y = v.dy / o.hh;
    k = 1 / math.sqrt(x * x + y * y);
  } else {
    final kx = v.dx.abs() < 1e-12 ? double.infinity : o.hw / v.dx.abs();
    final ky = v.dy.abs() < 1e-12 ? double.infinity : o.hh / v.dy.abs();
    var kk = math.min(kx, ky);
    // In a round corner, meet the corner's arc instead.
    final r = o.corner;
    final q = v * kk;
    final cx = o.hw - r, cy = o.hh - r;
    if (r > 0 && q.dx.abs() > cx && q.dy.abs() > cy) {
      final cc = Offset(cx * q.dx.sign, cy * q.dy.sign);
      // |k v - cc| = r, the far root.
      final a = v.dx * v.dx + v.dy * v.dy;
      final b = -2 * (v.dx * cc.dx + v.dy * cc.dy);
      final c = cc.dx * cc.dx + cc.dy * cc.dy - r * r;
      final disc = b * b - 4 * a * c;
      if (disc >= 0) kk = (-b + math.sqrt(disc)) / (2 * a);
    }
    k = kk;
  }
  return t.toScene(v * k);
}

Offset _quad(Offset a, Offset c, Offset b, double t) {
  final u = 1 - t;
  return a * (u * u) + c * (2 * u * t) + b * (t * t);
}

/// The control point of the piece of the quadratic (a, c, b) between [s] and
/// [e]; a piece of a quadratic is itself an exact quadratic.
Offset _subControl(Offset a, Offset c, Offset b, double s, double e) =>
    a * ((1 - s) * (1 - e)) + c * ((1 - s) * e + s * (1 - e)) + b * (s * e);

/// The parameter where the curve (a, c, b) first leaves [t], walking from the
/// start (or from the end, with [fromEnd]). Null when it never does.
double? _curveExit(BoxObject t, Offset a, Offset c, Offset b, bool fromEnd) {
  double at(double i) => fromEnd ? 1 - i : i;
  const steps = 64;
  for (int i = 1; i <= steps; i++) {
    if (!_inside(t, _quad(a, c, b, at(i / steps)))) {
      var lo = (i - 1) / steps, hi = i / steps;
      for (int k = 0; k < 40; k++) {
        final m = (lo + hi) / 2;
        if (_inside(t, _quad(a, c, b, at(m)))) {
          lo = m;
        } else {
          hi = m;
        }
      }
      return at(hi);
    }
  }
  return null;
}

/// The control point of the curve from [a] to [b] that bends by [bend]
/// (measured as in [LineObject.bend]).
Offset controlFor(Offset a, Offset b, Offset bend) {
  final d = b - a;
  final mid = (a + b) / 2 + d * bend.dx + Offset(-d.dy, d.dx) * bend.dy;
  return mid * 2 - (a + b) / 2;
}

/// The bend (as in [LineObject.bend]) of the curve from [a] to [b] with
/// control point [c].
Offset bendFor(Offset a, Offset b, Offset c) {
  final d = b - a;
  final len2 = d.dx * d.dx + d.dy * d.dy;
  if (len2 < 1e-12) return Offset.zero;
  final v = (a + b) / 4 + c / 2 - (a + b) / 2;
  return Offset(
    (v.dx * d.dx + v.dy * d.dy) / len2,
    (v.dy * d.dx - v.dx * d.dy) / len2,
  );
}

/// The two anchors of [l]: a pin's spot, the centre of the outline an end
/// rides, or a free end itself. Null for an end whose target is missing.
(Offset, Offset) anchorsOf(LineObject l, Document doc) {
  Offset anchor(Attachment? a, Offset own) {
    if (a == null) return own;
    final t = doc.objectById(a.to);
    if (t is! BoxObject) return own;
    return a.pinned ? pinPoint(t, a.at!) : t.center;
  }

  return (anchor(l.start, l.p1), anchor(l.end, l.p2));
}

/// Put every attached line end where its attachment says. It depends only on
/// the targets and the line's own notes (and the stored point of an end that
/// is free or frozen), so on data that is already in step it changes nothing,
/// however often it runs. Returns whether anything changed.
///
/// An attachment whose target is gone (deleted, cut, merged away) is dropped
/// and that end stays where it was. An end on a hidden target stays frozen
/// where it is.
bool relinkConnectors(Document doc) {
  final byId = <String, SceneObject>{};
  final hidden = <String>{};
  final lines = <LineObject>[];
  for (final layer in doc.layers) {
    for (final o in layer.objects) {
      byId[o.id] = o;
      if (!layer.visible || !o.visible) hidden.add(o.id);
      if (o is LineObject && (o.attached || o.anchorBend != null)) lines.add(o);
    }
  }
  var changed = false;
  for (final l in lines) {
    if (_relink(l, byId, hidden)) changed = true;
  }
  return changed;
}

bool _relink(LineObject l, Map<String, SceneObject> byId, Set<String> hidden) {
  var changed = false;
  BoxObject? target(Attachment? a) {
    if (a == null) return null;
    final t = byId[a.to];
    return t is BoxObject && t.id != l.id && canAttachTo(t) ? t : null;
  }

  final ts = target(l.start), te = target(l.end);
  final dropped =
      (l.start != null && ts == null) || (l.end != null && te == null);
  if (l.start != null && ts == null) {
    l.start = null;
    changed = true;
  }
  if (l.end != null && te == null) {
    l.end = null;
    changed = true;
  }
  final s = l.start, e = l.end;
  // An end that has just gone free keeps the curve exactly where it was drawn.
  if (dropped && l.connects && l.anchorBend != null) {
    final b1 = s == null
        ? l.p1
        : (s.pinned ? pinPoint(ts!, s.at!) : ts!.center);
    final b2 = e == null
        ? l.p2
        : (e.pinned ? pinPoint(te!, e.at!) : te!.center);
    l.anchorBend = refitBend(l, b1, b2) ?? l.anchorBend;
  }

  if (!l.connects) {
    // Free ends and pins: the line is a mark, its shape is its own bend.
    if (l.anchorBend != null) {
      l.anchorBend = null;
      changed = true;
    }
    final n1 = s == null || hidden.contains(s.to) ? l.p1 : pinPoint(ts!, s.at!);
    final n2 = e == null || hidden.contains(e.to) ? l.p2 : pinPoint(te!, e.at!);
    return _set(l, n1, n2, l.bend) || changed;
  }

  final a1 = s == null ? l.p1 : (s.pinned ? pinPoint(ts!, s.at!) : ts!.center);
  final a2 = e == null ? l.p2 : (e.pinned ? pinPoint(te!, e.at!) : te!.center);
  final frozen1 = s != null && hidden.contains(s.to);
  final frozen2 = e != null && hidden.contains(e.to);
  final edge1 = s != null && !s.pinned, edge2 = e != null && !e.pinned;

  // A curved line that has just started riding an outline keeps its control
  // point: its bend is re-measured over the anchors once.
  if (l.anchorBend == null && l.bend != Offset.zero) {
    l.anchorBend = bendFor(a1, a2, l.control);
    changed = true;
  }
  final ab = l.anchorBend;
  if (ab != null && ab == Offset.zero) {
    l.anchorBend = null;
    changed = true;
  }

  if (l.anchorBend != null) {
    final c = controlFor(a1, a2, l.anchorBend!);
    final t1 = edge1 ? _curveExit(ts!, a1, c, a2, false) : 0.0;
    final t2 = edge2 ? _curveExit(te!, a1, c, a2, true) : 1.0;
    if (t1 != null && t2 != null && t1 < t2) {
      final q1 = _quad(a1, c, a2, t1), q2 = _quad(a1, c, a2, t2);
      final n1 = frozen1 ? l.p1 : q1;
      final n2 = frozen2 ? l.p2 : q2;
      final sub = _subControl(a1, c, a2, t1, t2);
      return _set(l, n1, n2, bendFor(n1, n2, sub)) || changed;
    }
    // The curve never leaves an outline (the two overlap): draw it straight.
  }

  Offset edgeEnd(BoxObject t, Offset aim, bool head) {
    final p = rayExit(t, aim);
    if (head) return p;
    // A plain end's round cap would overlap the outline by half the width.
    final d = aim - p;
    final len = d.distance;
    return len < 1e-9 ? p : p + d / len * math.min(l.width / 2, len);
  }

  final n1 = s == null || frozen1
      ? l.p1
      : edge1
      ? edgeEnd(ts!, a2, l.headStart)
      : a1;
  final n2 = e == null || frozen2
      ? l.p2
      : edge2
      ? edgeEnd(te!, a1, l.headEnd)
      : a2;
  return _set(l, n1, n2, Offset.zero) || changed;
}

/// The bend over anchors [a1] and [a2] of the curve [l] draws now, extended
/// to reach them; a quadratic's piece and its whole are one curve. Null when
/// the anchors are not on it.
Offset? refitBend(LineObject l, Offset a1, Offset a2) {
  final p1 = l.p1, p2 = l.p2, c = l.control;
  double? reach(Offset a, bool before) {
    final own = before ? p1 : p2;
    if ((a - own).distance < 1e-9) return before ? 0 : 1;
    var best = before ? 0.0 : 1.0;
    var bestD = double.infinity;
    for (int i = 0; i <= 4000; i++) {
      final s = before ? -i / 200 : 1 + i / 200;
      final d = (_quad(p1, c, p2, s) - a).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    var lo = best - 1 / 200, hi = best + 1 / 200;
    for (int k = 0; k < 60; k++) {
      final m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3;
      if ((_quad(p1, c, p2, m1) - a).distanceSquared <
          (_quad(p1, c, p2, m2) - a).distanceSquared) {
        hi = m2;
      } else {
        lo = m1;
      }
    }
    final s = (lo + hi) / 2;
    return (_quad(p1, c, p2, s) - a).distance < 0.5 ? s : null;
  }

  final s = reach(a1, true), e = reach(a2, false);
  if (s == null || e == null) return null;
  return bendFor(a1, a2, _subControl(p1, c, p2, s, e));
}

bool _set(LineObject l, Offset p1, Offset p2, Offset bend) {
  if (l.p1 == p1 && l.p2 == p2 && l.bend == bend) return false;
  l.p1 = p1;
  l.p2 = p2;
  l.bend = bend;
  return true;
}

/// After copying a batch, point each copied line's attachments at the copies
/// of their targets ([ids] maps old ids to new). An attachment to something
/// left out of the batch is dropped: that end becomes a free one.
void remapAttachments(Iterable<SceneObject> copies, Map<String, String> ids) {
  final byId = {for (final o in copies) o.id: o};
  Attachment? remap(Attachment? a) {
    if (a == null) return null;
    final to = ids[a.to];
    return to == null ? null : Attachment(to, a.at);
  }

  Offset anchor(Attachment? a, Offset own) {
    final t = a == null ? null : byId[a.to];
    if (t is! BoxObject) return own;
    return a!.pinned ? pinPoint(t, a.at!) : t.center;
  }

  for (final o in copies) {
    if (o is LineObject) {
      final s = remap(o.start), e = remap(o.end);
      final dropped =
          (o.start != null && s == null) || (o.end != null && e == null);
      o.start = s;
      o.end = e;
      if (!o.connects) {
        o.anchorBend = null;
      } else if (dropped && o.anchorBend != null) {
        // The copy keeps the curve it was drawn with.
        o.anchorBend =
            refitBend(o, anchor(s, o.p1), anchor(e, o.p2)) ?? o.anchorBend;
      }
    }
  }
}
