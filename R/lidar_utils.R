# lidar_utils.R -----------------------------------------------------------
# Shared helpers for the LiDAR stages (14-16): the imprint survey, the 1893
# cross-reference and the full-reservoir ghost relief grew from the same
# rendering chain, so the common pieces live here once. Each stage sources
# this file right after its 00_setup guard -- the water constants below need
# POOL_M and WATER_FILL from 00_setup.R. (12_lidar.R keeps its own, different,
# single-direction hillshade/pit helpers; 02_build_layers.R keeps its inline
# 10 m MassGIS fetch, which uses a different retry count.)
# -------------------------------------------------------------------------

# MassGIS 1 m bare-earth LiDAR DEM (2013-2021, 32-bit float) export endpoint.
MG <- "https://arcgisserver.digital.mass.gov/arcgisserver/rest/services/LiDAR/DEM_lidar_2013to2021_32bitFloat/ImageServer/exportImage"

# Cells at/below half a metre over the full pool render as water, in the
# study's water-fill colour (as an RGB triplet for raster painting).
WATER_LVL <- POOL_M + 0.5
wc <- grDevices::col2rgb(WATER_FILL)[, 1]

# 3-band 0-255 SpatRaster -> plain raster for annotation_raster(); NA -> white.
to_raster <- function(rgb3) { arr <- terra::as.array(rgb3) / 255; arr[is.na(arr)] <- 1; grDevices::as.raster(arr) }

# Local Relief Model: elevation minus its local mean over a K-cell window.
# K is required -- the stages tune it (14/15 use 25; 16 uses 13 for fine detail).
lrm <- function(d, K) d - terra::focal(d, w = K, fun = "mean", na.rm = TRUE)

# Multi-direction (8-azimuth) hillshade, contrast-stretched around mid-grey.
mdow <- function(dem, angle = 35) {
  slp <- terra::terrain(dem, "slope", unit = "radians"); asp <- terra::terrain(dem, "aspect", unit = "radians")
  hs <- Reduce(`+`, lapply(seq(0, 315, 45), function(a) terra::shade(slp, asp, angle = angle, direction = a))) / 8
  terra::clamp((hs - 0.5) * 1.6 + 0.5, 0, 1)
}

# Composite relief: the hillshade darkened in negative relief (cuts) and
# lightened in positive relief (banks), scaled by the LRM span.
relief_grey <- function(demS, L, span) {
  hs <- mdow(demS); neg <- terra::clamp(-L / span, 0, 1); pos <- terra::clamp(L / span, 0, 1)
  terra::clamp(hs * (1 - 0.5 * neg) + 0.32 * pos * (1 - hs), 0, 1)
}

# Connected-component line filter: keep only components of a 1/NA mask that are
# big (>= Nmin cells), elongated (>= Emin) and long (>= Lmin map units).
linfilter <- function(mask, Nmin, Emin, Lmin) {
  p <- terra::patches(mask, directions = 8, zeroAsNA = TRUE)
  v <- terra::values(p)[, 1]; cells <- which(!is.na(v)); if (!length(cells)) return(p * NA)
  ids <- v[cells]; xy <- terra::xyFromCell(p, cells); spl <- split(as.data.frame(xy), ids)
  sizes <- vapply(spl, nrow, integer(1))
  st <- lapply(spl, function(z) { if (nrow(z) < 8) return(c(0, 0)); ev <- eigen(stats::cov(z), only.values = TRUE)$values
    c(sqrt(max(ev) / max(min(ev), 1e-4)), sqrt(max(ev)) * 3.5) })
  el <- vapply(st, `[`, numeric(1), 1); ln <- vapply(st, `[`, numeric(1), 2)
  keep <- as.numeric(names(sizes)[sizes >= Nmin & el >= Emin & ln >= Lmin])
  if (length(keep)) terra::subst(p, keep, 1, others = NA) else p * NA
}
# Linear relief features: threshold the signed LRM on gentle, dry ground, then
# keep the elongated components (roads/paths from -L, walls/banks from +L).
extract_lines <- function(signed, thr, slope, slopemax, water, Nmin, Emin, Lmin)
  linfilter(terra::ifel(signed > thr & slope < slopemax & !water, 1, NA), Nmin, Emin, Lmin)

# MassGIS exportImage URL for a lon/lat bbox at ~mpp metres/pixel, clamped to
# the server's ~4 Mpx export cap. Split out so it is testable without a fetch.
massgis_export_url <- function(bbox, mpp) {
  latm <- mean(c(bbox[2], bbox[4]))
  w <- round((bbox[3] - bbox[1]) * cos(latm * pi / 180) * 111320 / mpp); h <- round((bbox[4] - bbox[2]) * 111320 / mpp)
  if (w * h > 4.0e6) { f <- sqrt(4.0e6 / (w * h)); w <- floor(w * f); h <- floor(h * f) }
  sprintf("%s?bbox=%f,%f,%f,%f&bboxSR=4326&size=%d,%d&imageSR=26986&format=tiff&pixelType=F32&interpolation=RSP_BilinearInterpolation&f=image",
          MG, bbox[1], bbox[2], bbox[3], bbox[4], w, h)
}
# Cached download of that export: skip if dst already looks complete; returns
# dst on success, NA on failure.
massgis_export <- function(bbox, dst, mpp) {
  if (!file.exists(dst) || file.size(dst) < 1e5) {
    url <- massgis_export_url(bbox, mpp)
    for (k in 1:6) { ok <- tryCatch({ download.file(url, dst, mode = "wb", quiet = TRUE); file.exists(dst) && file.size(dst) > 1e5 }, error = function(e) FALSE)
      if (ok) break; Sys.sleep(2 * k) }   # MassGIS throws intermittent 500s; retry resolves them
  }
  if (file.exists(dst) && file.size(dst) > 1e5) dst else NA_character_
}

# One survey panel: a borderless raster pane with a bold subtitle, 150 dpi.
render_one <- function(ras, sub, e, file, w, h, sub_size = 10.5) {
  p <- ggplot() + annotation_raster(ras, e[1], e[2], e[3], e[4], interpolate = TRUE) +
    coord_sf(crs = st_crs(CRS_MA), xlim = c(e[1], e[2]), ylim = c(e[3], e[4]), datum = NA, expand = FALSE) +
    labs(subtitle = sub) + theme_quabbin() +
    theme(axis.text = element_blank(), axis.title = element_blank(), panel.grid = element_blank(),
          plot.subtitle = element_text(face = "bold", size = sub_size), panel.border = element_rect(colour = "#888888", fill = NA, linewidth = 0.5))
  ggsave(file, p, width = w, height = h, dpi = 150, bg = "white"); file
}
# Stitch panel PNGs into one titled row. (15_xref keeps its own inline stitch:
# it adds a footnote line, so its margins and title size differ.)
stitch_row <- function(pngs, out, pw, ph, title, res = 150) {
  imgs <- lapply(pngs, png::readPNG)
  grDevices::png(out, width = pw * length(imgs) * res, height = (ph + 0.3) * res, res = res); grid::grid.newpage()
  grid::grid.text(title, y = grid::unit(1, "npc") - grid::unit(3, "mm"), vjust = 1, gp = grid::gpar(fontface = "bold", fontsize = 15))
  grid::pushViewport(grid::viewport(y = 0, height = grid::unit(1, "npc") - grid::unit(8, "mm"), just = "bottom", layout = grid::grid.layout(1, length(imgs))))
  for (i in seq_along(imgs)) { grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = i)); grid::grid.raster(imgs[[i]]); grid::popViewport() }
  grDevices::dev.off(); out
}
