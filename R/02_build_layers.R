# 02_build_layers.R -------------------------------------------------------
# Turn the raw downloads into analysis-ready layers, all in EPSG:26986:
#   - reproject + hillshade the DEM
#   - resolve the reservoir (OSM polygon, or carved from the DEM pool level)
#   - the four drowned towns as points
#   - modern municipalities clipped to the area, plus a MA state outline
# Objects are left in memory for 03/04 and also written to data/cache/.
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("CRS_MA")) source(file.path(QB_DIR, "R", "00_setup.R"))
if (!exists("dem_ll")) source(file.path(QB_DIR, "R", "01_fetch_data.R"))

stopifnot("DEM is required but was not fetched" = !is.null(dem_ll))

# --- DEM -> Massachusetts Mainland metres, then hillshade -----------------
dem_ma <- terra::project(dem_ll, sprintf("EPSG:%d", CRS_MA), method = "bilinear")
names(dem_ma) <- "elev"

slp  <- terra::terrain(dem_ma, "slope",  unit = "radians")
asp  <- terra::terrain(dem_ma, "aspect", unit = "radians")
hill <- terra::shade(slp, asp, angle = 40, direction = 315)
names(hill) <- "shade"

terra::writeRaster(dem_ma, file.path(DIR_CACHE, "dem_ma.tif"),       overwrite = TRUE)
terra::writeRaster(hill,   file.path(DIR_CACHE, "hillshade_ma.tif"), overwrite = TRUE)
msg("DEM reprojected to EPSG:%d and hillshaded (%d x %d cells)", CRS_MA, nrow(dem_ma), ncol(dem_ma))

# --- Reservoir ------------------------------------------------------------
# The coarse regional DEM (elevatr) can't resolve Winsor Dam / Goodnough Dike, so
# a naive "largest area below the 530 ft pool" leaks south past the dams into the
# dry lowlands around Belchertown & Ware. Derive the real footprint from MassGIS
# 1 m LiDAR (downsampled to 10 m here), which DOES resolve the dams: the largest
# contiguous body at/below the pool is the basin, cleanly cut off from downstream.
MG_DEM <- "https://arcgisserver.digital.mass.gov/arcgisserver/rest/services/LiDAR/DEM_lidar_2013to2021_32bitFloat/ImageServer/exportImage"
reservoir_true <- tryCatch({
  bb <- c(-72.400, 42.285, -72.275, 42.465); mpp <- 10
  dst <- file.path(DIR_CACHE, "massgis_reservoir10m.tif")
  if (!file.exists(dst) || file.size(dst) < 1e5) {
    latm <- mean(c(bb[2], bb[4]))
    w <- round((bb[3] - bb[1]) * cos(latm * pi / 180) * 111320 / mpp); h <- round((bb[4] - bb[2]) * 111320 / mpp)
    url <- sprintf("%s?bbox=%f,%f,%f,%f&bboxSR=4326&size=%d,%d&imageSR=%d&format=tiff&pixelType=F32&interpolation=RSP_BilinearInterpolation&f=image",
                   MG_DEM, bb[1], bb[2], bb[3], bb[4], w, h, CRS_MA)
    ok <- FALSE; for (k in 1:5) { ok <- tryCatch({ download.file(url, dst, mode = "wb", quiet = TRUE); file.exists(dst) && file.size(dst) > 1e5 }, error = function(e) FALSE); if (ok) break; Sys.sleep(2 * k) }
    if (!ok) stop("MassGIS DEM unavailable")
  }
  d10 <- terra::rast(dst)[[1]]
  pat <- terra::patches(terra::ifel(d10 <= POOL_M, 1, NA), directions = 8, zeroAsNA = TRUE)
  fr  <- terra::freq(pat); big <- fr$value[which.max(fr$count)]
  pp  <- sf::st_as_sf(terra::as.polygons(terra::ifel(pat == big, 1, NA), dissolve = TRUE))
  st_simplify(st_make_valid(st_union(st_geometry(pp))), dTolerance = 15)
}, error = function(e) { msg("  reservoir: MassGIS unavailable (%s); using coarse-DEM carve", conditionMessage(e)); NULL })

if (!is.null(reservoir_true)) {
  reservoir_ma <- st_sf(name = "Quabbin Reservoir", geometry = st_sfc(reservoir_true, crs = CRS_MA))
  RES_SRC <- "MassGIS LiDAR (dam-contained, <= 530 ft pool)"
} else if (is.null(reservoir)) {
  wmask <- terra::ifel((dem_ma <= POOL_M) == 1, 1, NA)
  rp    <- st_make_valid(suppressWarnings(st_cast(sf::st_as_sf(terra::as.polygons(wmask, dissolve = TRUE)), "POLYGON")))
  rp$area <- as.numeric(st_area(rp)); reservoir_ma <- rp[which.max(rp$area), ]
  RES_SRC <- sprintf("DEM-derived (<= %d ft full pool)", POOL_FT)
} else {
  reservoir_ma <- st_make_valid(st_transform(reservoir, CRS_MA)); RES_SRC <- "OpenStreetMap (natural=water)"
}
# Clip to AOI and dissolve to a single waterbody.
reservoir_ma <- st_intersection(st_union(st_geometry(reservoir_ma)), st_geometry(aoi_ma))
reservoir_ma <- st_sf(name = "Quabbin Reservoir", geometry = st_sfc(reservoir_ma, crs = CRS_MA))
st_write(reservoir_ma, file.path(DIR_CACHE, "reservoir_ma.gpkg"), quiet = TRUE, delete_dsn = TRUE)
msg("Reservoir source: %s", RES_SRC)

# --- The four drowned towns (bundled, cited) ------------------------------
towns_df <- utils::read.csv(file.path(DIR_DATA, "drowned_towns.csv"),
                            stringsAsFactors = FALSE)
drowned <- st_transform(
  st_as_sf(towns_df, coords = c("lon", "lat"), crs = CRS_LL), CRS_MA)
msg("Drowned towns: %s", paste(drowned$town, collapse = ", "))

# --- Modern municipalities + state outline --------------------------------
towns_aoi <- state_ma <- NULL
if (!is.null(ma_towns)) {
  towns_ma  <- st_make_valid(st_transform(ma_towns, CRS_MA))
  state_ma  <- st_union(st_geometry(towns_ma))
  towns_aoi <- suppressWarnings(st_crop(towns_ma, st_bbox(aoi_ma)))
  msg("Municipalities prepared (%d in study window)", nrow(towns_aoi))
}

# --- Watershed (optional): HUC-10 units overlapping the reservoir ----------
watershed_ma <- NULL
if (!is.null(watershed)) {
  ws  <- st_make_valid(st_transform(watershed, CRS_MA))
  hit <- lengths(st_intersects(ws, reservoir_ma)) > 0
  if (any(hit)) ws <- ws[hit, ]
  watershed_ma <- st_sf(geometry = st_union(st_geometry(ws)))
  msg("Watershed: %d HUC-10 unit(s) overlap the reservoir", nrow(ws))
}

msg("layer-build stage complete")
