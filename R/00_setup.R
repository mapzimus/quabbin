# 00_setup.R --------------------------------------------------------------
# Packages, projections, area-of-interest, paths, palettes and helpers for
# the Quabbin study. Sourced first by run_all.R; safe to source on its own
# (it figures out where the project lives).
# -------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(dplyr)
  library(ggplot2)
  library(ggnewscale)   # two fill scales in one plot (hillshade + hypsometry)
  library(ggrepel)      # non-overlapping town labels
  library(patchwork)    # compose multi-panel figures
})

# --- Locate the project root (works from repo root or the quabbin/ folder) --
if (!exists("QB_DIR")) {
  cand <- c(getwd(), file.path(getwd(), "quabbin"))
  hit  <- cand[file.exists(file.path(cand, "R", "00_setup.R"))]
  QB_DIR <- if (length(hit)) normalizePath(hit[1]) else getwd()
}

DIR_DATA   <- file.path(QB_DIR, "data")
DIR_CACHE  <- file.path(QB_DIR, "data", "cache")
DIR_OUTPUT <- file.path(QB_DIR, "output")
dir.create(DIR_CACHE,  recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_OUTPUT, recursive = TRUE, showWarnings = FALSE)

# --- Coordinate reference systems ----------------------------------------
CRS_LL <- 4326    # WGS84 lon/lat (everything is fetched in this)
CRS_MA <- 26986   # NAD83 / Massachusetts Mainland (metres) -- area-true maps

# --- Area of interest: the Swift River Valley / Quabbin Reservoir ---------
AOI_BBOX <- c(xmin = -72.46, ymin = 42.22, xmax = -72.18, ymax = 42.50)
aoi_ll   <- st_as_sfc(st_bbox(AOI_BBOX, crs = CRS_LL))
aoi_ma   <- st_transform(aoi_ll, CRS_MA)

# Quabbin full-pool surface = 530 ft above sea level. Used to carve the
# reservoir straight out of the DEM (see RESERVOIR_METHOD below).
POOL_FT <- 530
POOL_M  <- POOL_FT * 0.3048            # 161.5 m

# Reservoir geometry source:
#   "dem" - carve it from the 530 ft full-pool surface. No network, fully
#           reproducible, and it ties the water directly to the terrain.
#   "osm" - precise shoreline from OpenStreetMap. Needs a reachable Overpass
#           server (often rate-limited / IP-blocked), so it is opt-in and
#           guarded by a fast probe that falls back to "dem".
RESERVOIR_METHOD <- "dem"

# --- Cartography ----------------------------------------------------------
# Low -> high hypsometric ramp tuned for a New England valley (~100-400 m).
HYPSO_PAL <- c("#1d4d2b", "#3f7a3f", "#7aa55a", "#bcc98c",
               "#e6dca6", "#cdab74", "#9c7b4d", "#f3efe6")
WATER_FILL <- "#2b6cb0"
WATER_LINE <- "#0b3d66"
INK        <- "#1a1a1a"

ATTRIB <- paste(
  "Elevation: AWS Terrain Tiles (SRTM/USGS)  -  Boundaries: US Census TIGER",
  "Town charters & figures: town histories / NEHGS / Wikipedia",
  sep = "\n"
)

theme_quabbin <- function(base = 12) {
  theme_minimal(base_size = base) +
    theme(
      plot.title    = element_text(face = "bold", size = rel(1.25), colour = INK),
      plot.subtitle = element_text(colour = "#444444", margin = margin(b = 8)),
      plot.caption  = element_text(colour = "#777777", size = rel(0.72), hjust = 0),
      panel.grid    = element_blank(),
      axis.title    = element_blank(),
      axis.text     = element_text(colour = "#999999", size = rel(0.65)),
      legend.position = "right",
      plot.margin   = margin(12, 14, 10, 14)
    )
}

# --- Small helpers --------------------------------------------------------
msg <- function(...) cat(sprintf("[quabbin] %s\n", sprintf(...)))

# Save a ggplot at a consistent size/quality.
save_map <- function(plot, file, w = 9, h = 9, dpi = 150) {
  path <- file.path(DIR_OUTPUT, file)
  ggsave(path, plot, width = w, height = h, dpi = dpi, bg = "white")
  msg("wrote %s", file.path("output", file))
  invisible(path)
}

msg("setup complete - project at %s", QB_DIR)
