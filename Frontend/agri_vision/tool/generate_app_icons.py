"""Generate the launcher icon for every platform from one master mark.

Run from the Flutter project root:

    python tool/generate_app_icons.py

Why a script and not a folder of hand-made PNGs: there are 45 image files
across five platforms, and the only way they stay the *same* icon after
somebody tweaks the green is if one command rebuilds all of them. Committing
the outputs is still right -- a checkout must build without Pillow -- but the
recipe is here so the next change is a one-line edit rather than an afternoon
in an image editor.

The mark
--------
The app already had an identity before it had an icon: ``LogoMark`` in
``lib/src/ui/widget/drone_logo.dart`` draws the drone on a green gradient, and
that is what the splash screen and the sign-in header show. So the launcher
icon is deliberately *that*, not a new invention -- the thing on the home
screen is the thing that greets you when you open the app.

Two deliberate departures from ``LogoMark``:

* **A bolder drone.** ``LogoMark`` uses ``drone.png``, whose thin rotor rings
  are lovely at 108 px and illegible at the 48 px Android draws a launcher icon
  at -- the rings close up into grey mush. ``drone (1).png`` is the same
  quadcopter with weight behind it and survives the small sizes. Rendering a
  glyph heavier for small use is ordinary icon practice, not a divergence.
* **No baked-in shadow.** ``LogoMark``'s drop shadow belongs on a light app
  surface. Every launcher composites its own shadow, and a second one inside
  the artwork reads as a smudge.

Android adaptive icons
----------------------
API 26+ masks the icon to whatever shape the launcher wants -- circle, squircle,
teardrop -- so the background must be full-bleed and the foreground must keep
its content inside the guaranteed-visible middle. Both layers are 108 dp and
only the central 72 dp always survives the mask, so the drone is sized against
*that* rather than the canvas: ``0.56 x 72/108``, which lands it at the same
apparent size as the legacy icon instead of looking shrunken next to it.

Getting this wrong is the most visible "unfinished app" tell there is: a
non-adaptive icon on a modern launcher gets drawn as a small square floating in
a white circle.
"""

from __future__ import annotations

import json
import os
import struct
import sys
import zlib

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - developer tooling
    sys.exit("This script needs Pillow:  pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The mark. Bolder than the in-app DroneIcon on purpose -- see the module
# docstring.
SOURCE_MARK = os.path.join(ROOT, "assets", "images", "drone (1).png")

# The app's own green, lifted from LogoMark so the icon and the splash screen
# cannot drift apart.
GRADIENT_TOP_LEFT = (0x2B, 0xBE, 0x6E)
GRADIENT_BOTTOM_RIGHT = (0x1C, 0x8C, 0x50)

# Share of the tile the drone occupies, matching LogoMark's 0.56.
MARK_SCALE = 0.56

# Corner radius as a share of the edge, for the platforms that do not mask for
# us (legacy Android, and the web's non-maskable icons).
CORNER_RADIUS = 0.26

# Android adaptive geometry, in dp. Only the middle of the canvas is safe.
ADAPTIVE_CANVAS_DP = 108
ADAPTIVE_SAFE_DP = 72

# Everything is rendered at 4x and downsampled, so the gradient has no banding
# and the mark's curves stay clean at 48 px.
SUPERSAMPLE = 4


# -- drawing ------------------------------------------------------------------

def _gradient(size: int) -> Image.Image:
    """The app's diagonal green, top-left to bottom-right."""
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    # Drawn as anti-diagonal lines: each is a constant distance along the
    # gradient axis, which is what makes it a true 45-degree ramp rather than
    # a horizontal one that merely looks tilted.
    span = size * 2 - 1
    for i in range(span + 1):
        t = i / span
        draw.line(
            [(i, 0), (0, i)],
            fill=tuple(
                round(GRADIENT_TOP_LEFT[c] + (GRADIENT_BOTTOM_RIGHT[c] - GRADIENT_TOP_LEFT[c]) * t)
                for c in range(3)
            ),
        )
    return image


def _white_mark(size: int) -> Image.Image:
    """The drone artwork recoloured white, keeping its own alpha."""
    mark = Image.open(SOURCE_MARK).convert("RGBA").resize(
        (size, size), Image.LANCZOS
    )
    white = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    white.putalpha(mark.split()[3])
    return white


def _tile(size: int, mark_scale: float, radius: float | None) -> Image.Image:
    """A finished square icon: gradient, drone, optional rounded corners.

    ``radius=None`` leaves the tile full-bleed square, which is what iOS,
    macOS and Android's adaptive background all want -- they apply their own
    mask, and corners baked into the artwork would be clipped twice.
    """
    work = size * SUPERSAMPLE
    tile = _gradient(work)

    mark_px = round(work * mark_scale)
    mark = _white_mark(mark_px)
    offset = (work - mark_px) // 2
    tile.paste(mark, (offset, offset), mark)

    tile = tile.convert("RGBA")
    if radius is not None:
        mask = Image.new("L", (work, work), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, work - 1, work - 1], radius=round(work * radius), fill=255
        )
        tile.putalpha(mask)

    return tile.resize((size, size), Image.LANCZOS)


def _foreground(size: int) -> Image.Image:
    """The Android adaptive foreground: the drone alone, on transparency.

    Sized against the 72 dp safe zone rather than the 108 dp canvas, so it
    reads at the same size as the legacy icon once the launcher's mask has
    eaten the outer ring.
    """
    work = size * SUPERSAMPLE
    layer = Image.new("RGBA", (work, work), (0, 0, 0, 0))
    mark_px = round(work * MARK_SCALE * (ADAPTIVE_SAFE_DP / ADAPTIVE_CANVAS_DP))
    mark = _white_mark(mark_px)
    offset = (work - mark_px) // 2
    layer.paste(mark, (offset, offset), mark)
    return layer.resize((size, size), Image.LANCZOS)


def _write(image: Image.Image, path: str, *, opaque: bool = False) -> None:
    """Save a PNG, flattening alpha where the platform forbids it.

    iOS and macOS reject an app icon with an alpha channel outright -- the
    build fails at submission, long after anyone remembers editing the icon.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if opaque and image.mode == "RGBA":
        flat = Image.new("RGB", image.size, GRADIENT_BOTTOM_RIGHT)
        flat.paste(image, (0, 0), image)
        image = flat
    image.save(path, "PNG", optimize=True)
    print(f"  {os.path.relpath(path, ROOT).replace(os.sep, '/')}")


# -- platforms ----------------------------------------------------------------

def android() -> None:
    """Legacy bitmaps, adaptive layers, and the XML that ties them together."""
    print("android")
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")

    # Legacy square icon, for launchers below API 26. Corners baked in,
    # because nothing is going to round them for us there.
    for bucket, px in (
        ("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)
    ):
        _write(
            _tile(px, MARK_SCALE, CORNER_RADIUS),
            os.path.join(res, f"mipmap-{bucket}", "ic_launcher.png"),
        )

    # Adaptive foreground, at 108 dp in each bucket.
    for bucket, scale in (
        ("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)
    ):
        _write(
            _foreground(round(ADAPTIVE_CANVAS_DP * scale)),
            os.path.join(res, f"mipmap-{bucket}", "ic_launcher_foreground.png"),
        )

    # The background is a gradient, so it has to be a drawable rather than the
    # single colour the template's ic_launcher_background usually is.
    _text(
        os.path.join(res, "drawable", "ic_launcher_background.xml"),
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- The app's green, matching LogoMark in drone_logo.dart. Full-bleed:\n"
        "     the launcher masks this to its own shape, so any corner rounding\n"
        "     here would be clipped a second time. -->\n"
        '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:shape="rectangle">\n'
        "    <gradient\n"
        '        android:type="linear"\n'
        '        android:angle="315"\n'
        f'        android:startColor="#{"%02X%02X%02X" % GRADIENT_TOP_LEFT}"\n'
        f'        android:endColor="#{"%02X%02X%02X" % GRADIENT_BOTTOM_RIGHT}" />\n'
        "</shape>\n",
    )

    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- API 26+ composes these two layers and masks them to whatever shape\n"
        "     the launcher uses. Without this file a modern launcher draws the\n"
        "     legacy square floating inside a white circle. -->\n"
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    _text(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), adaptive)
    # No ic_launcher_round.xml. `android:roundIcon` is an API 25 mechanism and
    # would need a round *bitmap*; on API 26+ the adaptive icon above already
    # produces a circle wherever the launcher wants one. Generating a round
    # variant nothing references is a file that only ever goes stale.


def ios() -> None:
    """Every size Contents.json asks for. No alpha: iOS rejects it."""
    print("ios")
    icon_set = os.path.join(
        ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
    )
    for filename, px in _sizes_from_contents(icon_set):
        # No rounded corners: iOS applies the superellipse mask itself, and
        # baking one in leaves a visible dark rim inside the real corner.
        _write(_tile(px, MARK_SCALE, None), os.path.join(icon_set, filename), opaque=True)


def macos() -> None:
    """macOS icons sit inset in their tile, per Apple's own grid."""
    print("macos")
    icon_set = os.path.join(
        ROOT, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset"
    )
    for filename, px in _sizes_from_contents(icon_set):
        # Rounded here, unlike iOS: macOS does *not* mask app icons, so the
        # artwork has to bring its own shape -- and keep real transparency
        # outside it. Flattening these the way iOS needs puts dark green
        # squares behind every rounded corner in the Dock.
        _write(
            _tile(px, MARK_SCALE * 0.82, CORNER_RADIUS * 0.85),
            os.path.join(icon_set, filename),
        )


def web() -> None:
    print("web")
    web_dir = os.path.join(ROOT, "web")
    _write(_tile(32, MARK_SCALE, CORNER_RADIUS), os.path.join(web_dir, "favicon.png"))
    for px in (192, 512):
        _write(
            _tile(px, MARK_SCALE, CORNER_RADIUS),
            os.path.join(web_dir, "icons", f"Icon-{px}.png"),
        )
        # Maskable icons are cropped by the installing browser, so they follow
        # the same safe-zone rule as Android's adaptive foreground.
        _write(
            _tile(px, MARK_SCALE * (ADAPTIVE_SAFE_DP / ADAPTIVE_CANVAS_DP), None),
            os.path.join(web_dir, "icons", f"Icon-maskable-{px}.png"),
        )


def windows() -> None:
    """One .ico carrying every size Windows picks between."""
    print("windows")
    path = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sizes = [16, 24, 32, 48, 64, 128, 256]
    # Built from the largest render and downsampled by Pillow per entry, so the
    # 16 px frame is a proper reduction rather than a nearest-neighbour crush.
    master = _tile(256, MARK_SCALE, CORNER_RADIUS)
    master.save(path, format="ICO", sizes=[(s, s) for s in sizes])
    print(f"  {os.path.relpath(path, ROOT).replace(os.sep, '/')}  ({len(sizes)} sizes)")


def master() -> None:
    """A 1024 px master, for the Play Store listing and anything print.

    Deliberately *not* registered in pubspec.yaml's asset list: nothing in the
    app loads it, and bundling a megabyte of icon into every APK to satisfy a
    store listing would be pure waste. It lives here to be found, not shipped.
    """
    print("master")
    _write(
        _tile(1024, MARK_SCALE, None),
        os.path.join(ROOT, "assets", "icons", "app_icon.png"),
        opaque=True,
    )


# -- helpers ------------------------------------------------------------------

def _sizes_from_contents(icon_set: str):
    """(filename, pixels) for each entry in an Xcode icon set.

    Read from Contents.json rather than hard-coded: the list differs between
    iOS and macOS and changes with Xcode versions, and a missing file is a
    build error nobody sees until they open a Mac.
    """
    with open(os.path.join(icon_set, "Contents.json"), encoding="utf-8") as handle:
        contents = json.load(handle)

    seen = {}
    for entry in contents.get("images", []):
        filename = entry.get("filename")
        if not filename:
            continue
        points = float(entry["size"].split("x")[0])
        pixels = round(points * float(entry["scale"].rstrip("x")))
        # Several entries share a file (e.g. 32x32@1x and 16x16@2x are both
        # app_icon_32.png). Keep the largest demand for each name.
        seen[filename] = max(seen.get(filename, 0), pixels)
    return sorted(seen.items())


def _text(path: str, body: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(body)
    print(f"  {os.path.relpath(path, ROOT).replace(os.sep, '/')}")


def main() -> None:
    if not os.path.isfile(SOURCE_MARK):
        sys.exit(f"Source mark not found: {SOURCE_MARK}")
    print(f"Building AgriVision icons from {os.path.basename(SOURCE_MARK)}\n")
    master()
    android()
    ios()
    macos()
    web()
    windows()
    print("\nDone. Rebuild the app to see them (icons are not hot-reloaded).")


if __name__ == "__main__":
    _ = struct, zlib  # kept: handy when debugging PNG output by hand
    main()
