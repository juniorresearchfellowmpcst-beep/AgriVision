# Multispectral Preprocessing Module

Turns raw drone multispectral captures into analysis-ready **reflectance** data,
then into the crop-monitoring products you need:

1. **Correct reflectance using the calibration-panel photo** — `reflectance.py`
2. **Check the bands line up cleanly** (band co-registration + a quality score) — `alignment.py`
3. **Assemble an orthomosaic / mosaic** — `orthomosaic.py`
4. **Vegetation indices** NDVI / GNDVI / NDRE — `indices.py`
5. **Low / medium / high management zones** via K-means — `zoning.py`

> Drone **mission planning** from an uploaded KML lives in a sibling package,
> `app/mission/` (parse KML → ordered flight waypoints).

📄 **Full data-flow diagrams:** [docs/PREPROCESSING_DATAFLOW.md](../../docs/PREPROCESSING_DATAFLOW.md)

## Pipeline

```
raw bands ─► reflectance ─► band alignment ─► NDVI/GNDVI/NDRE ─► K-means zones ─► outputs
            calibration      (ECC / ORB)       (indices.py)       (low/med/high)
            (panel photo)    + QC score
```

Each capture is one file per band (16-bit TIFF is typical). A separate photo of
the reflectance panel, shot under the same light, drives the radiometric
correction.

## How each step works

### 1. Reflectance calibration (single-panel method)
- Dark-subtract raw DN; if exposure/gain metadata is supplied, normalise by it
  so pixels are proportional to at-sensor radiance.
- Measure the mean panel signal per band inside the panel ROI (auto-detected or
  supplied), rejecting saturated pixels.
- Per-band scale factor `F = panel_reflectance / panel_signal`.
- `reflectance = F × normalised_scene_signal`, clipped to a physical range.

Assumes illumination is stable between the panel shot and the flight (standard
single-panel assumption). DLS / two-panel data can be folded into `F` later.

### 2. Band alignment ("do the bands line up cleanly?")
- Warp every band onto a reference band (default `green`).
- Primary: **ECC** in a coarse-to-fine gaussian pyramid (robust to the bands
  having different brightness). Fallback: **ORB features + RANSAC homography**.
- Crop to the region valid in all bands.
- **Quality score** per band = zero-normalised cross-correlation of edge maps.
  `aligned_cleanly = min(score) ≥ min_alignment_score` (default 0.65).

### 3. Vegetation indices (`indices.py`)
Normalized-difference ratios computed on the **reflectance** stack:
```
NDVI  = (NIR − Red)     / (NIR + Red)      canopy greenness / biomass
GNDVI = (NIR − Green)   / (NIR + Green)    chlorophyll / nitrogen status
NDRE  = (NIR − RedEdge) / (NIR + RedEdge)  stress in dense / mature canopy
```
Each yields a float32 map in `[-1, 1]`, summary stats, and a red→green preview.

### 4. Management zones (`zoning.py`)
K-means (default k=3) over an index map. Cluster ids from K-means are arbitrary,
so clusters are **re-ordered by mean index** — zone 0 is always lowest-vigor,
zone k−1 highest — giving stable `low` / `medium` / `high` labels with per-zone
area fractions.

### 5. Mosaic / orthomosaic (`orthomosaic.py`)
- `stitch_mosaic()` — OpenCV feature stitch of nadir frames. Good for scouting;
  **not** georeferenced.
- `run_external_odm()` — hands images to OpenDroneMap (native or docker) for a
  survey-grade, georeferenced GeoTIFF when that engine is installed.

## Python usage

```python
from app.preprocessing import preprocess_capture, PipelineConfig

config = PipelineConfig()
config.panel.reflectance = {"blue": 0.49, "green": 0.49, "red": 0.49,
                            "red_edge": 0.49, "nir": 0.49}  # from panel cert

report = preprocess_capture(
    band_paths={"blue": "b.tif", "green": "g.tif", "red": "r.tif",
                "red_edge": "re.tif", "nir": "nir.tif"},
    panel_paths={"blue": "pb.tif", ...},
    output_dir="out/capture_001",
    indices=["ndvi", "gndvi", "ndre"],  # compute all three
    zones=3, zone_index="ndvi",         # low / medium / high on NDVI
)

print(report["alignment"]["aligned_cleanly"], report["alignment"]["mean_score"])
print(report["indices"]["ndvi"]["stats"]["mean"])
for z in report["zones"]["zones"]:
    print(z["label"], z["area_fraction"])
stack = report["_aligned_stack"]   # (n_bands, H, W) aligned reflectance
```

Folder-based captures:

```python
from app.preprocessing import preprocess_capture_dir
report = preprocess_capture_dir("scene_folder/", "panel_folder/", "out/")
```

## REST API

| Method | Path                         | Purpose                                   |
|--------|------------------------------|-------------------------------------------|
| GET    | `/api/preprocessing/health`  | Capabilities + full index catalog         |
| POST   | `/api/preprocessing/analyze-images` | **Multipart** upload of band images → indices + risk zones + report + action plan (no drone/KML needed) |
| POST   | `/api/preprocessing/calibrate` | Reflectance-calibrate + align + index + zone one capture |
| POST   | `/api/preprocessing/mosaic`  | Stitch calibrated rasters into a mosaic   |
| GET    | `/api/preprocessing/output/<path>` | Serve a generated preview / risk-map image |
| POST   | `/api/mission/upload-kml`    | KML file → ordered drone waypoints        |

### Image analysis (no drone yet)

`POST /api/preprocessing/analyze-images` — the flow the Flutter app uses. Send a
multipart form with the band images as file parts (name them `*_nir.tif`,
`*_red.tif`, … for auto-detection, or send a `band_map` field). Add
`calibrate=true` plus panel file parts (field name containing `panel`) for true
reflectance; otherwise the backend uses relative pseudo-reflectance. Response
includes `report` (health score + flags), `risk` (high/medium/low distribution),
`action_plan`, per-index readings, and fetchable preview/risk-map URLs.

The index registry (`indices.INDEX_REGISTRY`, exposed at `/health`) covers 21
indices: NDVI, GNDVI, NDRE, RVI, DVI, SAVI, OSAVI, MSAVI, EVI, EVI2, ARVI, GCI,
RECI, MCARI, PSRI, SIPI, NDWI, GRVI, VARI, ExG, TGI. `available_indices(bands)`
returns just the ones a given band set supports (e.g. RGB-only → GRVI/VARI/ExG/TGI).

`/calibrate` body:

```json
{
  "band_paths":  {"blue": "...", "green": "...", "red": "...", "red_edge": "...", "nir": "..."},
  "panel_paths": {"blue": "...", "green": "...", "red": "...", "red_edge": "...", "nir": "..."},
  "output_dir":  "out/capture_001",
  "panel_reflectance": {"blue": 0.49, "green": 0.49, "red": 0.49, "red_edge": 0.49, "nir": 0.49},
  "panel_roi": {"all": [x, y, w, h]},
  "alignment": {"reference_band": "green", "warp_mode": "homography", "min_alignment_score": 0.65},
  "indices": ["ndvi", "gndvi", "ndre"],
  "zones": 3,
  "zone_index": "ndvi"
}
```

`/api/mission/upload-kml` — multipart file field `file` (a `.kml`) **or** JSON
`{"kml": "<text>", "altitude_m": 60, "line_spacing_m": 20}`. A LineString/Point
KML is flown as-is; a Polygon boundary is filled with a lawnmower survey path.

## Configuration knobs (`config.py`)
- `bands` — band names and order (defaults to a 5-band setup).
- `panel.reflectance` — **set these from your panel's calibration certificate.**
- `panel.roi` — skip auto-detection with an explicit `{band|"all": (x,y,w,h)}`.
- `sensor.black_level`, `bit_depth`, `saturation_fraction`.
- `alignment.reference_band`, `warp_mode`, `min_alignment_score`, `pyramid_levels`.

## Dependencies
Uses only what the backend already ships: `numpy`, `opencv-python`, `pillow`.
Georeferenced orthomosaics additionally need an OpenDroneMap engine (optional).
```
