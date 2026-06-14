# Quabbin study — changelog

## 2026-06-14 — Dam-containment fix + locator redesign

Two cleanup items on the regenerated figures.

### Reservoir no longer spills below the dams
The reservoir footprint is built in `R/02_build_layers.R` from MassGIS 1 m LiDAR
(downsampled to 10 m). At 10 m the dams don't fully seal, so the "largest patch
below the 530 ft pool" still pulled in ~2 sq km of below-dam ground — water drawn
south of Winsor Dam / Goodnough Dike onto Belchertown/Ware. This had leaked into
every figure that draws the reservoir and into the web explorer's
`reservoir.geojson`.

- `02_build_layers.R`: after extraction, the footprint is now **clipped at the
  dam line** (Winsor Dam 42.2967 N, Goodnough Dike 42.2920 N) — the dams are the
  true southern boundary. Spill dropped from ~2.2 km² to ~0; southern shore now
  sits at the dams (lat 42.296). The fix applies to whichever branch built the
  footprint (LiDAR / coarse-DEM / OSM).
- Regenerated every reservoir-bearing artifact from the dam-contained footprint:
  figures `01–05`, `08`, `09` (+ flood GIF), `10`, `11`, `13`, `16`, and the web
  exports `reservoir.geojson` and `floodstages.geojson`. The heavy LiDAR stages
  (`12`,`14`,`15`,`16_reservoir`) were left untouched — they derive water
  per-pixel from their own LiDAR DEMs and never used the carve.

### Locator redesigned (`01_locator.png`)
Replaced the flat grey-state-with-a-red-box locator with a composite: the valley
in shaded relief (the subject), with the four town sites, and a small
Massachusetts "you are here" chip marking Quabbin and Boston.

## 2026-06-12 — Standalone-repo closeout

The study moved into its own repository ([`mapzimus/quabbin`](https://github.com/mapzimus/quabbin)),
split from the portfolio repo with history preserved. Final tidy for the split:

- README and `run_all.R` run instructions no longer assume the old `quabbin/`
  subfolder layout — paths are now relative to the study folder, so the same
  text is correct in both the standalone repo and the portfolio copy.
- **MIT license** added (code only; the data sources are U.S. public domain,
  credited in the README).
- New README section **"Where this lives"** documents the two-copy workflow:
  the standalone repo is the source of truth; the portfolio's `quabbin/`
  folder is the deployed copy that serves the live page and explorer.
- GitHub repo metadata filled in: description, topics, homepage.

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
