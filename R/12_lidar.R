# 12_lidar.R --------------------------------------------------------------
# LiDAR of what stayed above water, paired with the 1893 map so it is legible.
# Two areas never went under: Dana Common (the preserved Dana town centre) and
# the Prescott Peninsula. For each we show a "then & now": the 1893 USGS village
# map and the 1 m bare-earth LiDAR of the *same ground*, at the same extent, with
# the former town centre marked on both -- so you can see where the roads, houses
# and common were, and what survives (or drowned) today. On the LiDAR a local
# relief model flags depressions (cellar holes, road cuts) in red. Also exports
# land-only LiDAR overlays for the interactive map.
# Sources: USGS 3DEP elevation + Historical Topographic Map Collection (public domain).
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("reservoir_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)

TOPO_1893 <- file.path(DIR_CACHE, "preflood_belchertown_1893.tif")  # fetched by 11_preflood.R

fetch_3dep <- function(bbox, size, dst) {
  if (!file.exists(dst)) {
    url <- sprintf(paste0("https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/",
                          "exportImage?bbox=%s&bboxSR=4326&size=%s&imageSR=4326&format=tiff&pixelType=F32&",
                          "interpolation=RSP_BilinearInterpolation&f=image"),
                   paste(bbox, collapse = ","), size)
    try(download.file(url, dst, mode = "wb", quiet = TRUE), silent = TRUE)
  }
  if (file.exists(dst)) dst else NA_character_
}

hillshade <- function(dem_m) {
  slp <- terra::terrain(dem_m, "slope", unit = "radians"); asp <- terra::terrain(dem_m, "aspect", unit = "radians")
  hs  <- terra::shade(slp, asp, angle = 30, direction = 315)
  qs  <- stats::quantile(terra::values(hs), c(0.02, 0.98), na.rm = TRUE)
  terra::clamp((hs - qs[1]) / (qs[2] - qs[1]), 0, 1)
}
pit_depth <- function(dem_m, win = 25) {
  lrm <- dem_m - terra::focal(dem_m, w = win, fun = "mean", na.rm = TRUE)
  terra::clamp(-terra::focal(lrm, w = 3, fun = "mean", na.rm = TRUE), 0, 2)
}
hl_rgb <- function(hs, pit, thr = 0.45, span = 0.9, amax = 0.72) {     # grey hillshade + red over depressions
  a <- terra::clamp((pit - thr) / span, 0, amax); base <- hs * 255; rc <- grDevices::col2rgb("#c1121f")[, 1]
  c(base * (1 - a) + rc[1] * a, base * (1 - a) + rc[2] * a, base * (1 - a) + rc[3] * a)
}
to_raster <- function(rgb3) { arr <- terra::as.array(rgb3) / 255; arr[is.na(arr)] <- 1; grDevices::as.raster(arr) }

WATER_LVL <- POOL_M + 0.5
wc <- grDevices::col2rgb(WATER_FILL)[, 1]

sites <- list(
  list(web = "lidar_dana", file = "14_dana_lidar.png", w = 11, h = 6.2,
       bbox = c(-72.2853, 42.4267, -72.2713, 42.4367), size = "1150,1110",
       pt = c(-72.2783, 42.4317), mark = "Dana Common",
       title = "Dana Common: where the village stood, and what survives",
       sub1 = "1893 — the village as surveyed: roads, houses and the common",
       sub2 = "Today — 1 m LiDAR relief (blue = now reservoir; red = cellar holes)"),
  list(web = "lidar_prescott", file = "15_prescott_lidar.png", w = 9.2, h = 7.6,
       bbox = c(-72.3400, 42.4180, -72.3160, 42.4450), size = "1500,1850",
       pt = c(-72.328, 42.431), mark = "Prescott (town)",
       title = "The Prescott Peninsula: the pre-flood roads, and the ground today",
       sub1 = "1893 — the peninsula's roads and farms before the flood",
       sub2 = "Today — 1 m LiDAR relief (blue = now reservoir; red = old dips)")
)

for (s in sites) {
  tif <- fetch_3dep(s$bbox, s$size, file.path(DIR_CACHE, paste0(s$web, ".tif")))
  if (is.na(tif)) { msg("3DEP unavailable for %s, skipping", s$web); next }

  dem   <- terra::project(terra::rast(tif), "EPSG:26986")
  demS  <- terra::focal(dem, w = 3, fun = "mean", na.rm = TRUE)
  hs    <- hillshade(demS)
  pit   <- pit_depth(demS)
  pit   <- terra::ifel(terra::terrain(demS, "slope", unit = "degrees") < 9, pit, 0)
  water <- dem <= WATER_LVL
  rgb   <- hl_rgb(hs, pit)
  Rf <- terra::ifel(water, wc[1], rgb[[1]]); Gf <- terra::ifel(water, wc[2], rgb[[2]]); Bf <- terra::ifel(water, wc[3], rgb[[3]])
  ras_lidar <- to_raster(c(Rf, Gf, Bf)); e <- terra::ext(dem)

  # the same ground on the 1893 map, resampled onto the LiDAR grid
  ras_1893 <- NULL
  if (file.exists(TOPO_1893)) {
    bb <- terra::as.polygons(terra::ext(s$bbox[1], s$bbox[3], s$bbox[2], s$bbox[4]), crs = "EPSG:4326")
    topo <- terra::project(terra::crop(terra::rast(TOPO_1893), terra::project(bb, terra::crs(terra::rast(TOPO_1893)))),
                           "EPSG:26986", method = "bilinear")
    ras_1893 <- to_raster(terra::resample(topo, dem, method = "bilinear"))
  }

  pt_ma <- st_transform(st_sfc(st_point(s$pt), crs = CRS_LL), CRS_MA); pxy <- st_coordinates(pt_ma)
  panel <- function(ras, sub) ggplot() +
    annotation_raster(ras, e[1], e[2], e[3], e[4], interpolate = TRUE) +
    annotate("segment", x = pxy[1], y = pxy[2] - diff(c(e[3], e[4])) * 0.06, xend = pxy[1], yend = pxy[2],
             colour = "black", linewidth = 0.4) +
    annotate("point", x = pxy[1], y = pxy[2], shape = 21, fill = "#ffd166", colour = "black", size = 3, stroke = 0.8) +
    annotate("label", x = pxy[1], y = pxy[2] - diff(c(e[3], e[4])) * 0.06, label = s$mark, vjust = 1.1,
             size = 2.9, fontface = "bold", fill = "#ffffffcc", label.size = 0) +
    coord_sf(crs = st_crs(CRS_MA), xlim = c(e[1], e[2]), ylim = c(e[3], e[4]), datum = NA, expand = FALSE) +
    labs(subtitle = sub) + theme_quabbin() +
    theme(axis.text = element_blank(), axis.title = element_blank(), panel.grid = element_blank(),
          plot.subtitle = element_text(face = "bold", size = 9.5),
          panel.border = element_rect(colour = "#888888", fill = NA, linewidth = 0.4))

  left  <- if (is.null(ras_1893)) NULL else panel(ras_1893, s$sub1)
  right <- panel(ras_lidar, s$sub2)
  out <- (if (is.null(left)) right else (left | right)) +
    plot_annotation(title = s$title,
      caption = "Left: USGS Belchertown 15' quad, 1893. Right: USGS 3DEP 1 m bare-earth LiDAR. Same extent; public domain.",
      theme = theme_quabbin())
  save_map(out, s$file, w = s$w, h = s$h)

  # --- web overlay: blended relief as RGBA PNG (transparent over water) ----
  alpha <- terra::ifel(water | is.na(hs), 0, 255)
  rgba  <- terra::project(c(rgb[[1]], rgb[[2]], rgb[[3]], alpha), "EPSG:4326")
  f <- max(1, round(terra::ncol(rgba) / 850)); if (f > 1) rgba <- terra::aggregate(rgba, f, fun = "mean", na.rm = TRUE)
  rgba <- terra::ifel(is.na(rgba), 0, rgba)
  png_out <- file.path(DIR_WEB, paste0(s$web, ".png"))
  terra::writeRaster(rgba, png_out, datatype = "INT1U", overwrite = TRUE)
  unlink(c(file.path(DIR_WEB, paste0(s$web, ".jpg")), list.files(DIR_WEB, pattern = "\\.aux\\.xml$", full.names = TRUE)))
  writeLines(sprintf('{"image":"%s.png","bounds":[[%.5f,%.5f],[%.5f,%.5f]],"source":"USGS 3DEP 1 m LiDAR bare earth"}',
                     s$web, s$bbox[2], s$bbox[1], s$bbox[4], s$bbox[3]),
             file.path(DIR_WEB, paste0(s$web, ".json")))
  msg("wrote %s + %s.png (%.2f MB)", s$file, s$web, file.size(png_out) / 1e6)
}

msg("lidar stage complete")
