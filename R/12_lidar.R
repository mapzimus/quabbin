# 12_lidar.R --------------------------------------------------------------
# LiDAR of what stayed above water. The reservoir's buildings were demolished
# and flooded, but two areas never went under -- Dana Common (the preserved
# Dana town centre, Quabbin Gate 40) and the Prescott Peninsula. USGS 3DEP
# 1 m bare-earth LiDAR over them still records the old commons, roads, stone
# walls, and cellar holes. We render a hillshade blended with a Local Relief
# Model (LRM = elevation minus its local mean), which strips the natural
# hillslope so micro-features pop: blue = local depressions (cellar holes, road
# cuts, ditches), red = local rises (walls, embankments, building platforms).
# Renders 14_dana_lidar.png, 15_prescott_lidar.png and land-only PNG overlays
# for the interactive map. Source: USGS 3DEP elevation service (public domain).
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("reservoir_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)

# Best-available 3DEP elevation (1 m LiDAR where it exists) for a bbox.
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

# Low-sun hillshade with a contrast stretch (terrain readability).
hillshade <- function(dem_m) {
  slp <- terra::terrain(dem_m, "slope",  unit = "radians")
  asp <- terra::terrain(dem_m, "aspect", unit = "radians")
  hs  <- terra::shade(slp, asp, angle = 30, direction = 315)
  qs  <- stats::quantile(terra::values(hs), c(0.02, 0.98), na.rm = TRUE)
  terra::clamp((hs - qs[1]) / (qs[2] - qs[1]), 0, 1)
}

# Depression depth from a Local Relief Model (elevation minus its local mean),
# denoised. Cellar holes / road cuts are local lows; under forest canopy the
# 1 m DTM is noisy, so we smooth and keep only depressions over a threshold.
pit_depth <- function(dem_m, win = 25) {
  lrm <- dem_m - terra::focal(dem_m, w = win, fun = "mean", na.rm = TRUE)
  lrm <- terra::focal(lrm, w = 3, fun = "mean", na.rm = TRUE)
  terra::clamp(-lrm, 0, 2)                                   # metres below local ground
}

# Composite a grey hillshade with a red highlight over real depressions.
hl_rgb <- function(hs, pit, thr = 0.45, span = 0.9, amax = 0.72) {
  a    <- terra::clamp((pit - thr) / span, 0, amax)
  base <- hs * 255; rc <- grDevices::col2rgb("#c1121f")[, 1]
  c(base * (1 - a) + rc[1] * a, base * (1 - a) + rc[2] * a, base * (1 - a) + rc[3] * a)
}

WATER_LVL <- POOL_M + 0.5
wc <- grDevices::col2rgb(WATER_FILL)[, 1]

sites <- list(
  list(web = "lidar_dana", file = "14_dana_lidar.png", w = 8, h = 8.4,
       bbox = c(-72.2853, 42.4267, -72.2713, 42.4367), size = "1150,1110", pt = c(-72.2783, 42.4317),
       title = "Dana Common in LiDAR",
       subtitle = "1 m bare-earth relief of the surviving Dana town site: cellar holes show as red pits, old roads and walls as lines in the hillshade"),
  list(web = "lidar_prescott", file = "15_prescott_lidar.png", w = 7, h = 8.6,
       bbox = c(-72.3400, 42.4180, -72.3160, 42.4450), size = "1500,1850", pt = c(-72.328, 42.431),
       title = "The Prescott Peninsula in LiDAR",
       subtitle = "1 m bare-earth relief of the land that stayed above water: cellar holes (red) and old road traces under the forest")
)

for (s in sites) {
  tif <- fetch_3dep(s$bbox, s$size, file.path(DIR_CACHE, paste0(s$web, ".tif")))
  if (is.na(tif)) { msg("3DEP unavailable for %s, skipping", s$web); next }

  dem   <- terra::project(terra::rast(tif), "EPSG:26986")
  demS  <- terra::focal(dem, w = 3, fun = "mean", na.rm = TRUE)   # denoise the 1 m DTM
  hs    <- hillshade(demS)
  pit   <- pit_depth(demS)
  slp   <- terra::terrain(demS, "slope", unit = "degrees")
  pit   <- terra::ifel(slp < 9, pit, 0)              # cellar holes sit on near-level ground, not slopes
  water <- dem <= WATER_LVL
  rgb   <- hl_rgb(hs, pit)

  # figure raster: blended relief on land, flat water colour on the reservoir
  Rf <- terra::ifel(water, wc[1], rgb[[1]]); Gf <- terra::ifel(water, wc[2], rgb[[2]]); Bf <- terra::ifel(water, wc[3], rgb[[3]])
  arr <- terra::as.array(c(Rf, Gf, Bf)) / 255; arr[is.na(arr)] <- 1
  ras <- grDevices::as.raster(arr); e <- terra::ext(dem)

  pt_ma <- st_transform(st_sfc(st_point(s$pt), crs = CRS_LL), CRS_MA)
  loc <- ggplot() +
    geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = NA) +
    geom_sf(data = pt_ma, colour = "#c1121f", size = 2) + theme_void()

  g <- ggplot() +
    annotation_raster(ras, xmin = e[1], xmax = e[2], ymin = e[3], ymax = e[4], interpolate = TRUE) +
    coord_sf(crs = st_crs(CRS_MA), xlim = c(e[1], e[2]), ylim = c(e[3], e[4]), datum = NA, expand = FALSE) +
    labs(title = s$title, subtitle = s$subtitle,
         caption = paste0("USGS 3DEP 1 m bare-earth LiDAR (public domain). Low-sun hillshade; ",
                          "depressions over ~0.5 m deep (cellar holes, road cuts) flagged in red. Reservoir in pale blue.")) +
    theme_quabbin() +
    theme(axis.text = element_blank(), axis.title = element_blank(), panel.grid = element_blank(),
          panel.border = element_rect(colour = "#888888", fill = NA, linewidth = 0.4))
  final <- g + patchwork::inset_element(loc, left = 0.0, bottom = 0.80, right = 0.19, top = 1.0, align_to = "panel")
  save_map(final, s$file, w = s$w, h = s$h)

  # --- web overlay: blended relief as RGBA PNG (transparent over water) ----
  alpha <- terra::ifel(water | is.na(hs), 0, 255)
  rgba  <- terra::project(c(rgb[[1]], rgb[[2]], rgb[[3]], alpha), "EPSG:4326")
  f <- max(1, round(terra::ncol(rgba) / 850)); if (f > 1) rgba <- terra::aggregate(rgba, f, fun = "mean", na.rm = TRUE)
  rgba <- terra::ifel(is.na(rgba), 0, rgba)
  png_out <- file.path(DIR_WEB, paste0(s$web, ".png"))
  terra::writeRaster(rgba, png_out, datatype = "INT1U", overwrite = TRUE)
  unlink(c(file.path(DIR_WEB, paste0(s$web, ".jpg")), list.files(DIR_WEB, pattern = "\\.aux\\.xml$", full.names = TRUE)))
  writeLines(sprintf('{"image":"%s.png","bounds":[[%.5f,%.5f],[%.5f,%.5f]],"source":"USGS 3DEP 1 m LiDAR bare earth (hillshade + local relief)"}',
                     s$web, s$bbox[2], s$bbox[1], s$bbox[4], s$bbox[3]),
             file.path(DIR_WEB, paste0(s$web, ".json")))
  msg("wrote %s + %s.png (%.2f MB)", s$file, s$web, file.size(png_out) / 1e6)
}

msg("lidar stage complete")
