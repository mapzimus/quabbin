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
  bb <- c(-72.405, 42.285, -72.195, 42.515)   # fully contains Quabbin (N/E arms were truncated at the old box)
  latm <- mean(c(bb[2], bb[4]))
  wm <- (bb[3] - bb[1]) * cos(latm * pi / 180) * 111320; hm <- (bb[4] - bb[2]) * 111320
  # Size the export to stay under the ImageServer's ~2.8M-px cap (it 500s above ~3M);
  # never finer than 10 m. For this box mpp lands ~14 m, plenty for a reservoir outline.
  mpp <- max(10, ceiling(sqrt(wm * hm / 2.5e6)))
  dst <- file.path(DIR_CACHE, "massgis_reservoir.tif")
  if (!file.exists(dst) || file.size(dst) < 1e5) {
    w <- round(wm / mpp); h <- round(hm / mpp)
    url <- sprintf("%s?bbox=%f,%f,%f,%f&bboxSR=4326&size=%d,%d&imageSR=%d&format=tiff&pixelType=F32&interpolation=RSP_BilinearInterpolation&f=image",
                   MG_DEM, bb[1], bb[2], bb[3], bb[4], w, h, CRS_MA)
    ok <- FALSE; for (k in 1:5) { ok <- tryCatch({ download.file(url, dst, mode = "wb", quiet = TRUE); file.exists(dst) && file.size(dst) > 1e5 }, error = function(e) FALSE); if (ok) break; Sys.sleep(2 * k) }
    if (!ok) stop("MassGIS DEM unavailable")
  }
  dmg <- terra::rast(dst)[[1]]
  pat <- terra::patches(terra::ifel(dmg <= POOL_M, 1, NA), directions = 8, zeroAsNA = TRUE)
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

# --- Enforce dam containment ---------------------------------------------
# Winsor Dam (42.2967 N) and Goodnough Dike (42.2920 N) are the reservoir's true
# southern boundary. Even the MassGIS 10 m extraction above still leaks ~2 km^2 of
# below-dam land into the largest patch (the dams don't fully seal at 10 m), which
# is what drew water south of the dams onto Belchertown/Ware in earlier figures.
# Clip everything south of the dam line so no waterbody is ever drawn below the dams.
.dam <- rbind(c(-72.3370, 42.2967), c(-72.3000, 42.2920))   # Winsor Dam, Goodnough Dike
.dm  <- stats::lm(.dam[, 2] ~ .dam[, 1])
.aoi_ll <- st_bbox(st_transform(aoi_ma, CRS_LL))            # span the full AOI width (+ margin)
.xe  <- c(as.numeric(.aoi_ll["xmin"]) - 0.05, as.numeric(.aoi_ll["xmax"]) + 0.05)
.ye  <- as.numeric(coef(.dm)[1] + coef(.dm)[2] * .xe)
.south <- st_transform(st_sfc(st_polygon(list(rbind(
            cbind(.xe, .ye), c(.xe[2], 42.10), c(.xe[1], 42.10), c(.xe[1], .ye[1])))),
            crs = CRS_LL), CRS_MA)
.cl <- st_cast(st_make_valid(st_difference(st_geometry(reservoir_ma), st_geometry(.south))),
               "POLYGON", warn = FALSE)
if (length(.cl) == 0L) stop("dam-containment clip produced no polygons - check reservoir/clip geometry")
reservoir_ma <- st_sf(name = "Quabbin Reservoir",
                      geometry = st_sfc(.cl[which.max(as.numeric(st_area(.cl)))], crs = CRS_MA))

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
