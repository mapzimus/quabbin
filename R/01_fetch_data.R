# 01_fetch_data.R ---------------------------------------------------------
# Pull every open-data layer for the study and cache it under data/cache/.
# Each source is wrapped in tryCatch so a single unreachable endpoint never
# kills the run -- it degrades to a documented fallback instead.
#   1. DEM ............ elevatr  -> AWS Terrain Tiles
#   2. Reservoir ...... osmdata  -> OpenStreetMap (fallback: derive from DEM)
#   3. Modern towns ... tigris   -> Census TIGER  (fallback: direct cb download)
#   4. Watershed ...... USGS Watershed Boundary Dataset REST (optional)
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("CRS_MA")) source(file.path(QB_DIR, "R", "00_setup.R"))

# 1. DIGITAL ELEVATION MODEL ----------------------------------------------
dem_path <- file.path(DIR_CACHE, "dem_ll.tif")
if (file.exists(dem_path)) {
  dem_ll <- terra::rast(dem_path); msg("DEM: loaded from cache")
} else {
  dem_ll <- tryCatch({
    r <- elevatr::get_elev_raster(locations = st_sf(geometry = aoi_ll),
                                  z = 11, clip = "locations", verbose = FALSE)
    r <- terra::rast(r)
    names(r) <- "elev"
    terra::writeRaster(r, dem_path, overwrite = TRUE)
    msg("DEM: downloaded via elevatr (AWS Terrain Tiles, z=11)")
    r
  }, error = function(e) { msg("DEM fetch FAILED: %s", conditionMessage(e)); NULL })
}

# 2. RESERVOIR POLYGON -----------------------------------------------------
# Default is DEM-derived (RESERVOIR_METHOD, see 00_setup); the OSM path is
# opt-in and guarded by a fast probe so it never hangs on a rate-limited or
# IP-blocked Overpass server. If reservoir stays NULL it is carved from the
# DEM in 02_build_layers.R.
res_path  <- file.path(DIR_CACHE, "reservoir.gpkg")
reservoir <- NULL
if (RESERVOIR_METHOD == "osm" && file.exists(res_path)) {
  reservoir <- st_read(res_path, quiet = TRUE); msg("Reservoir: loaded OSM cache")
} else if (RESERVOIR_METHOD == "osm") {
  op_ok <- tryCatch(
    isTRUE(curl::curl_fetch_memory("https://overpass-api.de/api/status")$status_code == 200),
    error = function(e) FALSE)
  if (!op_ok) {
    msg("Overpass not reachable - reservoir will be DEM-derived")
  } else {
    reservoir <- tryCatch({
      q <- osmdata::opq(bbox = unname(AOI_BBOX[c("xmin","ymin","xmax","ymax")]), timeout = 50) |>
           osmdata::add_osm_feature(key = "natural", value = "water")
      d <- osmdata::osmdata_sf(q)
      water <- dplyr::bind_rows(
        if (!is.null(d$osm_polygons))      d$osm_polygons[, "name"]      else NULL,
        if (!is.null(d$osm_multipolygons)) d$osm_multipolygons[, "name"] else NULL)
      water <- st_make_valid(water[!st_is_empty(water), ])
      qsel  <- water[grepl("Quabbin", water$name, ignore.case = TRUE) %in% TRUE, ]
      if (nrow(qsel) == 0) { water$area <- as.numeric(st_area(water)); qsel <- water[which.max(water$area), ] }
      qsel <- st_make_valid(qsel)
      st_write(qsel, res_path, quiet = TRUE, delete_dsn = TRUE)
      msg("Reservoir: OSM natural=water (%d feature[s])", nrow(qsel)); qsel
    }, error = function(e) { msg("Reservoir OSM fetch failed (%s) - using DEM", conditionMessage(e)); NULL })
  }
} else {
  msg("Reservoir: DEM-derived from the %d ft full pool (RESERVOIR_METHOD='dem')", POOL_FT)
}

# 3. MODERN MASSACHUSETTS MUNICIPALITIES ----------------------------------
towns_path <- file.path(DIR_CACHE, "ma_towns.gpkg")
if (file.exists(towns_path)) {
  ma_towns <- st_read(towns_path, quiet = TRUE); msg("Towns: loaded from cache")
} else {
  ma_towns <- tryCatch({
    options(tigris_use_cache = TRUE)
    t <- tigris::county_subdivisions(state = "MA", cb = TRUE, year = 2021, progress_bar = FALSE)
    t <- st_make_valid(t)
    st_write(t, towns_path, quiet = TRUE, delete_dsn = TRUE)
    msg("Towns: tigris county_subdivisions MA cb-2021 (%d features)", nrow(t))
    t
  }, error = function(e) {
    msg("tigris FAILED (%s) - trying direct TIGER download", conditionMessage(e))
    tryCatch({
      url <- "https://www2.census.gov/geo/tiger/GENZ2021/shp/cb_2021_25_cousub_500k.zip"
      zf  <- file.path(DIR_CACHE, "cb_ma_cousub.zip")
      utils::download.file(url, zf, mode = "wb", quiet = TRUE)
      t <- st_make_valid(st_read(paste0("/vsizip/", zf), quiet = TRUE))
      st_write(t, towns_path, quiet = TRUE, delete_dsn = TRUE)
      msg("Towns: direct TIGER cb download (%d features)", nrow(t))
      t
    }, error = function(e2) { msg("Towns fetch FAILED: %s", conditionMessage(e2)); NULL })
  })
}

# 4. WATERSHED (USGS WBD HUC-10, optional) --------------------------------
# Open-data proxy for the protected catchment. The exact DCR Quabbin watershed
# is a MassGIS layer; the reachable USGS WBD HUC-10s intersecting the reservoir
# are a reasonable public stand-in. Skipped gracefully if the service is down.
ws_path <- file.path(DIR_CACHE, "watershed.gpkg")
if (file.exists(ws_path)) {
  watershed <- st_read(ws_path, quiet = TRUE); msg("Watershed: loaded from cache")
} else {
  watershed <- tryCatch({
    bb  <- AOI_BBOX
    env <- sprintf("%f,%f,%f,%f", bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"])
    # WBD MapServer layer 5 = HUC-10 (10-digit hydrologic units); geojson out.
    url <- paste0(
      "https://hydro.nationalmap.gov/arcgis/rest/services/wbd/MapServer/5/query",  # layer 5 = HUC-10
      "?geometry=", utils::URLencode(env, reserved = TRUE),
      "&geometryType=esriGeometryEnvelope&inSR=4326&outSR=4326",
      "&spatialRel=esriSpatialRelIntersects&outFields=name,huc10",
      "&returnGeometry=true&f=geojson")
    w <- st_read(url, quiet = TRUE)
    w <- st_make_valid(w[!st_is_empty(w), ])
    stopifnot(nrow(w) > 0)
    st_write(w, ws_path, quiet = TRUE, delete_dsn = TRUE)
    msg("Watershed: USGS WBD HUC-10 (%d unit[s] in window)", nrow(w))
    w
  }, error = function(e) {
    msg("Watershed fetch unavailable (%s) - watershed map will be skipped", conditionMessage(e))
    NULL
  })
}

msg("fetch stage complete")
