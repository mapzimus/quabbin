# Quabbin: a valley chosen, four towns erased

A small, reproducible **R** GIS study of the Quabbin Reservoir, Massachusetts —
the reservoir created between 1938 and 1946 by deliberately flooding four
disincorporated towns of the Swift River Valley: **Dana, Enfield, Greenwich,
and Prescott.** Around 2,500 people were displaced so that Boston, 65 miles
east, could drink.

It is built as a *multi-layer study* in the spirit of the "Cairo test": several
spatial layers that, read together, converge on one story —

> The terrain made the valley an obvious basin; the state filled it; four
> towns vanished from the map and their land was parcelled out to the
> survivors that ring the water today.

![Hero map](output/08_hero.png)

## The layers

| # | Figure | What it shows | Source |
|---|--------|---------------|--------|
| 1 | `01_locator.png` | Where the reservoir sits in Massachusetts | TIGER + DEM-derived water |
| 2 | `02_dem_hillshade.png` | The Swift River Valley basin — the terrain that made it a reservoir | AWS Terrain Tiles (elevatr) |
| 3 | `03_reservoir_towns.png` | The four drowned towns over the water that replaced them | DEM + bundled town points |
| 4 | `04_watershed.png` | The reservoir nested inside its drainage (regional context) | USGS WBD HUC-10 |
| 5 | `05_erasure.png` | The towns are gone; their land divided among surviving municipalities | TIGER municipalities |
| 6 | `06_town_lifelines.png` | Four towns chartered across three centuries, all dissolved on one day | town charter records |
| 7 | `07_population_decline.png` | Prescott was already dying before the water came | NEHGS / town histories |
| 8 | `08_hero.png` | Terrain + water + the vanished towns, together | all of the above |

## Running it

R is the only requirement. On Ubuntu the heavy spatial stack installs as
binaries (no source compiles):

```bash
sudo apt-get install -y r-base-core r-cran-sf r-cran-terra r-cran-raster \
    r-cran-ggplot2 r-cran-dplyr libcurl4-openssl-dev libxml2-dev libjpeg-dev
Rscript -e 'install.packages(c("elevatr","osmdata","tigris","ggspatial","ggnewscale","ggrepel","patchwork"))'
```

Then, from the repository root:

```bash
Rscript quabbin/run_all.R
```

Downloads are cached under `quabbin/data/cache/` (git-ignored), so the first
run takes a few minutes and every run after that is ~10 seconds. The eight
figures land in `quabbin/output/`.

## How it is built

```
quabbin/
├── run_all.R              one-command reproduction
├── R/
│   ├── 00_setup.R         packages, CRS (EPSG:26986), area of interest, palettes
│   ├── 01_fetch_data.R    elevatr DEM · OSM/DEM reservoir · TIGER towns · USGS watershed
│   ├── 02_build_layers.R  reproject, hillshade, carve the reservoir, assemble layers
│   ├── 03_maps.R          the six spatial figures (shaded relief + vector overlays)
│   └── 04_population.R    the two displacement charts
├── data/
│   ├── drowned_towns.csv  the four towns: location, county, charter & end dates
│   └── town_population.csv Prescott's documented decline
└── output/                the rendered figures (committed)
```

Every network fetch in `01_fetch_data.R` is wrapped so one unreachable service
never breaks the run — it degrades to a documented fallback instead.

## Data, methods, and honest caveats

- **Elevation** — AWS Terrain Tiles (SRTM/USGS, public domain) via
  `elevatr::get_elev_raster(z = 11)`, reprojected to NAD83 / Massachusetts
  Mainland (EPSG:26986) and hillshaded with `terra`.
- **Reservoir** — by default **carved from the DEM** at Quabbin's 530-ft
  full-pool surface (the single largest contiguous polygon below that
  elevation). This needs no external service and ties the water directly to the
  terrain. An OpenStreetMap shoreline path (`RESERVOIR_METHOD <- "osm"`) is
  available but opt-in, because public Overpass servers frequently rate-limit
  or block cloud IPs.
- **Watershed** — USGS Watershed Boundary Dataset HUC-10 units (public domain),
  queried live from the National Map ArcGIS service. **These are deliberately
  shown as regional context, not as the catchment boundary:** the dissolved
  HUC-10s are several times larger than the ~120 sq mi DCR-defined Quabbin
  watershed (a MassGIS layer that was not reachable here). The map says so.
- **Modern municipalities** — US Census TIGER county subdivisions (2021,
  public domain) via `tigris`.
- **The four towns** — there is no clean, freely downloadable historic GIS
  boundary for towns abolished in 1938, so they are plotted as labeled points
  at their historic centers (coordinates from the towns' Wikipedia pages).
- **Population** — popular sources give well-documented *anchor* figures rather
  than a full decennial table, so this study uses only what can be cited:
  Prescott's ~750 (1830) → ~300 (1900) → ~18 (1938), and the commonly cited
  ~2,500 total displaced. The charts are labeled as anchor points, not an
  interpolated series. Charter dates: Greenwich 1754, Dana 1801, Enfield 1816,
  Prescott 1822; all four disincorporated **28 April 1938**.

## Stack

`R` · `sf` · `terra` · `elevatr` · `osmdata` · `tigris` · `ggplot2` ·
`ggnewscale` · `ggrepel` · `ggspatial` · GDAL 3.8

---
*Part of an ongoing series of multi-layer GIS studies of geography-shaped
American places. Data is open; figures are reproducible from the scripts above.*
