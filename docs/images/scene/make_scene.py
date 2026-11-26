#!/usr/bin/env python3
"""Build the README's living-room scene from the photos beside this script.

    python3 docs/images/scene/make_scene.py OUT_DIR

The photos in photos/ were made with Codex's image generation for the README:
an empty room, and each piece of furniture on white, as a shop shows it. The
prompt is in PROMPT below. They are kept here so the screenshots can be
retaken without generating them again.

Each piece is trimmed and scaled, and cut out of its white with a flood fill
from the edges. The cut-outs are placed on the page; the white-backed copies
go in the collection, as they would arrive from a shop's website. The result
is OUT_DIR/Living room.thinkspace. See docs/DEVELOPING.md, "Refreshing the
README images".
"""

import base64
import io
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
PAGE = (1536, 1024)

PROMPT = """\
Use your image generation tool to create the images below, and save each one
as a PNG file in the current directory with exactly the file name given.
Photographic, natural daylight, realistic, no text, no logos, no watermarks,
no people.

1. room.png (landscape, about 3:2): a bright, mostly empty Scandinavian living
   room seen straight on. A plain light wall takes up most of the frame, light
   oak floor, one tall window on the left edge, a low white baseboard. Nothing
   against the wall: the middle of the room is empty so furniture can be
   placed there later.
2. velvet-sofa.png (landscape): a three-seat dark green velvet sofa with slim
   wooden legs, front view, isolated on a pure white background, soft shadow
   underneath.
3. leather-sofa.png (landscape): a three-seat cognac brown leather sofa, front
   view, isolated on a pure white background, soft shadow underneath.
4. floor-lamp.png (portrait): a tall brass arc floor lamp with a white shade,
   isolated on a pure white background.
5. fiddle-leaf-fig.png (portrait): a fiddle leaf fig tree in a white ceramic
   pot, isolated on a pure white background.
6. print.png (portrait): a framed abstract print with soft terracotta and sand
   shapes in a thin black frame, straight-on, isolated on a pure white
   background.
7. armchair.png (square): a mustard yellow boucle armchair, three-quarter
   view, isolated on a pure white background.
"""

# name: (photo, scale to, flood-fill threshold, centre on the page, layer)
# The threshold is how far from white the fill may reach: high for the sofas,
# so their grey floor shadow goes too; low for the lamp and the plant, whose
# white shade and pot would otherwise go with the background.
PIECES = {
    "Armchair": ("armchair", ("h", 420), None, None, None),
    "Floor lamp": ("floor-lamp", ("h", 640), 12, (400, 592), "Decor"),
    "Fiddle leaf fig": ("fiddle-leaf-fig", ("h", 470), 12, (1365, 680), "Decor"),
    "Print": ("print", ("h", 300), 30, (880, 385), "Decor"),
    "Velvet sofa": ("velvet-sofa", ("w", 720), 70, (880, 745), "Option A: velvet"),
    "Leather sofa": ("leather-sofa", ("w", 720), 70, (880, 752), "Option B: leather"),
}
# How many rows at the bottom of a piece hold its photo's floor shadow: pale
# grey there becomes a dark see-through shadow that sits on any floor.
SHADOW_ROWS = {"Floor lamp": 30, "Fiddle leaf fig": 30, "Velvet sofa": 90, "Leather sofa": 90}
LAYERS = ["Room", "Option B: leather", "Option A: velvet", "Decor", "Notes"]


def trim(im, pad=12):
    """Cut the white margin down to `pad` pixels."""
    bg = Image.new("RGB", im.size, (255, 255, 255))
    ink = ImageChops.difference(im, bg).convert("L").point(lambda v: 255 if v > 18 else 0)
    l, t, r, b = ink.getbbox()
    return im.crop((max(0, l - pad), max(0, t - pad), min(im.width, r + pad), min(im.height, b + pad)))


def fit(im, how):
    side, n = how
    s = n / (im.width if side == "w" else im.height)
    return im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)


def cut(im, thresh):
    """The white around the piece made transparent, with a soft edge."""
    w, h = im.size
    pad = Image.new("RGB", (w + 2, h + 2), (255, 255, 255))
    pad.paste(im, (1, 1))
    ImageDraw.floodfill(pad, (0, 0), (255, 0, 255), thresh=thresh)
    r, g, b = pad.split()
    is_fill = ImageChops.multiply(
        ImageChops.multiply(r.point(lambda v: 255 if v == 255 else 0), g.point(lambda v: 255 if v == 0 else 0)),
        b.point(lambda v: 255 if v == 255 else 0),
    )
    alpha = ImageChops.invert(is_fill)
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8)).crop((1, 1, w + 1, h + 1))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out.crop(alpha.getbbox())


def darken_shadow(im, rows, keep_sides=False):
    """Pale grey in the bottom rows, the photo's floor shadow, turned into a
    dark see-through shadow. Something white of its own, like the pot, is
    kept: its sides are followed down from the rows above the shadow, and
    within them what lies above its dark bottom rim is kept."""
    if rows <= 0:
        return im
    px = im.load()
    w, h = im.size
    top = h - rows
    inside = sides(im, top) if keep_sides else None
    rim = {}
    if inside:
        for x in range(w):
            for y in range(top, h):
                r, g, b, a = px[x, y]
                if a > 128 and lum(r, g, b) < 190 and inside(x, y):
                    rim[x] = y
        # Where the rim is too pale to see, it runs at its neighbours' height.
        found = sorted(rim)
        for x in range(w):
            if x not in rim and found:
                rim[x] = rim[min(found, key=lambda f: abs(f - x))]
    for y in range(top, h):
        for x in range(w):
            if inside and inside(x, y) and y <= rim.get(x, h):
                continue
            r, g, b, a = px[x, y]
            light = lum(r, g, b)
            # Light shadow can take a little colour from what stands on it;
            # dark shadow must be truly grey, or dark green velvet would pass.
            grey = max(r, g, b) - min(r, g, b) < (40 if light > 150 else 22 if light > 110 else 10)
            if a and grey:
                px[x, y] = (20, 16, 12, min(a, int(max(0, 255 - light) * 2.0)))
    # Soften the shadow's ragged lower edge.
    alpha = im.getchannel("A")
    soft = alpha.crop((0, top, w, h)).filter(ImageFilter.GaussianBlur(1.2))
    alpha.paste(soft, (0, top))
    im.putalpha(alpha)
    return im


def lum(r, g, b):
    return (r * 299 + g * 587 + b * 114) // 1000


def sides(im, top):
    """Where the piece's left and right edges would run below row `top`,
    carried on from their slope just above it. None if they are not clear."""
    a = im.getchannel("A")
    edges = []
    for y in range(max(0, top - 30), top):
        row = a.crop((0, y, im.width, y + 1)).getbbox()
        if row:
            edges.append((y, row[0], row[2]))
    if len(edges) < 10:
        return None
    (y0, l0, r0), (y1, l1, r1) = edges[0], edges[-1]
    dl, dr = (l1 - l0) / (y1 - y0), (r1 - r0) / (y1 - y0)
    return lambda x, y: l1 + dl * (y - y1) + 2 <= x <= r1 + dr * (y - y1) - 2


def png(im):
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "readme-scene").resolve()
    out.mkdir(parents=True, exist_ok=True)
    assets, n = {}, [0]

    def nid(prefix):
        n[0] += 1
        return f"{prefix}{n[0]}"

    def asset(im):
        aid = nid("a")
        assets[aid] = base64.b64encode(png(im)).decode()
        return aid

    layers = {name: [] for name in LAYERS}
    collection = []
    room = Image.open(HERE / "photos" / "room.jpg").convert("RGB").resize(PAGE, Image.LANCZOS)
    layers["Room"].append(image(nid("o"), "Room", (PAGE[0] / 2, PAGE[1] / 2), room.size, asset(room)))

    for name, (photo, size, thresh, at, layer) in PIECES.items():
        im = fit(trim(Image.open(HERE / "photos" / f"{photo}.jpg").convert("RGB")), size)
        collection.append({"id": nid("c"), "name": name, "asset": asset(im)})
        if at:
            piece = cut(im, thresh)
            piece = darken_shadow(piece, SHADOW_ROWS.get(name, 0), keep_sides=name == "Fiddle leaf fig")
            layers[layer].append(image(nid("o"), name, at, piece.size, asset(piece)))

    layers["Notes"] += [
        {
            "type": "text", "id": nid("o"), "name": "Question", **common(),
            "center": [1190.0, 154.0], "size": [560.0, 84.0], "rotation": 0.0, "flipX": False,
            "text": "Green velvet or leather?", "fontSize": 48.0,
            "color": 0xFF000000, "bold": False, "italic": False, "background": 0xFFFFFFFF,
            "align": 2, "autoWidth": True,
        },
        {
            "type": "line", "id": nid("o"), "name": "Pointer", **common(),
            "p1": [1190.0, 200.0], "p2": [1158.0, 600.0], "bend": [0.0, -0.18],
            "color": 0xFFE0352B, "width": 5.0, "headEnd": True, "headStart": False, "dashed": False,
        },
    ]
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
            for i, name in enumerate(LAYERS)
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
