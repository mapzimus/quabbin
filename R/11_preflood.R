# 11_preflood.R -----------------------------------------------------------
# Process the 1893 USGS Belchertown 15-minute quadrangle (pre-reservoir) into
# a web overlay: reproject to EPSG:4326, crop to the map neatline (drop the
# collar), downsample, and write map/data/preflood_topo.png + preflood.json
# (image + bounds) for a fade layer in the interactive map.
# Source: USGS Historical Topographic Map Collection (public domain).
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("CRS_LL")) source(file.path(QB_DIR, "R", "00_setup.R"))
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)

tif <- file.path(DIR_DATA, "cache", "preflood_belchertown_1893.tif")
url <- "https://prd-tnm.s3.amazonaws.com/StagedProducts/Maps/HistoricalTopo/GeoTIFF/MA/MA_Belchertown_352469_1893_62500_geo.tif"
if (!file.exists(tif)) {
  dir.create(dirname(tif), recursive = TRUE, showWarnings = FALSE)
  try(download.file(url, tif, mode = "wb", quiet = TRUE), silent = TRUE)
}
if (!file.exists(tif)) { msg("preflood: quad not available, skipping"); } else {

  r   <- terra::rast(tif)
  r84 <- terra::project(r, "EPSG:4326", method = "bilinear")

  # neatline of the 15' quad (drops the white collar + marginalia)
  nl   <- terra::ext(-72.50, -72.25, 42.25, 42.50)
  r84c <- terra::crop(r84, nl)

  # downsample for the browser (~1500 px wide)
  f <- floor(terra::ncol(r84c) / 1500)
  if (f > 1) r84c <- terra::aggregate(r84c, f, fun = "mean", na.rm = TRUE)

  # JPEG: far smaller than PNG for a scanned map
  jpg_out <- file.path(DIR_WEB, "preflood_topo.jpg")
  terra::writeRaster(r84c, jpg_out, filetype = "JPEG", datatype = "INT1U",
                     overwrite = TRUE, gdal = c("QUALITY=82"))
  unlink(c(file.path(DIR_WEB, "preflood_topo.png"),                 # drop heavy PNG if present
           list.files(DIR_WEB, pattern = "\\.aux\\.xml$", full.names = TRUE)))  # GDAL sidecars

  meta <- sprintf(
    '{"image":"preflood_topo.jpg","bounds":[[%.4f,%.4f],[%.4f,%.4f]],"year":1893,"source":"USGS Belchertown 15-minute quadrangle, 1:62,500 (Historical Topographic Map Collection)"}',
    42.25, -72.50, 42.50, -72.25)
  writeLines(meta, file.path(DIR_WEB, "preflood.json"))
  msg("wrote map/data/preflood_topo.jpg (%.2f MB) + preflood.json", file.size(jpg_out) / 1e6)
}
