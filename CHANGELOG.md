# Quabbin study — changelog

## 2026-06-10 — UX, accessibility & code-quality round (multi-agent)

A parallel polish pass (three workers on disjoint files + an overseer audit),
verified independently. No rendered figures or web data were regenerated — only
source, markup, and docs changed (12 files, ~+186/−173, plus this changelog).

### Explorer (`map/index.html`)
- Loading indicator while LiDAR/overlay imagery streams in (the LiDAR relief layer
  is ~37 MB); overlays confirmed to fetch only when a layer is first enabled.
- LiDAR relief **opacity slider** (shown while the layer is on; drives all tiles).
- **Scale bar** (metric + imperial; hidden on mobile so it can't collide with the
  flood bar) and a `LiDAR: MassGIS` attribution.
- Honesty: a "schematic stages" label + tooltip on the reservoir-filling slider.
- About copy now leads with LiDAR relief and names MassGIS 1 m bare-earth LiDAR;
  trace legend states the actual colours (roads/paths orange, stone walls teal).
- Accessibility: `aria-pressed` synced on the About/Layers toggles; play/pause
  `aria-label`; `:focus-visible` outlines; ESC closes the About panel and the
  mobile sheet; transitions/spinner gated behind `prefers-reduced-motion`.

### Project page (`quabbin.html`, `js/projects.js`)
- New section **"What survives in the ground"** (between the animation and the gallery):
  a short, factual explainer with the Prescott 1893-vs-LiDAR triptych and a CTA
  into the explorer.
- Hero tightened (6→5 paragraphs) with the LiDAR relief explorer as the headline;
  flood-fill section relabelled and reworded as a schematic illustration, not
  surveyed bathymetry; "MassGIS LiDAR" added to the tech pills.
- Gallery image render gets lazy-loading + meaningful `alt`; lightbox controls got
  `aria-label`s. Meta/`og:description` and the `projects.js` card refreshed
  (20 figures; MassGIS LiDAR; schematic animation; "LiDAR imprint explorer").

### Pipeline (`R/`)
- New `R/lidar_utils.R` consolidates the helpers that stages 14–16 had copy-pasted
  (`to_raster`, `lrm`, `mdow`, `relief_grey`, `linfilter`/`extract_lines`,
  `massgis_export`, `render_one`, `stitch_row`, shared constants); the stages now
  source it. `12_lidar.R` and `02_build_layers.R` keep their own variants by design.
- Dead code removed: `POUR_LL`, `%||%` (`00_setup.R`), `dams_ma` (`06_aqueduct.R`),
  `deep_mi` (`08_profile.R`). README reconciled (twenty figures; LiDAR stages 14–16).

### Fixed
- `14_imprints.R`: no longer clobbers `map/data/imprints.json` to `[]` on a fresh
  clone (when the git-ignored `.bounds_*` sidecars are absent) — the committed
  manifest is preserved when there are no new entries.
- `16_reservoir.R`: added a stage-level cache guard (skips when the manifest and all
  its overlay PNGs exist; delete `reservoir_ghost.json` to force a rebuild) and now
  writes the manifest only when entries exist, so a partial MassGIS outage can no
  longer silently drop explorer tiles.

### Verification
- All 17 R stages + `run_all.R` + `lidar_utils.R` parse; inline JS of both pages and
  `projects.js` pass `node --check`.
- Behaviour-equivalence harness for the de-duplicated helpers: old definitions
  (extracted verbatim from git) vs the new shared helpers on synthetic rasters —
  identical outputs, byte-identical export URLs (24/24).
- Headless Chromium on both pages: 0 page errors, all local requests 200; explorer
  layers/opacity/flood/jump-to exercised; gallery renders 20 images.

## Earlier milestones
- Initial multi-layer study: terrain, DEM-carved reservoir, watershed, town points,
  population (#16).
- Depth round: real census series, reservoir-filling animation, aqueduct, first
  interactive map (#18); cross-section, by-the-numbers, 3D, 1893 overlay (#19).
- Read-through audit: render-safe figure text, neutral tone, accurate distances (#21).
- LiDAR of the surviving sites + the 1893 road network (#22, #23).
- LiDAR **imprint survey** of the four towns + the mobile-first imprint explorer (#23).
- Explorer map fixes: zoom-in limit, control/panel overlaps, sharper peninsula (#24).
- Full-reservoir **LiDAR relief** coverage for the explorer (#26).
- Reservoir derived from MassGIS LiDAR — **dam-contained**, no longer spilling past
  the dams onto Belchertown/Ware (#28).
- Ground-truth cross-reference (1893 roads vs. LiDAR traces) (#25/#28 era).
- **Schematic bathymetry** reservoir-filling animation (gradual, captioned) (#31).
- Closeout cleanup: orphaned overlays + dead code removed (#32).
</content>
