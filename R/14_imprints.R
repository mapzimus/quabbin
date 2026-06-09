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
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)
TOPO_1893 <- file.path(DIR_CACHE, "preflood_belchertown_1893.tif")
MG <- "https://arcgisserver.digital.mass.gov/arcgisserver/rest/services/LiDAR/DEM_lidar_2013to2021_32bitFloat/ImageServer/exportImage"
WATER_LVL <- POOL_M + 0.5; wc <- grDevices::col2rgb(WATER_FILL)[, 1]

to_raster <- function(rgb3) { arr <- terra::as.array(rgb3) / 255; arr[is.na(arr)] <- 1; grDevices::as.raster(arr) }
lrm <- function(dem, K = 25) dem - terra::focal(dem, w = K, fun = "mean", na.rm = TRUE)
mdow <- function(dem, angle = 35) {
  slp <- terra::terrain(dem, "slope", unit = "radians"); asp <- terra::terrain(dem, "aspect", unit = "radians")
  hs <- Reduce(`+`, lapply(seq(0, 315, 45), function(a) terra::shade(slp, asp, angle = angle, direction = a))) / 8
  terra::clamp((hs - 0.5) * 1.6 + 0.5, 0, 1)
}
relief_grey <- function(demS, L, span) {
  hs <- mdow(demS); neg <- terra::clamp(-L / span, 0, 1); pos <- terra::clamp(L / span, 0, 1)
  terra::clamp(hs * (1 - 0.5 * neg) + 0.32 * pos * (1 - hs), 0, 1)
}
extract_lines <- function(signed, thr, slope, slopemax, water, Nmin, Emin, Lmin) {
  mask <- terra::ifel(signed > thr & slope < slopemax & !water, 1, NA)
  p <- terra::patches(mask, directions = 8, zeroAsNA = TRUE)
  v <- terra::values(p)[, 1]; cells <- which(!is.na(v)); if (!length(cells)) return(p * NA)
  ids <- v[cells]; xy <- terra::xyFromCell(p, cells); spl <- split(as.data.frame(xy), ids)
  sizes <- vapply(spl, nrow, integer(1))
  st <- lapply(spl, function(d) { if (nrow(d) < 8) return(c(0, 0)); ev <- eigen(stats::cov(d), only.values = TRUE)$values
    c(sqrt(max(ev) / max(min(ev), 1e-4)), sqrt(max(ev)) * 3.5) })
  el <- vapply(st, `[`, numeric(1), 1); ln <- vapply(st, `[`, numeric(1), 2)
  keep <- as.numeric(names(sizes)[sizes >= Nmin & el >= Emin & ln >= Lmin])
  if (length(keep)) terra::subst(p, keep, 1, others = NA) else p * NA
}

dl_window <- function(bbox, dst, mpp) {
  if (!file.exists(dst) || file.size(dst) < 1e5) {
    latm <- mean(c(bbox[2], bbox[4]))
    w <- round((bbox[3] - bbox[1]) * cos(latm * pi / 180) * 111320 / mpp); h <- round((bbox[4] - bbox[2]) * 111320 / mpp)
    if (w * h > 4.0e6) { f <- sqrt(4.0e6 / (w * h)); w <- floor(w * f); h <- floor(h * f) }
    url <- sprintf("%s?bbox=%f,%f,%f,%f&bboxSR=4326&size=%d,%d&imageSR=26986&format=tiff&pixelType=F32&interpolation=RSP_BilinearInterpolation&f=image",
                   MG, bbox[1], bbox[2], bbox[3], bbox[4], w, h)
    for (k in 1:6) { ok <- tryCatch({ download.file(url, dst, mode = "wb", quiet = TRUE); file.exists(dst) && file.size(dst) > 1e5 }, error = function(e) FALSE)
      if (ok) break; Sys.sleep(2 * k) }   # MassGIS throws intermittent 500s; retry resolves them
  }
  if (file.exists(dst) && file.size(dst) > 1e5) dst else NA_character_
}
# single-window DEM (1 m) or a multi-strip mosaic for long areas (Prescott Peninsula)
fetch_dem <- function(a) {
  mpp <- if (is.null(a$mpp)) 1 else a$mpp
  if (isTRUE(a$tiled)) {
    n <- a$nstrips; bnd <- seq(a$bbox[2], a$bbox[4], length.out = n + 1)
    tiles <- lapply(seq_len(n), function(i) {
      bb <- c(a$bbox[1], bnd[i], a$bbox[3], bnd[i + 1])
      d <- dl_window(bb, file.path(DIR_CACHE, sprintf("massgis_%s_%d.tif", a$slug, i)), mpp); if (is.na(d)) NULL else terra::rast(d)[[1]]
    })
    tiles <- Filter(Negate(is.null), tiles); if (!length(tiles)) return(NULL)
    poly <- terra::project(terra::as.polygons(terra::ext(a$bbox[1], a$bbox[3], a$bbox[2], a$bbox[4]), crs = "EPSG:4326"), "EPSG:26986")
    tmpl <- terra::rast(terra::ext(poly), resolution = mpp, crs = "EPSG:26986")
    dem <- do.call(terra::merge, lapply(tiles, function(t) terra::resample(t, tmpl, method = "bilinear")))
    terra::cover(dem, terra::focal(dem, 5, "mean", na.rm = TRUE))   # fill thin seams between strips
  } else {
    d <- dl_window(a$bbox, file.path(DIR_CACHE, paste0("massgis_", a$slug, ".tif")), mpp); if (is.na(d)) NULL else terra::rast(d)[[1]]
  }
}

render_one <- function(ras, sub, e, file, w, h) {
  p <- ggplot() + annotation_raster(ras, e[1], e[2], e[3], e[4], interpolate = TRUE) +
    coord_sf(crs = st_crs(CRS_MA), xlim = c(e[1], e[2]), ylim = c(e[3], e[4]), datum = NA, expand = FALSE) +
    labs(subtitle = sub) + theme_quabbin() +
    theme(axis.text = element_blank(), axis.title = element_blank(), panel.grid = element_blank(),
          plot.subtitle = element_text(face = "bold", size = 10.5), panel.border = element_rect(colour = "#888888", fill = NA, linewidth = 0.5))
  ggsave(file, p, width = w, height = h, dpi = 150, bg = "white"); file
}
stitch_row <- function(pngs, out, pw, ph, title, res = 150) {
  imgs <- lapply(pngs, png::readPNG)
  grDevices::png(out, width = pw * length(imgs) * res, height = (ph + 0.3) * res, res = res); grid::grid.newpage()
  grid::grid.text(title, y = grid::unit(1, "npc") - grid::unit(3, "mm"), vjust = 1, gp = grid::gpar(fontface = "bold", fontsize = 15))
  grid::pushViewport(grid::viewport(y = 0, height = grid::unit(1, "npc") - grid::unit(8, "mm"), just = "bottom", layout = grid::grid.layout(1, length(imgs))))
  for (i in seq_along(imgs)) { grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = i)); grid::grid.raster(imgs[[i]]); grid::popViewport() }
  grDevices::dev.off(); out
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
  ovl <- file.path(DIR_WEB, paste0("imprint_", a$slug, ".png"))
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
  } else msg("imprints: %s done (static survey figure only)", a$slug)
}

# assemble the explorer manifest from each web area's bounds sidecar (in AREAS order)
lines <- unlist(lapply(AREAS, function(a) if (isTRUE(a$web)) { bf <- file.path(DIR_WEB, paste0(".bounds_", a$slug)); if (file.exists(bf)) readLines(bf) }))
writeLines(c("[", paste(lines, collapse = ",\n"), "]"), file.path(DIR_WEB, "imprints.json"))
msg("imprints stage complete; %d areas in map/data/imprints.json", length(lines))
