# 14_imprints.R -----------------------------------------------------------
# The LiDAR imprint survey: the relict road / path / field-wall landscape of
# the four lost towns, as it still survives in the ground on the dry land that
# never went under. Uses MassGIS 1 m bare-earth LiDAR (2013-2021), rendered as a
# composite relief (multi-direction hillshade emphasised by a Local Relief
# Model) that makes faint linear features read, plus an automatic trace of the
# linear cuts (roads/paths) and banks (walls). Ground-truthed against the 1893
# USGS quad. The Prescott Peninsula is mosaicked from tiles to cover its whole
# length. Exports static survey figures AND web overlays for the explorer.
# Heavy work is cache-guarded (skip if the figure exists) so re-runs are fast.
# Data: MassGIS LiDAR DEM ImageServer (public); USGS Historical Topo (public).
# -------------------------------------------------------------------------
if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("POOL_M")) source(file.path(QB_DIR, "R", "00_setup.R"))
source(file.path(QB_DIR, "R", "lidar_utils.R"))
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)
TOPO_1893 <- file.path(DIR_CACHE, "preflood_belchertown_1893.tif")

# single-window DEM (1 m) or a multi-strip mosaic for long areas (Prescott Peninsula)
fetch_dem <- function(a) {
  mpp <- if (is.null(a$mpp)) 1 else a$mpp
  if (isTRUE(a$tiled)) {
    n <- a$nstrips; bnd <- seq(a$bbox[2], a$bbox[4], length.out = n + 1)
    tiles <- lapply(seq_len(n), function(i) {
      bb <- c(a$bbox[1], bnd[i], a$bbox[3], bnd[i + 1])
      d <- massgis_export(bb, file.path(DIR_CACHE, sprintf("massgis_%s_%d.tif", a$slug, i)), mpp); if (is.na(d)) NULL else terra::rast(d)[[1]]
    })
    tiles <- Filter(Negate(is.null), tiles); if (!length(tiles)) return(NULL)
    poly <- terra::project(terra::as.polygons(terra::ext(a$bbox[1], a$bbox[3], a$bbox[2], a$bbox[4]), crs = "EPSG:4326"), "EPSG:26986")
    tmpl <- terra::rast(terra::ext(poly), resolution = mpp, crs = "EPSG:26986")
    dem <- do.call(terra::merge, lapply(tiles, function(t) terra::resample(t, tmpl, method = "bilinear")))
    terra::cover(dem, terra::focal(dem, 5, "mean", na.rm = TRUE))   # fill thin seams between strips
  } else {
    d <- massgis_export(a$bbox, file.path(DIR_CACHE, paste0("massgis_", a$slug, ".tif")), mpp); if (is.na(d)) NULL else terra::rast(d)[[1]]
  }
}

ground_raster <- function(bbox, dem) {
  if (!file.exists(TOPO_1893)) return(NULL)
  bb <- terra::as.polygons(terra::ext(bbox[1], bbox[3], bbox[2], bbox[4]), crs = "EPSG:4326")
  topo <- terra::project(terra::crop(terra::rast(TOPO_1893), terra::project(bb, terra::crs(terra::rast(TOPO_1893)))), "EPSG:26986", method = "bilinear")
  to_raster(terra::resample(topo, dem, method = "bilinear"))
}
write_overlay <- function(R, G, B, A, slug, maxdim) {
  rgba <- terra::project(c(R, G, B, A), "EPSG:4326")
  f <- max(1, round(max(terra::ncol(rgba), terra::nrow(rgba)) / maxdim)); if (f > 1) rgba <- terra::aggregate(rgba, f, fun = "mean", na.rm = TRUE)
  rgba <- terra::ifel(is.na(rgba), 0, rgba)
  terra::writeRaster(rgba, file.path(DIR_WEB, paste0(slug, ".png")), datatype = "INT1U", overwrite = TRUE, NAflag = NA)
  unlink(list.files(DIR_WEB, pattern = "\\.aux\\.xml$", full.names = TRUE))
  e <- terra::ext(rgba); c(e[3], e[1], e[4], e[2])
}

AREAS <- list(
  list(slug = "dana",      bbox = c(-72.2925, 42.4262, -72.2765, 42.4368), label = "Dana Common",        web = TRUE),
  list(slug = "enfield",   bbox = c(-72.346, 42.305, -72.324, 42.322),    label = "Enfield (Winsor Dam)", web = TRUE),
  # (Greenwich's center is entirely under water — no footprint survives, so it gets no
  #  imprint figure; its drowned site is shown by the reservoir/flood/roads maps and is
  #  covered, transparent-over-water, by the full-reservoir ghost layer in 16_reservoir.R.)
  # The Prescott Peninsula runs ~12 km N-S; a single export exceeds the server's
  # ~4 Mpx cap, so mosaic three ~2 m strips into one DEM for full coverage.
  list(slug = "prescott",  bbox = c(-72.362, 42.350, -72.318, 42.458),    label = "Prescott Peninsula",  web = TRUE, tiled = TRUE, nstrips = 3, mpp = 2)
)

for (a in AREAS) {
  fig <- file.path(DIR_OUTPUT, paste0("24_", a$slug, "_survey.png"))
  ovl <- file.path(DIR_WEB, paste0("imprint_", a$slug, "_trace.png"))
  if (file.exists(fig) && (!isTRUE(a$web) || file.exists(ovl))) { msg("imprints: %s cached, skipping", a$slug); next }

  dem <- fetch_dem(a); if (is.null(dem)) { msg("MassGIS unavailable for %s; skipping", a$slug); next }
  mpp <- if (is.null(a$mpp)) 1 else a$mpp
  demS <- terra::focal(dem, w = 3, fun = "mean", na.rm = TRUE)
  water <- dem <= WATER_LVL; e <- terra::ext(dem)
  slope <- terra::terrain(demS, "slope", unit = "degrees")
  L <- lrm(demS, K = 25); span <- as.numeric(stats::quantile(abs(terra::values(L)), 0.985, na.rm = TRUE))
  g <- relief_grey(demS, L, span)
  Nr <- max(20, round(60 / mpp^1.5))   # min component size scales with pixel size
  roads <- extract_lines(-L, 0.22, slope, 12, water, Nr, 5, 40)
  walls <- extract_lines( L, 0.16, slope, 13, water, round(Nr * 0.9), 5, 35)

  base <- terra::clamp(g, 0, 1) * 255
  ras_rel <- to_raster(c(terra::ifel(water, wc[1], base), terra::ifel(water, wc[2], base), terra::ifel(water, wc[3], base)))
  rc <- grDevices::col2rgb("#ff7b00"); wl <- grDevices::col2rgb("#1fb6a6")
  tRr <- terra::ifel(!is.na(walls), wl[1], base); tGg <- terra::ifel(!is.na(walls), wl[2], base); tBb <- terra::ifel(!is.na(walls), wl[3], base)
  tRr <- terra::ifel(!is.na(roads), rc[1], tRr); tGg <- terra::ifel(!is.na(roads), rc[2], tGg); tBb <- terra::ifel(!is.na(roads), rc[3], tBb)
  ras_tr <- to_raster(c(terra::ifel(water, wc[1], tRr), terra::ifel(water, wc[2], tGg), terra::ifel(water, wc[3], tBb)))

  # ---- static survey figure: 1893 | relief | traced ----
  asp <- terra::nrow(dem) / terra::ncol(dem); pw <- 4.2; ph <- max(4.4, min(14, pw * asp))
  g93 <- ground_raster(a$bbox, dem)
  tR <- tempfile(fileext = ".png"); tT <- tempfile(fileext = ".png")
  render_one(ras_rel, sprintf("Today - %s, MassGIS LiDAR relief", a$label), e, tR, pw, ph)
  render_one(ras_tr, "Auto-traced: roads/paths (orange), walls (teal)", e, tT, pw, ph)
  pngs <- c(tR, tT)
  if (!is.null(g93)) { t9 <- tempfile(fileext = ".png"); render_one(g93, "1893 survey (ground-truth)", e, t9, pw, ph); pngs <- c(t9, tR, tT) }
  stitch_row(pngs, fig, pw, ph, sprintf("%s - what survives in the ground", a$label))

  # ---- web overlays ----
  # the explorer's relief comes from the full-reservoir ghost layer (16_reservoir.R);
  # here we export only the auto-trace overlay (the optional "Traced lines" layer).
  if (isTRUE(a$web)) {
    md <- if (isTRUE(a$tiled)) 6100 else 1400
    hasline <- (!is.na(roads)) | (!is.na(walls))
    oR <- terra::ifel(!is.na(walls), wl[1], 0); oG <- terra::ifel(!is.na(walls), wl[2], 0); oB <- terra::ifel(!is.na(walls), wl[3], 0)
    oR <- terra::ifel(!is.na(roads), rc[1], oR); oG <- terra::ifel(!is.na(roads), rc[2], oG); oB <- terra::ifel(!is.na(roads), rc[3], oB)
    bounds <- write_overlay(oR, oG, oB, terra::ifel(hasline, 255, 0), paste0("imprint_", a$slug, "_trace"), md)
    writeLines(sprintf('  {"slug":"%s","label":"%s","bounds":[[%.6f,%.6f],[%.6f,%.6f]]}',
                       a$slug, a$label, bounds[1], bounds[2], bounds[3], bounds[4]), file.path(DIR_WEB, paste0(".bounds_", a$slug)))
    msg("imprints: %s done (trace overlay + survey figure)", a$slug)
  }
}

# assemble the explorer manifest from each web area's bounds sidecar (in AREAS order).
# The sidecars are git-ignored scratch: on a fresh clone the committed survey figures
# make every area cache-skip, so no sidecars exist -- in that case keep the committed
# manifest instead of clobbering it. Only write when there are actual entries.
lines <- unlist(lapply(AREAS, function(a) if (isTRUE(a$web)) { bf <- file.path(DIR_WEB, paste0(".bounds_", a$slug)); if (file.exists(bf)) readLines(bf) }))
manifest <- file.path(DIR_WEB, "imprints.json")
if (length(lines)) {
  writeLines(c("[", paste(lines, collapse = ",\n"), "]"), manifest)
  msg("imprints stage complete; %d areas in map/data/imprints.json", length(lines))
} else if (file.exists(manifest)) {
  msg("imprints stage complete; no bounds sidecars (all areas cache-skipped) - keeping existing map/data/imprints.json")
} else {
  msg("imprints stage complete; no areas exported and no prior manifest - map/data/imprints.json not written")
}
