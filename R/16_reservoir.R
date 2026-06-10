# 16_reservoir.R ----------------------------------------------------------
# Full-reservoir LiDAR "ghost" coverage. Tiles the whole Quabbin land area in
# MassGIS bare-earth LiDAR and renders each as a fine Local Relief Model (the
# rendering that makes drowned-town street plans, house-lot outlines and
# cellar-hole pits read in the bare ground), transparent over water. Broad
# coverage at ~2 m; crisp ~1 m tiles at the surviving village sites. Exports
# web overlays + map/data/reservoir_ghost.json for the explorer.
# Cache-guarded at two levels: the LiDAR downloads (the slow part), and the
# whole stage -- when the manifest exists and every overlay it lists is on
# disk there is nothing to re-export. Delete map/data/reservoir_ghost.json to
# force a full rebuild.
# Data: MassGIS 1 m LiDAR DEM ImageServer (public domain).
# -------------------------------------------------------------------------
if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("POOL_M")) source(file.path(QB_DIR, "R", "00_setup.R"))
source(file.path(QB_DIR, "R", "lidar_utils.R"))
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)
MANIFEST <- file.path(DIR_WEB, "reservoir_ghost.json")

# stage-level cache guard: re-exporting all ~20 overlays takes minutes, so skip
# the stage when the manifest and every overlay PNG it references already exist.
ghost_slugs <- character(0)
if (file.exists(MANIFEST)) {
  txt <- paste(readLines(MANIFEST, warn = FALSE), collapse = "")
  ghost_slugs <- sub('^"slug":"(.*)"$', "\\1", regmatches(txt, gregexpr('"slug":"[^"]*"', txt))[[1]])
}
if (length(ghost_slugs) && all(file.exists(file.path(DIR_WEB, paste0("imprintg_", ghost_slugs, ".png"))))) {
  msg("reservoir ghost: manifest + all %d overlays present, skipping (delete map/data/reservoir_ghost.json to force a re-export)", length(ghost_slugs))
} else {

# fine LRM ghost as RGBA (grey relief; alpha 0 over water / no-data) -> Leaflet bounds.
# span = fixed contrast (so adjacent broad tiles match -> no seams); NULL = per-tile (zoomed sites).
ghost_overlay <- function(dem, slug, maxdim, span = NULL) {
  demS <- terra::focal(dem, 3, "mean", na.rm = TRUE); L <- lrm(demS, 13)
  sp <- if (is.null(span)) { v <- as.numeric(stats::quantile(abs(terra::values(L)), 0.985, na.rm = TRUE)); if (!is.finite(v) || v == 0) 1 else v } else span
  g <- terra::clamp(0.5 + L/(1.5*sp), 0, 1) * 255
  A <- terra::ifel(dem <= WATER_LVL | is.na(demS), 0, 235)
  rgba <- terra::project(c(g, g, g, A), "EPSG:4326")
  f <- max(1, round(max(terra::ncol(rgba), terra::nrow(rgba))/maxdim)); if (f > 1) rgba <- terra::aggregate(rgba, f, fun = "mean", na.rm = TRUE)
  rgba <- terra::ifel(is.na(rgba), 0, rgba)
  terra::writeRaster(rgba, file.path(DIR_WEB, paste0(slug, ".png")), datatype = "INT1U", overwrite = TRUE, NAflag = NA)
  unlink(list.files(DIR_WEB, pattern = "\\.aux\\.xml$", full.names = TRUE))
  e <- terra::ext(rgba); c(e[3], e[1], e[4], e[2])
}
landfrac <- function(dem) as.numeric(terra::global(dem > WATER_LVL & !is.na(dem), "mean", na.rm = TRUE))

# ---- broad coverage: tile the reservoir land area at ~2 m ----
RES <- c(-72.400, 42.270, -72.280, 42.460); NC <- 3; NR <- 6
lon <- seq(RES[1], RES[3], length.out = NC + 1); lat <- seq(RES[2], RES[4], length.out = NR + 1)
entries <- list()
for (j in seq_len(NR)) for (i in seq_len(NC)) {
  bb <- c(lon[i], lat[j], lon[i+1], lat[j+1]); slug <- sprintf("ghost_r%dc%d", j, i)
  tif <- massgis_export(bb, file.path(DIR_CACHE, sprintf("massgis_%s.tif", slug)), 2)
  if (is.na(tif)) { msg("  %s: fetch failed, skipping", slug); next }
  dem <- terra::rast(tif)[[1]]; lf <- landfrac(dem)
  if (lf < 0.02) { msg("  %s: ~all water (%.0f%% land), skipping", slug, 100*lf); next }
  b <- ghost_overlay(dem, paste0("imprintg_", slug), 1800, span = 1.1)   # fixed contrast across broad tiles
  entries[[length(entries)+1]] <- sprintf('  {"slug":"%s","res":"2m","bounds":[[%.6f,%.6f],[%.6f,%.6f]]}', slug, b[1], b[2], b[3], b[4])
  msg("  %s: %.0f%% land -> overlay written", slug, 100*lf)
}

# ---- crisp 1 m tiles at the surviving village sites ----
SITES <- list(
  list(slug = "prescottctr", bbox = c(-72.352, 42.386, -72.338, 42.397), cache = "massgis_prescottctr.tif"),
  list(slug = "danacommon",  bbox = c(-72.290, 42.427, -72.277, 42.436),  cache = "massgis_danacommon.tif")
)
for (s in SITES) {
  tif <- massgis_export(s$bbox, file.path(DIR_CACHE, s$cache), 1); if (is.na(tif)) next
  b <- ghost_overlay(terra::rast(tif)[[1]], paste0("imprintg_", s$slug), 1400)
  entries[[length(entries)+1]] <- sprintf('  {"slug":"%s","res":"1m","bounds":[[%.6f,%.6f],[%.6f,%.6f]]}', s$slug, b[1], b[2], b[3], b[4])
  msg("  site %s: 1 m ghost overlay written", s$slug)
}

# only write the manifest when something was exported -- a partial MassGIS
# outage must not shrink it and silently drop explorer tiles.
if (length(entries)) {
  writeLines(c("[", paste(unlist(entries), collapse = ",\n"), "]"), MANIFEST)
  msg("reservoir ghost coverage: %d tiles in map/data/reservoir_ghost.json", length(entries))
} else if (file.exists(MANIFEST)) {
  msg("reservoir ghost: no overlays exported (MassGIS unreachable?) - keeping existing map/data/reservoir_ghost.json")
} else {
  msg("reservoir ghost: no overlays exported and no prior manifest - map/data/reservoir_ghost.json not written")
}
}
