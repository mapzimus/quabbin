# 14_imprints.R -----------------------------------------------------------
# The LiDAR imprint survey: the relict road / path / field-wall landscape of
# the four lost towns, as it still survives in the ground on the dry land that
# never went under. Uses MassGIS 1 m bare-earth LiDAR (2013-2021), rendered as a
# composite relief (multi-direction hillshade emphasised by a Local Relief
# Model) that makes faint linear features read, and an automatic trace of the
# linear cuts (roads/paths) and banks (walls). Ground-truthed against the 1893
# USGS quad. Exports static survey figures AND web overlays for the explorer.
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

fetch_massgis <- function(bbox, dst) {
  if (!file.exists(dst) || file.size(dst) < 1e5) {
    latm <- mean(c(bbox[2], bbox[4]))
    w <- round((bbox[3] - bbox[1]) * cos(latm * pi / 180) * 111320)
    h <- round((bbox[4] - bbox[2]) * 111320)
    if (w * h > 4.0e6) { f <- sqrt(4.0e6 / (w * h)); w <- floor(w * f); h <- floor(h * f) }  # stay under server limit
    url <- sprintf("%s?bbox=%f,%f,%f,%f&bboxSR=4326&size=%d,%d&imageSR=26986&format=tiff&pixelType=F32&interpolation=RSP_BilinearInterpolation&f=image",
                   MG, bbox[1], bbox[2], bbox[3], bbox[4], w, h)
    for (try in 1:3) { ok <- tryCatch({ download.file(url, dst, mode = "wb", quiet = TRUE); file.exists(dst) && file.size(dst) > 1e5 }, error = function(e) FALSE)
      if (ok) break; Sys.sleep(2 * try) }
  }
  if (file.exists(dst) && file.size(dst) > 1e5) dst else NA_character_
}

# composite-lite relief: multi-direction hillshade, cuts darkened & banks lifted by LRM
relief_grey <- function(demS, L, span) {
  hs <- mdow(demS); neg <- terra::clamp(-L / span, 0, 1); pos <- terra::clamp(L / span, 0, 1)
  terra::clamp(hs * (1 - 0.5 * neg) + 0.32 * pos * (1 - hs), 0, 1)
}

# elongated connected components of (signed relief > thr) on gentle, dry ground
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

render_one <- function(ras, sub, e, file, w = 6, h = 6.4) {
  p <- ggplot() + annotation_raster(ras, e[1], e[2], e[3], e[4], interpolate = TRUE) +
    coord_sf(crs = st_crs(CRS_MA), xlim = c(e[1], e[2]), ylim = c(e[3], e[4]), datum = NA, expand = FALSE) +
    labs(subtitle = sub) + theme_quabbin() +
    theme(axis.text = element_blank(), axis.title = element_blank(), panel.grid = element_blank(),
          plot.subtitle = element_text(face = "bold", size = 11), panel.border = element_rect(colour = "#888888", fill = NA, linewidth = 0.5))
  ggsave(file, p, width = w, height = h, dpi = 150, bg = "white"); file
}
stitch_row <- function(pngs, out, res = 150, pw = 6, ph = 6.7, title = NULL) {
  imgs <- lapply(pngs, png::readPNG)
  grDevices::png(out, width = pw * length(imgs) * res, height = ph * res, res = res); grid::grid.newpage()
  if (!is.null(title)) grid::grid.text(title, y = grid::unit(1, "npc") - grid::unit(3, "mm"), vjust = 1, gp = grid::gpar(fontface = "bold", fontsize = 15))
  grid::pushViewport(grid::viewport(y = 0, height = grid::unit(0.94, "npc"), just = "bottom", layout = grid::grid.layout(1, length(imgs))))
  for (i in seq_along(imgs)) { grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = i)); grid::grid.raster(imgs[[i]], name = paste0("im", i)); grid::popViewport() }
  grDevices::dev.off(); out
}
ground_raster <- function(bbox, dem) {
  if (!file.exists(TOPO_1893)) return(NULL)
  bb <- terra::as.polygons(terra::ext(bbox[1], bbox[3], bbox[2], bbox[4]), crs = "EPSG:4326")
  topo <- terra::project(terra::crop(terra::rast(TOPO_1893), terra::project(bb, terra::crs(terra::rast(TOPO_1893)))), "EPSG:26986", method = "bilinear")
  to_raster(terra::resample(topo, dem, method = "bilinear"))
}
# write an RGBA web overlay (4326) + return Leaflet bounds; alpha layer is 0/255
write_overlay <- function(R, G, B, A, slug, maxdim = 1100) {
  rgba <- terra::project(c(R, G, B, A), "EPSG:4326")
  f <- max(1, round(max(terra::ncol(rgba), terra::nrow(rgba)) / maxdim)); if (f > 1) rgba <- terra::aggregate(rgba, f, fun = "mean", na.rm = TRUE)
  rgba <- terra::ifel(is.na(rgba), 0, rgba)
  out <- file.path(DIR_WEB, paste0(slug, ".png"))
  terra::writeRaster(rgba, out, datatype = "INT1U", overwrite = TRUE, NAflag = NA)
  unlink(list.files(DIR_WEB, pattern = "\\.aux\\.xml$", full.names = TRUE))
  e <- terra::ext(rgba); c(e[3], e[1], e[4], e[2])  # ymin,xmin,ymax,xmax
}

AREAS <- list(
  list(slug = "prescott",  bbox = c(-72.336, 42.4255, -72.320, 42.4375), label = "Prescott Peninsula (north)", web = TRUE),
  list(slug = "dana",      bbox = c(-72.2925, 42.4262, -72.2765, 42.4368), label = "Dana Common",              web = TRUE),
  list(slug = "enfield",   bbox = c(-72.346, 42.305, -72.324, 42.322),   label = "Enfield (Winsor Dam)",       web = TRUE),
  # Greenwich's center is entirely under water now — a static "what drowned" panel only.
  list(slug = "greenwich", bbox = c(-72.307, 42.351, -72.287, 42.368),   label = "Greenwich (village site, now submerged)", web = FALSE)
)

manifest <- list()
for (a in AREAS) {
  tif <- fetch_massgis(a$bbox, file.path(DIR_CACHE, paste0("massgis_", a$slug, ".tif")))
  if (is.na(tif)) { msg("MassGIS unavailable for %s; skipping", a$slug); next }
  dem <- terra::rast(tif)[[1]]; demS <- terra::focal(dem, w = 3, fun = "mean", na.rm = TRUE)
  water <- dem <= WATER_LVL; e <- terra::ext(dem)
  slope <- terra::terrain(demS, "slope", unit = "degrees")
  L <- lrm(demS, K = 25); span <- as.numeric(stats::quantile(abs(terra::values(L)), 0.985, na.rm = TRUE))
  g <- relief_grey(demS, L, span)
  roads <- extract_lines(-L, 0.22, slope, 12, water, 80, 5, 40)
  walls <- extract_lines( L, 0.16, slope, 13, water, 70, 5, 35)

  # ---- static survey figure: 1893 ground-truth | relief ----
  base <- terra::clamp(g, 0, 1) * 255
  ras_relief <- to_raster(c(terra::ifel(water, wc[1], base), terra::ifel(water, wc[2], base), terra::ifel(water, wc[3], base)))
  g93 <- ground_raster(a$bbox, dem)
  tmpL <- file.path(tempdir(), paste0(a$slug, "_lrm.png")); render_one(ras_relief, sprintf("Today — %s, MassGIS 1 m LiDAR relief", a$label), e, tmpL)
  pngs <- tmpL
  if (!is.null(g93)) { tmp93 <- file.path(tempdir(), paste0(a$slug, "_93.png")); render_one(g93, "1893 survey (ground-truth)", e, tmp93); pngs <- c(tmp93, tmpL) }
  stitch_row(pngs, file.path(DIR_OUTPUT, paste0("24_", a$slug, "_survey.png")), title = sprintf("%s — what survives in the ground", a$label))

  # ---- web overlays: relief (transparent over water) + traces (land areas only) ----
  if (isTRUE(a$web)) {
    A <- terra::ifel(water | is.na(demS), 0, 235)
    bounds <- write_overlay(base, base, base, A, paste0("imprint_", a$slug))
    rc <- grDevices::col2rgb("#ff7b00"); wl <- grDevices::col2rgb("#1fb6a6")
    hasline <- (!is.na(roads)) | (!is.na(walls))
    tR <- terra::ifel(!is.na(walls), wl[1], 0); tG <- terra::ifel(!is.na(walls), wl[2], 0); tB <- terra::ifel(!is.na(walls), wl[3], 0)
    tR <- terra::ifel(!is.na(roads), rc[1], tR); tG <- terra::ifel(!is.na(roads), rc[2], tG); tB <- terra::ifel(!is.na(roads), rc[3], tB)
    tA <- terra::ifel(hasline, 255, 0)
    write_overlay(tR, tG, tB, tA, paste0("imprint_", a$slug, "_trace"))
    manifest[[length(manifest) + 1]] <- sprintf('  {"slug":"%s","label":"%s","bounds":[[%.6f,%.6f],[%.6f,%.6f]]}',
                                                a$slug, a$label, bounds[1], bounds[2], bounds[3], bounds[4])
    msg("imprints: %s done (relief + trace overlays, survey figure)", a$slug)
  } else {
    msg("imprints: %s done (static survey figure only — drowned)", a$slug)
  }
}
writeLines(c("[", paste(manifest, collapse = ",\n"), "]"), file.path(DIR_WEB, "imprints.json"))
msg("imprints stage complete; wrote %d areas to map/data/imprints.json", length(manifest))
