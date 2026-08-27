#!/usr/bin/env python
"""Build the leaf-disease training set from the public datasets.

Downloads (if needed), extracts, and merges two public sources into one
torchvision ``ImageFolder`` tree that ``tools/train_leaf_disease.py`` reads:

    python tools/build_leaf_dataset.py
    -> datasets/leaf_disease/tomato___late_blight/...
       datasets/leaf_disease/apple___scab/...
       ...

Why two sources
---------------
**PlantVillage** (Mendeley, CC0) is 55k images across 39 classes and gives the
class coverage, but every photo is a detached leaf on a uniform grey sheet. A
model trained on it alone learns "leaf on grey" as part of every class and does
badly on a phone photo of a plant in the ground — the effect ``docs/
CROP_CNN_TRAINING.md`` §6 warns about.

**PlantDoc** (GitHub, CC-BY-4.0) is only ~2.6k images but they are real field
photos: cluttered backgrounds, hands in frame, mixed lighting. It is small, so
it cannot carry the model on its own; mixed in, it is what stops the model
from depending on the grey sheet.

Label space
-----------
Both datasets name their classes differently — ``Tomato___Late_blight`` versus
``Tomato leaf late blight`` — so both are normalised to a shared
``<crop>___<condition>`` id. The mapping is rule-based (crop token + condition
synonyms) rather than a hardcoded table, and **anything it cannot place is
reported and skipped, never guessed into the nearest class**. Run with
``--report-only`` to see that mapping before writing 60k files to disk.

Fetching
--------
Both downloads are built to survive a link that resets. PlantVillage is one
868 MB file pulled as 12 parallel byte ranges (and verified against its
published SHA-256); PlantDoc is fetched file-by-file, because neither its
codeload zip nor a git clone can resume. Re-run after an interruption and only
the missing bytes are refetched. See ``docs/LEAF_DISEASE_MODEL.md`` §2.
"""

from __future__ import annotations

import argparse
import os
import random
import re
import shutil
import sys
import time
import zipfile
from collections import Counter, defaultdict

# ── Sources ───────────────────────────────────────────────────────────────────
# Both are direct, auth-free downloads. The PlantVillage file id is the
# "without augmentation" variant — the augmented one is the same photos with
# flips/rotations baked in, which the trainer does better at runtime.
SOURCES = {
    "plantvillage": {
        "url": (
            "https://data.mendeley.com/public-files/datasets/tywbtsjrjv/files/"
            "d5652a28-c1d8-4b76-97f3-72fb80f94efc/file_downloaded"
        ),
        "zip": "plantvillage.zip",
        "bytes": 868032562,
        "sha256": "ac3432453984d02a86197987e775a5429d0d59e7cc7c35bcf5a8f50349b90ff0",
        "licence": "CC0 1.0 (Mendeley Data, doi:10.17632/tywbtsjrjv.1)",
    },
    # PlantDoc comes file-by-file rather than as an archive, deliberately.
    # Its codeload zip is generated on the fly, so GitHub serves no
    # Content-Length and honours no byte ranges — a reset means starting over.
    # `git clone` is no better: the pack is one stream, and a disconnect at
    # 660 MB (which is what happens on a flaky link) discards all of it. 2,579
    # separate ~370 KB files retry individually and cost nothing to resume.
    "plantdoc": {
        "mode": "github_files",
        "repo": "pratikkayal/PlantDoc-Dataset",
        "ref": "master",
        "bytes": 997000000,  # approximate, for the size line only
        "licence": "CC-BY-4.0 (github.com/pratikkayal/PlantDoc-Dataset)",
    },
}

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp"}

# ── Label normalisation ───────────────────────────────────────────────────────
# Crops we accept. The value is the canonical crop token; the keys are every
# spelling the two datasets use for it (PlantDoc writes "Soyabean", and
# "Bell_pepper" / "Pepper,_bell" are the same plant).
CROP_ALIASES = {
    "apple": "apple",
    "blueberry": "blueberry",
    "cherry": "cherry",
    "corn": "corn",
    "maize": "corn",
    "grape": "grape",
    "orange": "orange",
    "peach": "peach",
    "pepper": "pepper",
    "bell_pepper": "pepper",
    "bellpepper": "pepper",
    "potato": "potato",
    "raspberry": "raspberry",
    "soybean": "soybean",
    "soyabean": "soybean",
    "squash": "squash",
    "strawberry": "strawberry",
    "tomato": "tomato",
}

# Condition synonyms, longest-match-first when scanning a normalised folder
# name. Order matters: "late_blight" must be tried before "blight", and
# "gray_leaf_spot" before "leaf_spot", or the specific class is swallowed by
# the general one.
CONDITION_PATTERNS = [
    ("cercospora_leaf_spot_gray_leaf_spot", "gray_leaf_spot"),
    ("gray_leaf_spot", "gray_leaf_spot"),
    ("grey_leaf_spot", "gray_leaf_spot"),
    ("septoria_leaf_spot", "septoria_leaf_spot"),
    ("septoria", "septoria_leaf_spot"),
    ("cedar_apple_rust", "cedar_rust"),
    ("common_rust", "common_rust"),
    ("rust_leaf", "common_rust"),
    ("northern_leaf_blight", "northern_leaf_blight"),
    ("leaf_blight_isariopsis_leaf_spot", "leaf_blight"),
    ("early_blight", "early_blight"),
    ("late_blight", "late_blight"),
    ("bacterial_spot", "bacterial_spot"),
    ("leaf_spot", "leaf_spot"),
    ("black_rot", "black_rot"),
    ("esca_black_measles", "esca"),
    ("black_measles", "esca"),
    ("esca", "esca"),
    ("powdery_mildew", "powdery_mildew"),
    ("haunglongbing_citrus_greening", "citrus_greening"),
    ("citrus_greening", "citrus_greening"),
    ("huanglongbing", "citrus_greening"),
    ("leaf_mold", "leaf_mold"),
    ("mold_leaf", "leaf_mold"),
    ("leaf_scorch", "leaf_scorch"),
    ("target_spot", "target_spot"),
    ("yellow_leaf_curl_virus", "yellow_leaf_curl_virus"),
    ("yellow_virus", "yellow_leaf_curl_virus"),
    ("mosaic_virus", "mosaic_virus"),
    ("two_spotted_spider_mite", "spider_mites"),
    ("two_spotted_spider_mites", "spider_mites"),
    ("spider_mites", "spider_mites"),
    ("scab", "scab"),
    ("leaf_blight", "leaf_blight"),
    ("blight", "leaf_blight"),
    ("rust", "common_rust"),
    ("healthy", "healthy"),
]

# Same disease, different name in each dataset — merged once the crop is known.
#
# This matters more than it looks. PlantDoc calls it "Apple rust leaf" and
# PlantVillage calls it "Cedar_apple_rust"; they are the same pathogen. Left
# unmerged they become two classes whose only real difference is *which dataset
# the photo came from* — which is to say, whether the background is a grey sheet
# or a real field. The model would happily learn that split, which is precisely
# the background-shortcut that mixing in PlantDoc was meant to prevent.
CROP_SCOPED_MERGES = {
    ("apple", "common_rust"): "cedar_rust",
    ("pepper", "leaf_spot"): "bacterial_spot",
    ("corn", "leaf_blight"): "northern_leaf_blight",
}

# PlantVillage ships a class of photos with no leaf in them at all. It is worth
# keeping: it is what lets the model answer "that is not a leaf" instead of
# confidently calling a photo of the ground 'late blight'.
BACKGROUND_LABEL = "not_a_leaf"
BACKGROUND_PATTERNS = ("background_without_leaves", "background")


def normalise(text: str) -> str:
    """Lowercase, underscore-separated form of a dataset's folder name."""
    lowered = str(text or "").strip().lower()
    lowered = re.sub(r"[^a-z0-9]+", "_", lowered)
    return re.sub(r"_+", "_", lowered).strip("_")


def canonical_label(folder_name: str) -> str | None:
    """Map one source folder name onto ``<crop>___<condition>``.

    Returns ``None`` when the folder cannot be placed confidently — the caller
    reports those rather than filing them under a best guess.
    """
    key = normalise(folder_name)
    if not key:
        return None

    if any(pattern in key for pattern in BACKGROUND_PATTERNS):
        return BACKGROUND_LABEL

    # PlantVillage separates crop from condition with "___"; PlantDoc does not,
    # so the crop is found by token scan in both cases.
    crop = None
    if "bell_pepper" in key or "pepper_bell" in key:
        crop = "pepper"
    else:
        for token in key.split("_"):
            if token in CROP_ALIASES:
                crop = CROP_ALIASES[token]
                break
    if crop is None:
        return None

    condition = None
    for pattern, canonical in CONDITION_PATTERNS:
        if pattern in key:
            condition = canonical
            break
    if condition is None:
        # A bare crop name ("Apple leaf", "Tomato leaf") is PlantDoc's way of
        # writing healthy.
        stripped = key.replace("leaf", "").replace("leaves", "").strip("_")
        if stripped in CROP_ALIASES or stripped == crop:
            condition = "healthy"
        else:
            return None

    condition = CROP_SCOPED_MERGES.get((crop, condition), condition)
    return f"{crop}___{condition}"


def is_field(path: str) -> bool:
    """True for a PlantDoc image — a real photo rather than a lab scan.

    The cap, the per-class report and the output filename all depend on this
    answer, so it lives in one place.
    """
    return os.sep + "plantdoc" in path


# ── Fetching ──────────────────────────────────────────────────────────────────

def human(size: int | None) -> str:
    if not size:
        return "unknown size"
    return f"{size / (1024 ** 2):.0f} MB"


# Mendeley's CDN answers Python-urllib's default User-Agent with 403. curl gets
# through, so present a curl UA. Without this the fetch fails outright.
_USER_AGENT = "curl/8.0.1"

# One connection to that CDN sustains ~4 MB/min and resets every few tens of
# MB; twelve of them sustain ~45. The limit is per-connection, not bandwidth,
# and the server advertises Accept-Ranges — so pull the file in parallel
# pieces. Each worker owns one part file and resumes into it independently, so
# a reset costs only that piece's remaining bytes rather than the transfer.
_WORKERS = 12


def _fetch_range(url: str, path: str, start: int, end: int, attempts: int = 400) -> None:
    """Fill ``path`` with bytes ``start..end`` of ``url``, resuming as needed."""
    import urllib.request

    want = end - start + 1
    for _attempt in range(attempts):
        have = os.path.getsize(path) if os.path.exists(path) else 0
        if have >= want:
            return
        request = urllib.request.Request(url, headers={
            "Range": f"bytes={start + have}-{end}",
            "User-Agent": _USER_AGENT,
        })
        try:
            with urllib.request.urlopen(request, timeout=120) as response, \
                    open(path, "ab") as handle:
                while True:
                    block = response.read(1024 * 256)
                    if not block:
                        break
                    handle.write(block)
                    if handle.tell() >= want:
                        return
        except Exception:
            time.sleep(2)  # reset or timeout: the loop re-reads size and resumes
    raise RuntimeError(f"gave up fetching bytes {start}-{end} after {attempts} attempts")


def download(url: str, target: str, total: int | None = None) -> None:
    """Download ``url`` to ``target``, in parallel byte ranges when possible."""
    import threading
    import urllib.request

    print(f"  downloading -> {os.path.basename(target)}")

    # Ranges need a known length and a server that honours them. GitHub's
    # codeload generates archives on the fly and does neither, so fall back to
    # one stream there.
    if not total:
        request = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
        tmp = target + ".part"
        with urllib.request.urlopen(request) as response, open(tmp, "wb") as handle:
            shutil.copyfileobj(response, handle, 1024 * 256)
        os.replace(tmp, target)
        return

    parts_dir = target + ".parts"
    os.makedirs(parts_dir, exist_ok=True)
    span = total // _WORKERS
    jobs = []
    for index in range(_WORKERS):
        start = index * span
        end = (total - 1) if index == _WORKERS - 1 else (start + span - 1)
        jobs.append((os.path.join(parts_dir, f"part{index:02d}"), start, end))

    threads = [
        threading.Thread(target=_fetch_range, args=(url, path, start, end), daemon=True)
        for path, start, end in jobs
    ]
    for thread in threads:
        thread.start()

    while any(thread.is_alive() for thread in threads):
        time.sleep(15)
        done = sum(os.path.getsize(p) for p, _s, _e in jobs if os.path.exists(p))
        print(f"\r    {100.0 * done / total:5.1f}%  "
              f"{done / 1048576:.0f}/{total / 1048576:.0f} MB", end="", flush=True)
    for thread in threads:
        thread.join()
    print()

    for path, start, end in jobs:
        actual = os.path.getsize(path) if os.path.exists(path) else 0
        if actual != end - start + 1:
            raise SystemExit(
                f"Incomplete part {os.path.basename(path)}: {actual} of "
                f"{end - start + 1} bytes. Re-run to resume."
            )

    tmp = target + ".part"
    with open(tmp, "wb") as out:
        for path, _start, _end in jobs:
            with open(path, "rb") as part:
                shutil.copyfileobj(part, out, 1024 * 1024)
    os.replace(tmp, target)
    shutil.rmtree(parts_dir, ignore_errors=True)


def verify(path: str, meta: dict) -> bool:
    """Is the file on disk the file we wanted?

    Worth doing properly rather than trusting "it exists and is big". A
    truncated or double-written zip is not obviously broken — it can still open
    and list some entries — and the failure then shows up as a mysteriously
    small class count several minutes into the build. Size is the cheap check;
    the digest is the one that catches an interleaved writer appending to a
    file that was already complete.
    """
    import hashlib

    if not os.path.isfile(path):
        return False

    expected_size = meta.get("bytes")
    actual_size = os.path.getsize(path)
    if expected_size and actual_size != expected_size:
        print(f"    size mismatch: {actual_size} bytes, expected {expected_size}")
        return False
    if actual_size < 1024 * 1024:
        return False

    expected_digest = meta.get("sha256")
    if not expected_digest:
        return True  # GitHub archives are not byte-stable; size is all we have

    print("    verifying checksum ...", end="", flush=True)
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    actual_digest = digest.hexdigest()
    if actual_digest != expected_digest:
        print(f"\n    checksum mismatch:\n      got      {actual_digest}"
              f"\n      expected {expected_digest}")
        return False
    print(" ok")
    return True


# Characters Windows forbids in a filename. PlantDoc matters here: its images
# were scraped from the web and keep their original names, query strings and
# all — "…picture-id537925565?k=6&m=537925565&s=612x612".  Writing those
# verbatim fails on NTFS for ~100 files. Only the class *directory* carries
# meaning for labelling, so the filename is safe to rewrite.
_ILLEGAL_IN_FILENAME = '?*<>|:"'

# Windows caps a full path at 260 characters unless long paths are enabled, and
# PlantDoc has filenames over 200 characters on their own (they were named from
# page titles: "apple-tree-branch-blossom-plant-fruit-berry-leaf-flower-…").
# Combined with a deep dataset directory that overflows, so long basenames are
# shortened and disambiguated with a digest of the original.
_MAX_BASENAME = 80


def local_name(repo_path: str) -> str:
    """The on-disk path for a repo path, safe on every filesystem.

    Only the class *directory* carries meaning for labelling, so the filename
    is free to be rewritten — which is what makes both of these fixes safe.
    """
    import hashlib

    cleaned = "".join(
        "_" if ch in _ILLEGAL_IN_FILENAME else ch for ch in repo_path
    )
    parts = cleaned.split("/")
    stem, suffix = os.path.splitext(parts[-1])
    if len(parts[-1]) > _MAX_BASENAME:
        digest = hashlib.sha1(repo_path.encode("utf-8")).hexdigest()[:10]
        keep = max(1, _MAX_BASENAME - len(suffix) - len(digest) - 1)
        parts[-1] = f"{stem[:keep]}_{digest}{suffix}"
    return os.sep.join(parts)


def download_github_files(repo: str, ref: str, dest: str, workers: int = 10) -> None:
    """Mirror a GitHub repo's images into ``dest``, one file at a time.

    Re-runnable: a file already on disk at the size the tree reports is left
    alone, so an interrupted fetch resumes for the cost of the missing files.
    """
    import json
    import queue
    import threading
    import urllib.parse
    import urllib.request

    tree_url = (
        f"https://api.github.com/repos/{repo}/git/trees/{ref}?recursive=1"
    )
    request = urllib.request.Request(tree_url, headers={"User-Agent": _USER_AGENT})
    with urllib.request.urlopen(request, timeout=90) as response:
        tree = json.load(response)

    if tree.get("truncated"):
        raise SystemExit(
            f"{repo}: the GitHub tree listing was truncated; this fetcher "
            "cannot enumerate the repo. Clone it manually into " + dest
        )

    blobs = [
        entry for entry in tree.get("tree", [])
        if entry.get("type") == "blob"
        and os.path.splitext(entry["path"])[1].lower() in IMAGE_SUFFIXES
    ]
    total = sum(entry.get("size", 0) for entry in blobs)
    print(f"    {len(blobs)} images, {human(total)}")

    raw_base = f"https://raw.githubusercontent.com/{repo}/{ref}/"
    pending: "queue.Queue" = queue.Queue()
    for blob in blobs:
        pending.put(blob)

    state = {"done": 0}
    failures: list = []
    lock = threading.Lock()

    def fetch_one(blob) -> bool:
        size = blob.get("size", 0)
        target = os.path.join(dest, local_name(blob["path"]))
        if os.path.exists(target) and os.path.getsize(target) == size:
            return True

        os.makedirs(os.path.dirname(target), exist_ok=True)
        # Class folders carry spaces and commas — quote the path, not the URL.
        url = raw_base + urllib.parse.quote(blob["path"])
        for attempt in range(6):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
                with urllib.request.urlopen(req, timeout=60) as response:
                    payload = response.read()
                if size and len(payload) != size:
                    raise IOError(f"short read: {len(payload)} of {size}")
                tmp = target + ".part"
                with open(tmp, "wb") as handle:
                    handle.write(payload)
                os.replace(tmp, target)
                return True
            except Exception:
                time.sleep(1.5 * (attempt + 1))
        return False

    def worker() -> None:
        while True:
            try:
                blob = pending.get_nowait()
            except queue.Empty:
                return
            ok = fetch_one(blob)
            with lock:
                state["done"] += 1
                if not ok:
                    failures.append(blob["path"])

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(workers)]
    started = time.time()
    for thread in threads:
        thread.start()
    while any(thread.is_alive() for thread in threads):
        time.sleep(15)
        with lock:
            done = state["done"]
        rate = done / max(1e-6, time.time() - started)
        left = (len(blobs) - done) / max(1e-6, rate) / 60
        print(f"\r    {done}/{len(blobs)} files  {rate:.1f}/s  ~{left:.1f} min left",
              end="", flush=True)
    for thread in threads:
        thread.join()
    print()

    if failures:
        raise SystemExit(
            f"{len(failures)} files could not be fetched, e.g. {failures[:3]}. "
            "Re-run to retry only the missing ones."
        )


def has_images(root: str, minimum: int = 50) -> bool:
    """Does this directory already hold an extracted image tree?"""
    if not os.path.isdir(root):
        return False
    found = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        found += sum(
            1 for f in filenames
            if os.path.splitext(f)[1].lower() in IMAGE_SUFFIXES
        )
        if found >= minimum:
            return True
    return False


def prepare_sources(work_dir: str, skip_download: bool) -> dict:
    """Get both sources onto disk as extracted trees; return {name: tree dir}.

    An already-extracted tree short-circuits everything. That matters in
    practice: PlantDoc is often faster to obtain with ``git clone`` than as a
    codeload zip (GitHub generates those on the fly and will not serve byte
    ranges), and a big dataset may equally have arrived from a colleague's
    drive. Any tree with images in it is accepted, whatever put it there.
    """
    os.makedirs(work_dir, exist_ok=True)
    trees = {}

    for name, meta in SOURCES.items():
        tree = os.path.join(work_dir, name)
        if has_images(tree):
            print(f"  {name}: using the extracted tree already at {tree}")
            trees[name] = tree
            continue

        if meta.get("mode") == "github_files":
            if skip_download:
                raise SystemExit(
                    f"{name}: no images at {tree} and --skip-download was given."
                )
            print(f"  {name}: ~{human(meta['bytes'])} — {meta['licence']}")
            download_github_files(meta["repo"], meta["ref"], tree)
            trees[name] = tree
            continue

        zip_path = os.path.join(work_dir, meta["zip"])
        if verify(zip_path, meta):
            print(f"  {name}: already downloaded ({human(os.path.getsize(zip_path))})")
        elif skip_download:
            raise SystemExit(
                f"{name}: no extracted tree at {tree}, and the zip at {zip_path} "
                f"is missing or corrupt, and --skip-download was given."
            )
        else:
            print(f"  {name}: {human(meta['bytes'])} — {meta['licence']}")
            download(meta["url"], zip_path, meta["bytes"])
            if not verify(zip_path, meta):
                raise SystemExit(
                    f"{name} failed verification after download. Delete "
                    f"{zip_path} and re-run."
                )
        trees[name] = extract(zip_path, tree)

    return trees


def extract(zip_path: str, target_dir: str) -> str:
    """Extract once; returns the directory holding the extracted tree."""
    marker = os.path.join(target_dir, ".extracted")
    if os.path.isfile(marker):
        print(f"  {os.path.basename(zip_path)}: already extracted")
        return target_dir

    print(f"  extracting {os.path.basename(zip_path)} ...")
    os.makedirs(target_dir, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(target_dir)
    with open(marker, "w", encoding="utf-8") as handle:
        handle.write("ok\n")
    return target_dir


# ── Collection ────────────────────────────────────────────────────────────────

def collect(root: str) -> tuple[dict, dict]:
    """Walk an extracted tree and group image paths by canonical label.

    Returns ``(by_label, unmapped)`` where ``unmapped`` counts the images in
    folders the mapper could not place, keyed by the folder name.
    """
    by_label: dict[str, list[str]] = defaultdict(list)
    unmapped: Counter = Counter()

    for dirpath, dirnames, filenames in os.walk(root):
        # A git-cloned source carries .git with tens of thousands of objects in
        # it; walking that is waste and can only produce false matches.
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        images = [
            f for f in filenames
            if os.path.splitext(f)[1].lower() in IMAGE_SUFFIXES
        ]
        if not images:
            continue

        folder = os.path.basename(dirpath)
        label = canonical_label(folder)
        if label is None:
            unmapped[folder] += len(images)
            continue
        for filename in images:
            by_label[label].append(os.path.join(dirpath, filename))

    return by_label, unmapped


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--out", default="datasets/leaf_disease",
                        help="ImageFolder tree to build")
    parser.add_argument("--work", default="datasets/_downloads",
                        help="where the zips and extracted trees live")
    parser.add_argument("--cap", type=int, default=0,
                        help="max images per class (0 = keep all). Capping keeps "
                             "the set balanced and CPU training tractable.")
    parser.add_argument("--min-images", type=int, default=40,
                        help="drop classes with fewer images than this")
    parser.add_argument("--skip-download", action="store_true",
                        help="fail instead of fetching missing zips")
    parser.add_argument("--report-only", action="store_true",
                        help="show the label mapping and counts, write nothing")
    parser.add_argument("--link", action="store_true",
                        help="hardlink instead of copying (saves ~2 GB; same volume only)")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    random.seed(args.seed)

    print("1. Sources")
    trees = prepare_sources(args.work, args.skip_download)

    print("\n2. Map labels")
    per_source: dict[str, dict] = {}
    combined: dict[str, list[str]] = defaultdict(list)
    for name, tree in trees.items():
        by_label, unmapped = collect(tree)
        per_source[name] = {"labels": by_label, "unmapped": unmapped}
        total = sum(len(v) for v in by_label.values())
        print(f"  {name}: {total} images in {len(by_label)} mapped classes")
        if unmapped:
            print(f"    unmapped folders (skipped, not guessed):")
            for folder, count in unmapped.most_common():
                print(f"      {folder!r}: {count}")
        for label, paths in by_label.items():
            combined[label].extend(paths)

    # Drop classes too small to learn anything from.
    dropped = {k: len(v) for k, v in combined.items() if len(v) < args.min_images}
    for label in dropped:
        del combined[label]

    print(f"\n3. Combined: {sum(len(v) for v in combined.values())} images, "
          f"{len(combined)} classes")
    if dropped:
        print(f"  dropped (< {args.min_images} images): {dropped}")

    for label in sorted(combined):
        paths = combined[label]
        field = sum(1 for p in paths if is_field(p))
        print(f"  {label:42s} {len(paths):6d}  (field: {field})")

    if args.report_only:
        print("\n--report-only: nothing written.")
        return

    print(f"\n4. Writing {args.out}")
    if os.path.isdir(args.out):
        shutil.rmtree(args.out)
    os.makedirs(args.out, exist_ok=True)

    written = 0
    linking_warned = False
    for label in sorted(combined):
        paths = combined[label]
        if args.cap and len(paths) > args.cap:
            # Cap the lab images only. Field images are the scarce, valuable
            # half — a class might be 2,000 PlantVillage leaves against 80
            # PlantDoc photos, and capping the pool as a whole would keep that
            # 96:4 ratio, cutting the field images to a handful and undoing the
            # reason for merging the datasets at all. Keep every field image,
            # then fill the remaining budget with lab ones.
            field = [p for p in paths if is_field(p)]
            lab = [p for p in paths if not is_field(p)]
            random.shuffle(lab)
            paths = field[: args.cap] + lab[: max(0, args.cap - len(field))]

        class_dir = os.path.join(args.out, label)
        os.makedirs(class_dir, exist_ok=True)
        for index, source_path in enumerate(paths):
            suffix = os.path.splitext(source_path)[1].lower()
            # Keep the origin in the filename. The trainer reads it back to
            # score lab-background and real-field images separately, and the
            # field number is the one that predicts how the app will behave.
            origin = "field" if is_field(source_path) else "lab"
            target = os.path.join(class_dir, f"{label}__{origin}__{index:05d}{suffix}")
            try:
                # Hardlink when asked, but fall back to a copy rather than
                # dropping the image: links fail for perfectly ordinary reasons
                # (the sources landing on a different volume, a filesystem
                # without link support), and silently skipping every file would
                # produce an empty dataset that only shows up as a baffling
                # class count much later.
                if args.link:
                    try:
                        os.link(source_path, target)
                    except OSError:
                        if not linking_warned:
                            print("  ! hardlinks unavailable here, copying instead")
                            linking_warned = True
                        shutil.copyfile(source_path, target)
                else:
                    shutil.copyfile(source_path, target)
                written += 1
            except OSError as exc:
                print(f"  ! skipped {source_path}: {exc}")

    print(f"\nDone. {written} images across {len(combined)} classes in {args.out}")
    print("\nNext:")
    print(f"  python tools/train_leaf_disease.py --data {args.out}")


if __name__ == "__main__":
    main()
