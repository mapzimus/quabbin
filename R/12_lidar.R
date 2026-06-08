# 12_lidar.R --------------------------------------------------------------
# LiDAR of what stayed above water. The reservoir's buildings were demolished
# and flooded, but two areas never went under -- Dana Common (the preserved
# Dana town centre, Quabbin Gate 40) and the Prescott Peninsula. USGS 3DEP
# 1 m bare-earth LiDAR over them still shows old commons, road traces, stone
# walls, and cellar holes. Renders 14_dana_lidar.png, 15_prescott_lidar.png and
# exports land-only hillshades (transparent over water) for the interactive map.
# Source: USGS 3DEP dynamic elevation service (public domain).
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

# Low-sun hillshade with a contrast stretch -- brings out subtle relief
# (road cuts, cellar holes) that a flat overhead/averaged shade washes out.
hillshade <- function(dem_m) {
  slp <- terra::terrain(dem_m, "slope",  unit = "radians")
  asp <- terra::terrain(dem_m, "aspect", unit = "radians")
  hs  <- terra::shade(slp, asp, angle = 28, direction = 315)
  qs  <- stats::quantile(terra::values(hs), c(0.02, 0.98), na.rm = TRUE)
  terra::clamp((hs - qs[1]) / (qs[2] - qs[1]), 0, 1)
}

WATER_LVL <- POOL_M + 0.5   # cells at/below the full pool read as reservoir

sites <- list(
  list(web = "lidar_dana", file = "14_dana_lidar.png", w = 8, h = 8,
       bbox = c(-72.2853, 42.4267, -72.2713, 42.4367), size = "1150,1110", pt = c(-72.2783, 42.4317),
       title = "Dana Common in LiDAR",
       subtitle = "Bare-earth LiDAR of the Dana town site, a point of land above the reservoir: old road traces and cellar holes survive in the relief"),
  list(web = "lidar_prescott", file = "15_prescott_lidar.png", w = 7, h = 8.6,
       bbox = c(-72.3400, 42.4180, -72.3160, 42.4450), size = "1500,1850", pt = c(-72.328, 42.431),
       title = "The Prescott Peninsula in LiDAR",
       subtitle = "The part of Prescott that stayed above water: old road traces and foundations in 1 m bare-earth LiDAR")
)

for (s in sites) {
  tif <- fetch_3dep(s$bbox, s$size, file.path(DIR_CACHE, paste0(s$web, ".tif")))
  if (is.na(tif)) { msg("3DEP unavailable for %s, skipping", s$web); next }

  dem   <- terra::project(terra::rast(tif), "EPSG:26986")   # to metres for correct terrain
  hs    <- hillshade(dem)
  water <- dem <= WATER_LVL
  hs_land <- terra::ifel(water, NA, hs)                      # hillshade on land only

  hdf <- terra::as.data.frame(hs_land, xy = TRUE, na.rm = TRUE); names(hdf) <- c("x", "y", "z")
  wdf <- terra::as.data.frame(terra::ifel(water, 1, NA), xy = TRUE, na.rm = TRUE); names(wdf) <- c("x", "y", "w")

  pt_ma <- st_transform(st_sfc(st_point(s$pt), crs = CRS_LL), CRS_MA)
  loc <- ggplot() +
    geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = NA) +
    geom_sf(data = pt_ma, colour = "#c1121f", size = 2) +
    theme_void()

  g <- ggplot() +
    geom_raster(data = wdf, aes(x, y), fill = WATER_FILL) +
    geom_raster(data = hdf, aes(x, y, fill = z), show.legend = FALSE) +
    scale_fill_gradient(low = "#3a3a3a", high = "#fbfbfb") +
    coord_sf(crs = st_crs(CRS_MA), datum = NA, expand = FALSE) +
    labs(title = s$title, subtitle = s$subtitle,
         caption = "USGS 3DEP 1 m bare-earth LiDAR (public domain). Low-sun hillshade (NW); reservoir shown in blue.") +
    theme_quabbin() +
    theme(axis.text = element_blank())
  final <- g + patchwork::inset_element(loc, left = 0.0, bottom = 0.78, right = 0.2, top = 1.0, align_to = "panel")
  save_map(final, s$file, w = s$w, h = s$h)

  # --- web overlay: land-only grey hillshade as RGBA PNG (transparent water) ---
  hl <- terra::project(hs, "EPSG:4326")
  wl <- terra::project(terra::ifel(water, 1, 0), "EPSG:4326")
  f  <- floor(terra::ncol(hl) / 1000); if (f > 1) { hl <- terra::aggregate(hl, f, fun = "mean", na.rm = TRUE); wl <- terra::aggregate(wl, f, fun = "mean", na.rm = TRUE) }
  g8  <- terra::ifel(is.na(hl), 255, hl * 255)
  alpha <- terra::ifel(is.na(hl) | wl > 0.5, 0, 255)
  rgba <- c(g8, g8, g8, alpha)
  png_out <- file.path(DIR_WEB, paste0(s$web, ".png"))
  terra::writeRaster(rgba, png_out, datatype = "INT1U", overwrite = TRUE)
  unlink(c(file.path(DIR_WEB, paste0(s$web, ".jpg")),
           list.files(DIR_WEB, pattern = "\\.aux\\.xml$", full.names = TRUE)))
  writeLines(sprintf('{"image":"%s.png","bounds":[[%.5f,%.5f],[%.5f,%.5f]],"source":"USGS 3DEP 1 m LiDAR bare earth"}',
                     s$web, s$bbox[2], s$bbox[1], s$bbox[4], s$bbox[3]),
             file.path(DIR_WEB, paste0(s$web, ".json")))
  msg("wrote %s + %s.png (%.2f MB)", s$file, s$web, file.size(png_out) / 1e6)
}

msg("lidar stage complete")
