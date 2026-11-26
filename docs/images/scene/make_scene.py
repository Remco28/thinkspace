#!/usr/bin/env python3
"""Draw the README's living-room scene and write it as a .thinkspace project.

    python3 docs/images/scene/make_scene.py OUT_DIR

Every image is drawn here as SVG and turned into a PNG by headless Chrome, so
the screenshots can be retaken at any time without outside assets. OUT_DIR
gets the SVGs, the PNGs (a white-backed copy of each piece for the
collection, and a cut-out copy for the page) and living-room.thinkspace.
See docs/DEVELOPING.md, "Refreshing the README images".
"""

import base64
import json
import random
import shutil
import subprocess
import sys
from pathlib import Path

PAGE = (1536, 1024)

# --- drawing -----------------------------------------------------------------


def svg(w, h, body, defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}"><defs>{defs}</defs>{body}</svg>'
    )


def grad(id, stops, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<linearGradient id="{id}" x1="0" y1="0" x2="{x2}" y2="{y2}">{s}</linearGradient>'


BLUR = '<filter id="blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="9"/></filter>'


def room():
    w, h = PAGE
    floor_y = 790
    defs = (
        grad("wall", [(0, "#f3eee7"), (1, "#e6ddd1")])
        + '<radialGradient id="light" cx="0.12" cy="0.35" r="0.7">'
        '<stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/>'
        '<stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>'
        + grad("glass", [(0, "#d8e6ee"), (0.6, "#edf2f2"), (1, "#f6f5ef")])
        + grad("floor", [(0, "#c9a27b"), (1, "#a97f57")])
        + grad("spill", [(0, "#fff8ea"), (1, "#fff8ea")])
        + BLUR
    )
    b = [
        f'<rect width="{w}" height="{floor_y}" fill="url(#wall)"/>',
        f'<rect width="{w}" height="{floor_y}" fill="url(#light)"/>',
        # The window: frame, glass, bars and sill.
        '<rect x="70" y="90" width="270" height="560" rx="4" fill="#fbfaf7"/>',
        '<rect x="86" y="106" width="238" height="528" fill="url(#glass)"/>',
        '<rect x="200" y="106" width="10" height="528" fill="#fbfaf7"/>',
        '<rect x="86" y="276" width="238" height="9" fill="#fbfaf7"/>',
        '<rect x="86" y="456" width="238" height="9" fill="#fbfaf7"/>',
        '<rect x="56" y="648" width="298" height="18" rx="3" fill="#fdfcf9"/>',
        '<rect x="56" y="664" width="298" height="6" fill="#d9d1c4"/>',
        '<rect x="70" y="90" width="270" height="560" fill="none" stroke="#e2dbd0" stroke-width="2"/>',
        # Skirting board.
        f'<rect y="{floor_y - 22}" width="{w}" height="22" fill="#f8f5f0"/>',
        f'<rect y="{floor_y - 23}" width="{w}" height="2" fill="#ddd4c7"/>',
        f'<rect y="{floor_y}" width="{w}" height="{h - floor_y}" fill="url(#floor)"/>',
    ]
    # Floorboards: rows that widen towards the viewer, with staggered joins.
    rnd = random.Random(4)
    y, gap = floor_y, 16.0
    while y < h:
        b.append(f'<rect y="{y:.1f}" width="{w}" height="1.4" fill="#7a5638" opacity="0.18"/>')
        x = rnd.uniform(0, 300)
        while x < w:
            b.append(
                f'<rect x="{x:.0f}" y="{y:.1f}" width="1.4" height="{gap:.1f}" fill="#7a5638" opacity="0.14"/>'
            )
            x += rnd.uniform(380, 620)
        y += gap
        gap *= 1.16
    # Sunlight from the window on the floor.
    b.append(
        f'<polygon points="90,{floor_y} 340,{floor_y} 640,{h} 160,{h}" fill="#fff6e4" opacity="0.22"/>'
    )
    # A rug under the sofa.
    b.append('<path d="M470,872 L1290,872 L1350,1000 L410,1000 Z" fill="#e9e2d6"/>')
    b.append('<path d="M492,884 L1268,884 L1320,988 L440,988 Z" fill="none" stroke="#c9bba6" stroke-width="3"/>')
    # Soft contact shadows where the furniture stands.
    for cx, cy, rx, ry in [(880, 962, 380, 16), (1392, 966, 92, 12), (500, 958, 70, 10)]:
        b.append(
            f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#3b2a1c" opacity="0.38" filter="url(#blur)"/>'
        )
    return svg(w, h, "".join(b), defs)


def velvet_sofa():
    w, h = 760, 330
    defs = (
        grad("back", [(0, "#41795f"), (1, "#2c5a46")])
        + grad("cush", [(0, "#4a8468"), (0.7, "#356a52"), (1, "#2a5442")])
        + grad("seat", [(0, "#4b8669"), (0.45, "#3a7058"), (1, "#28503f")])
        + grad("arm", [(0, "#3f7660"), (1, "#26503f")], x2=1, y2=0)
        + grad("leg", [(0, "#6b4529"), (1, "#4a2e1b")])
    )
    b = []
    for x in (64, 682):  # tapered walnut legs
        b.append(f'<polygon points="{x},286 {x + 16},286 {x + 12},326 {x + 4},326" fill="url(#leg)"/>')
    b += [
        '<rect x="30" y="226" width="700" height="66" rx="16" fill="#23463a"/>',
        '<rect x="56" y="18" width="648" height="170" rx="44" fill="url(#back)"/>',
        '<rect x="100" y="150" width="560" height="100" fill="#264c3c"/>',
    ]
    for x in (74, 280, 486):
        b.append(f'<rect x="{x}" y="34" width="200" height="150" rx="36" fill="url(#cush)"/>')
        b.append(f'<path d="M{x + 30},46 q70,-10 140,0" stroke="#ffffff" stroke-opacity="0.13" stroke-width="5" fill="none" stroke-linecap="round"/>')
    for x in (108, 290, 472):
        b.append(f'<rect x="{x}" y="166" width="180" height="84" rx="24" fill="url(#seat)"/>')
        b.append(f'<rect x="{x + 6}" y="226" width="168" height="22" rx="10" fill="#244a3a" opacity="0.55"/>')
    for x in (18, 646):
        b.append(f'<rect x="{x}" y="96" width="96" height="196" rx="44" fill="url(#arm)"/>')
        b.append(f'<path d="M{x + 22},112 q26,-10 52,0" stroke="#ffffff" stroke-opacity="0.14" stroke-width="5" fill="none" stroke-linecap="round"/>')
    return svg(w, h, "".join(b), defs)


def leather_sofa():
    w, h = 760, 290
    defs = (
        grad("lback", [(0, "#c27447"), (1, "#9a4f2b")])
        + grad("lseat", [(0, "#c97c4e"), (0.5, "#b0643a"), (1, "#8c4626")])
        + grad("larm", [(0, "#b8693d"), (1, "#8a4525")], x2=1, y2=0)
    )
    b = []
    for x in (54, 696):  # slim black metal legs
        b.append(f'<rect x="{x}" y="250" width="9" height="38" rx="2" fill="#2a2522"/>')
    b += [
        '<rect x="34" y="214" width="692" height="40" rx="8" fill="#7d3e22"/>',
        '<rect x="50" y="30" width="660" height="150" rx="18" fill="url(#lback)"/>',
    ]
    for r, y in enumerate((70, 128)):  # buttoned back
        for i in range(8):
            x = 110 + i * 77 + (38 if r else 0)
            if x < 690:
                b.append(f'<circle cx="{x}" cy="{y}" r="4.5" fill="#6e3419"/>')
                b.append(f'<path d="M{x - 26},{y + 12} q26,-12 52,0" stroke="#6e3419" stroke-opacity="0.35" stroke-width="2" fill="none"/>')
    b += [
        '<rect x="80" y="160" width="600" height="70" rx="14" fill="url(#lseat)"/>',
        '<path d="M110,170 h540" stroke="#ffffff" stroke-opacity="0.18" stroke-width="4" stroke-linecap="round"/>',
        '<rect x="80" y="206" width="600" height="22" rx="10" fill="#7a3a1f" opacity="0.5"/>',
    ]
    for x in (26, 666):
        b.append(f'<rect x="{x}" y="100" width="68" height="152" rx="12" fill="url(#larm)"/>')
        b.append(f'<path d="M{x + 14},110 h40" stroke="#ffffff" stroke-opacity="0.2" stroke-width="4" stroke-linecap="round"/>')
    return svg(w, h, "".join(b), defs)


def armchair():
    w, h = 330, 330
    defs = (
        grad("shell", [(0, "#e8b53a"), (1, "#c88e18")])
        + grad("aseat", [(0, "#efc04c"), (1, "#cf961d")])
        + grad("aleg", [(0, "#9b6a3e"), (1, "#6e4626")])
        + '<pattern id="boucle" width="9" height="9" patternUnits="userSpaceOnUse">'
        '<circle cx="2" cy="3" r="1.6" fill="#ffffff" opacity="0.16"/>'
        '<circle cx="6.5" cy="7" r="1.4" fill="#7a5200" opacity="0.12"/></pattern>'
    )
    b = [
        '<polygon points="70,262 84,262 60,326 50,326" fill="url(#aleg)"/>',
        '<polygon points="246,262 260,262 280,326 270,326" fill="url(#aleg)"/>',
        '<polygon points="150,262 162,262 160,312 152,312" fill="#5e3b20"/>',
    ]
    shell = "M40,150 C30,60 90,18 165,18 C240,18 300,60 290,150 L284,250 Q282,272 260,272 L70,272 Q48,272 46,250 Z"
    b += [
        f'<path d="{shell}" fill="url(#shell)"/>',
        f'<path d="{shell}" fill="url(#boucle)"/>',
        '<path d="M86,186 Q86,160 112,160 L218,160 Q244,160 244,186 L244,228 Q244,246 226,246 L104,246 Q86,246 86,228 Z" fill="url(#aseat)"/>',
        '<path d="M86,186 Q86,160 112,160 L218,160 Q244,160 244,186 L244,228 Q244,246 226,246 L104,246 Q86,246 86,228 Z" fill="url(#boucle)"/>',
        '<path d="M100,46 Q165,26 230,46" stroke="#ffffff" stroke-opacity="0.22" stroke-width="6" fill="none" stroke-linecap="round"/>',
        '<path d="M46,250 Q48,272 70,272 L260,272 Q282,272 284,250" stroke="#a87410" stroke-opacity="0.5" stroke-width="4" fill="none"/>',
    ]
    return svg(w, h, "".join(b), defs)


def floor_lamp():
    w, h = 380, 700
    defs = (
        grad("brass", [(0, "#d9b56a"), (0.5, "#b88c3c"), (1, "#8f6a26")], x2=1, y2=0)
        + grad("shade", [(0, "#fbfaf6"), (1, "#e9e4da")], x2=1, y2=0)
        + grad("marble", [(0, "#f2f0ec"), (1, "#cfcac2")])
    )
    b = [
        # The arc, from the base up and over to the shade.
        '<path d="M300,668 L300,330 C300,120 230,60 150,70 C118,74 106,92 102,118" '
        'stroke="url(#brass)" stroke-width="9" fill="none" stroke-linecap="round"/>',
        '<path d="M300,668 L300,330 C300,120 230,60 150,70" stroke="#f3dca0" stroke-opacity="0.5" '
        'stroke-width="2" fill="none" transform="translate(-2,0)"/>',
        '<rect x="96" y="112" width="12" height="18" rx="3" fill="#9c7630"/>',
        # The shade, and its light underneath.
        '<path d="M58,128 L146,128 L176,250 L28,250 Z" fill="url(#shade)"/>',
        '<ellipse cx="102" cy="250" rx="74" ry="9" fill="#fff4d6"/>',
        '<ellipse cx="102" cy="250" rx="74" ry="9" fill="none" stroke="#ddd6c8" stroke-width="2"/>',
        '<path d="M58,128 L146,128" stroke="#ddd6c8" stroke-width="3"/>',
        # The marble base.
        '<ellipse cx="300" cy="676" rx="64" ry="14" fill="#a39d94"/>',
        '<ellipse cx="300" cy="670" rx="64" ry="14" fill="url(#marble)"/>',
        '<rect x="292" y="640" width="16" height="30" rx="4" fill="url(#brass)"/>',
    ]
    return svg(w, h, "".join(b), defs)


def leaf(x, y, angle, size, color):
    """A fiddle-leaf fig leaf: broad at the tip, pinched near the stem."""
    s = size
    d = (
        f"M0,0 C{0.28 * s},{-0.1 * s} {0.34 * s},{-0.42 * s} {0.22 * s},{-0.6 * s} "
        f"C{0.36 * s},{-0.78 * s} {0.3 * s},{-1.02 * s} 0,{-1.05 * s} "
        f"C{-0.3 * s},{-1.02 * s} {-0.36 * s},{-0.78 * s} {-0.22 * s},{-0.6 * s} "
        f"C{-0.34 * s},{-0.42 * s} {-0.28 * s},{-0.1 * s} 0,0 Z"
    )
    rib = f"M0,0 L0,{-0.95 * s}"
    return (
        f'<g transform="translate({x:.1f},{y:.1f}) rotate({angle:.1f})">'
        f'<path d="{d}" fill="{color}"/>'
        f'<path d="{rib}" stroke="#a9cf8a" stroke-opacity="0.55" stroke-width="2" fill="none"/></g>'
    )


def plant():
    w, h = 300, 560
    defs = grad("pot", [(0, "#ffffff"), (0.55, "#f1efea"), (1, "#d6d2ca")], x2=1, y2=0)
    b = [
        '<path d="M150,440 C146,380 156,320 148,250 C142,200 152,160 150,120" stroke="#6b4a2f" stroke-width="9" fill="none" stroke-linecap="round"/>',
        '<path d="M149,300 C170,280 186,262 196,236" stroke="#6b4a2f" stroke-width="6" fill="none" stroke-linecap="round"/>',
        '<path d="M150,340 C130,320 112,300 104,276" stroke="#6b4a2f" stroke-width="6" fill="none" stroke-linecap="round"/>',
    ]
    rnd = random.Random(7)
    greens = ["#2f6a32", "#3c7d3b", "#4b8f45", "#2a5e2d", "#57994d"]
    spots = [
        (150, 128, 0, 118), (150, 150, -38, 108), (152, 150, 40, 110),
        (148, 196, -72, 104), (152, 200, 70, 106), (196, 238, 30, 100),
        (196, 240, 78, 92), (104, 278, -30, 98), (104, 280, -82, 92),
        (150, 250, -20, 96), (150, 256, 24, 98), (148, 320, -96, 88),
        (152, 330, 100, 90), (150, 372, -64, 80), (150, 380, 62, 82),
        (150, 176, -8, 100),
    ]
    for x, y, a, s in spots:
        b.append(leaf(x, y, a + rnd.uniform(-6, 6), s, rnd.choice(greens)))
    b += [
        '<path d="M88,436 L212,436 L200,540 Q198,552 186,552 L114,552 Q102,552 100,540 Z" fill="url(#pot)"/>',
        '<ellipse cx="150" cy="437" rx="62" ry="8" fill="#5a4636"/>',
        '<path d="M88,436 L212,436" stroke="#ffffff" stroke-width="4" stroke-linecap="round"/>',
    ]
    return svg(w, h, "".join(b), defs)


def print_art():
    w, h = 230, 300
    b = [
        '<rect width="230" height="300" fill="#26221f"/>',
        '<rect x="8" y="8" width="214" height="284" fill="#fbf9f5"/>',
        '<rect x="34" y="34" width="162" height="232" fill="#efe2cf"/>',
        '<path d="M34,170 C80,140 110,200 196,150 L196,266 L34,266 Z" fill="#c8693c"/>',
        '<path d="M34,120 C70,90 120,110 150,60 C165,40 185,40 196,46 L196,34 L34,34 Z" fill="#dcb789"/>',
        '<circle cx="80" cy="96" r="16" fill="#3c3b36"/>',
        '<path d="M120,266 C130,230 160,214 196,212 L196,266 Z" fill="#8e3f22" opacity="0.6"/>',
    ]
    return svg(w, h, "".join(b))


PIECES = {
    # name: (drawing, size, where it goes on the page (centre), layer)
    "Armchair": (armchair, (330, 330), None, None),
    "Floor lamp": (floor_lamp, (380, 700), (390, 610), "Decor"),
    "Fiddle leaf fig": (plant, (300, 560), (1392, 690), "Decor"),
    "Print": (print_art, (230, 300), (880, 400), "Decor"),
    "Velvet sofa": (velvet_sofa, (760, 330), (880, 800), "Option A: velvet"),
    "Leather sofa": (leather_sofa, (760, 290), (880, 820), "Option B: leather"),
}

# --- rendering ---------------------------------------------------------------


def chrome():
    for name in ("google-chrome", "chromium", "chromium-browser"):
        if shutil.which(name):
            return name
    sys.exit("needs Chrome or Chromium to turn the SVGs into PNGs")


def render(src, out, size, white):
    subprocess.run(
        [
            chrome(), "--headless", "--disable-gpu", "--hide-scrollbars",
            f"--window-size={size[0]},{size[1]}",
            f"--default-background-color={'ffffffff' if white else '00000000'}",
            f"--screenshot={out}", src.as_uri(),
        ],
        check=True, capture_output=True,
    )


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "readme-scene").resolve()
    out.mkdir(parents=True, exist_ok=True)
    assets, n = {}, [0]

    def asset(png):
        n[0] += 1
        aid = f"a{n[0]}"
        assets[aid] = base64.b64encode(png.read_bytes()).decode()
        return aid

    def nid(prefix):
        n[0] += 1
        return f"{prefix}{n[0]}"

    (out / "room.svg").write_text(room())
    render(out / "room.svg", out / "room.png", PAGE, white=True)

    layers = {name: [] for name in ["Room", "Option B: leather", "Option A: velvet", "Decor", "Notes"]}
    collection = []
    for name, (draw, size, at, layer) in PIECES.items():
        slug = name.lower().replace(" ", "-")
        (out / f"{slug}.svg").write_text(draw())
        render(out / f"{slug}.svg", out / f"{slug}.png", size, white=True)
        render(out / f"{slug}.svg", out / f"{slug}-cut.png", size, white=False)
        collection.append({"id": nid("c"), "name": name, "asset": asset(out / f"{slug}.png")})
        if at:
            layers[layer].append(image(nid("o"), name, at, size, asset(out / f"{slug}-cut.png")))

    layers["Room"].append(image(nid("o"), "Room", (PAGE[0] / 2, PAGE[1] / 2), PAGE, asset(out / "room.png")))
    layers["Notes"] += [
        {
            "type": "text", "id": nid("o"), "name": "Question", **common(),
            "center": [1190.0, 160.0], "size": [520.0, 90.0], "rotation": -0.03, "flipX": False,
            "text": "Green velvet or leather?", "fontSize": 54.0, "font": "hand",
            "color": 0xFF2B2B2B, "bold": False, "italic": False, "background": 0, "align": 2,
            "autoWidth": True,
        },
        {
            "type": "line", "id": nid("o"), "name": "Pointer", **common(),
            "p1": [1250.0, 214.0], "p2": [1150.0, 650.0], "bend": [0.0, -0.16],
            "color": 0xFFD8432E, "width": 6.0, "headEnd": True, "headStart": False, "dashed": False,
        },
    ]
    order = ["Room", "Option B: leather", "Option A: velvet", "Decor", "Notes"]
    doc = {
        "canvas": [float(PAGE[0]), float(PAGE[1])],
        "background": 0xFFFFFFFF,
        "gridSize": 40.0,
        "nextId": n[0] + 1,
        "layers": [
            {
                "id": f"l{i + 1}", "name": name,
                # The leather option starts hidden, so the eye can show it.
                "visible": name != "Option B: leather", "locked": False,
                "objects": layers[name],
            }
            for i, name in enumerate(order)
        ],
        "collection": collection,
    }
    project = out / "Living room.thinkspace"
    project.write_text(json.dumps({"format": "thinkspace", "version": 1, "document": doc, "assets": assets}))
    print(project)


def common():
    return {"opacity": 1.0, "visible": True, "locked": False}


def image(id, name, at, size, aid):
    return {
        "type": "image", "id": id, "name": name, **common(),
        "center": [float(at[0]), float(at[1])], "size": [float(size[0]), float(size[1])],
        "rotation": 0.0, "flipX": False, "asset": aid,
    }


if __name__ == "__main__":
    main()
