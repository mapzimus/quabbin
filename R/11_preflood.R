# 11_preflood.R -----------------------------------------------------------
# Historical USGS topographic overlays for the explorer. Each era is a mosaic
# of the quadrangles that cover the valley, clipped to their neatlines (drop
# the white collar + marginalia, and form a clean seam between sheets),
# reprojected to EPSG:4326, cropped to the reservoir window and written as a
# web JPEG. Writes map/data/hist_<key>.jpg + a histmaps.json manifest the
# explorer reads to offer a year selector.
#
# One 15' quad only covers half the valley, so each era is two sheets:
#   1890s  Belchertown 1893 (west) + Barre 1894 (east)            1:62,500 15'
#   1940s  Winsor Dam 1944 (south) + Quabbin Reservoir 1944 (north) 1:31,680 7.5'
# The 1940s sheets are 7.5' quads (~2x the detail) -- the better road reference,
# mapped as the valley was being taken.
# Source: USGS Historical Topographic Map Collection (public domain).
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("CRS_LL")) source(file.path(QB_DIR, "R", "00_setup.R"))
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)
HTMC <- "https://prd-tnm.s3.amazonaws.com/StagedProducts/Maps/HistoricalTopo/GeoTIFF/MA/"

# Each sheet: the HTMC file, and the lon/lat box to clip it to (its neatline,
# split at the shared seam so adjacent sheets meet without overlapping collars).
ERAS <- list(
  list(key = "1890s", year = 1893, label = "1890s survey", maxw = 1900, desat = 0,
       source = "USGS 15' quadrangles: Belchertown 1893 + Barre 1894 (1:62,500)",
       sheets = list(
         list(file = "MA_Belchertown_352469_1893_62500_geo.tif", clip = c(-72.55, -72.250, 42.25, 42.50)),
         list(file = "MA_Barre_352447_1894_62500_geo.tif",       clip = c(-72.250, -71.95, 42.25, 42.50)))),
  list(key = "1940s", year = 1944, label = "1940s survey", maxw = 2200, desat = 0.5,
       source = "USGS 7.5' quadrangles: Winsor Dam + Quabbin Reservoir 1944 (1:31,680)",
       sheets = list(
         list(file = "MA_Winsor Dam_352383_1944_31680_geo.tif",       clip = c(-72.375, -72.250, 42.250, 42.375)),
         list(file = "MA_Quabbin Reservoir_352110_1944_31680_geo.tif", clip = c(-72.375, -72.250, 42.375, 42.500)))))

AOI_CROP <- terra::ext(-72.46, -72.18, 42.25, 42.52)   # the reservoir window (a hair beyond the water)

dl <- function(file) {                                 # cached download of one HTMC sheet
  dst <- file.path(DIR_CACHE, paste0("htmc_", gsub("[^A-Za-z0-9]", "_", file)))
  if (!file.exists(dst) || file.size(dst) < 1e5) {
    url <- paste0(HTMC, utils::URLencode(file))
    ok <- FALSE
    for (k in 1:5) { ok <- tryCatch({ download.file(url, dst, mode = "wb", quiet = TRUE); file.exists(dst) && file.size(dst) > 1e5 }, error = function(e) FALSE); if (ok) break; Sys.sleep(2 * k) }
  }
  if (file.exists(dst) && file.size(dst) > 1e5) dst else NA_character_
}

prep <- function(sheet) {                              # -> sheet clipped to its neatline, in EPSG:4326 (RGB)
  tif <- dl(sheet$file); if (is.na(tif)) return(NULL)
  r <- terra::rast(tif); if (terra::nlyr(r) >= 3) r <- r[[1:3]]
  r84 <- terra::project(r, "EPSG:4326", method = "bilinear")
  terra::crop(r84, terra::ext(sheet$clip), snap = "out")
}

# Harmonize sheets within an era: optionally desaturate toward grey (tames a
# strong colour clash between sheets), then match each sheet's per-channel mean
# to the era's mean so the tonal seam between adjacent sheets fades.
harmonize <- function(parts, desat = 0) {
  if (desat > 0) parts <- lapply(parts, function(p) {
    if (terra::nlyr(p) < 3) return(p)
    g <- 0.299 * p[[1]] + 0.587 * p[[2]] + 0.114 * p[[3]]
    for (b in 1:3) p[[b]] <- (1 - desat) * p[[b]] + desat * g
    p
  })
  if (length(parts) >= 2) {
    mns <- t(vapply(parts, function(p) as.numeric(terra::global(p, "mean", na.rm = TRUE)[, 1]), numeric(terra::nlyr(parts[[1]]))))
    tgt <- colMeans(mns)
    parts <- lapply(seq_along(parts), function(i) { p <- parts[[i]]; off <- tgt - mns[i, ]
      for (b in seq_len(terra::nlyr(p))) p[[b]] <- terra::clamp(p[[b]] + off[b], 0, 255); p })
  }
  parts
}

entries <- character(0)
for (era in ERAS) {
  parts <- Filter(Negate(is.null), lapply(era$sheets, prep))
  if (!length(parts)) { msg("hist %s: no sheets available, skipping", era$key); next }
  parts <- harmonize(parts, era$desat)
  # resample every part onto one grid (the finest part's resolution over the union) so they merge cleanly
  res0 <- terra::res(parts[[which.min(vapply(parts, function(p) terra::res(p)[1], numeric(1)))]])
  un   <- Reduce(terra::union, lapply(parts, terra::ext))
  tmpl <- terra::rast(un, resolution = res0, crs = "EPSG:4326")
  mos  <- Reduce(terra::cover, lapply(parts, function(p) terra::resample(p, tmpl, method = "bilinear")))
  mos  <- terra::trim(terra::crop(mos, AOI_CROP))      # to the reservoir window, then drop NA margins
  terra::writeRaster(mos, file.path(DIR_CACHE, sprintf("histmos_%s.tif", era$key)), overwrite = TRUE)  # full-res mosaic, reused by 13_roads
  f <- floor(terra::ncol(mos) / era$maxw); if (f > 1) mos <- terra::aggregate(mos, f, fun = "mean", na.rm = TRUE)
  jpg <- file.path(DIR_WEB, paste0("hist_", era$key, ".jpg"))
  terra::writeRaster(mos, jpg, filetype = "JPEG", datatype = "INT1U", overwrite = TRUE, gdal = c("QUALITY=85"))
  unlink(list.files(DIR_WEB, pattern = "\\.aux\\.xml$", full.names = TRUE))
  e <- terra::ext(mos)
  entries <- c(entries, sprintf(
    '  {"key":"%s","label":"%s","year":%d,"image":"hist_%s.jpg","bounds":[[%.4f,%.4f],[%.4f,%.4f]],"source":"%s"}',
    era$key, era$label, era$year, era$key, e[3], e[1], e[4], e[2], era$source))
  msg("hist %s: wrote map/data/hist_%s.jpg (%.2f MB), bounds lat %.3f..%.3f lon %.3f..%.3f",
      era$key, era$key, file.size(jpg) / 1e6, e[3], e[4], e[1], e[2])
}

if (length(entries)) {
  writeLines(c("[", paste(entries, collapse = ",\n"), "]"), file.path(DIR_WEB, "histmaps.json"))
  msg("wrote map/data/histmaps.json (%d era[s])", length(entries))
} else msg("hist: nothing written (HTMC unreachable?)")
