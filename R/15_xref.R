# 15_xref.R ---------------------------------------------------------------
# Ground-truth cross-reference: does a LiDAR lineation correspond to a road the
# 1893 survey actually mapped? Extract the 1893 road network from the
# georeferenced quad (dark, low-saturation linework, morphologically closed,
# kept only where elongated → roads not text), then classify the LiDAR road
# traces by proximity: a trace within 14 m of an extracted 1893 road is a
# CONFIRMED surviving roadbed; the rest are unverified candidates. Demonstrated
# on the mid-Prescott-Peninsula window (the old village area). Renders
# output/25_prescott_xref.png. Cache-guarded.
# Honest limit: auto-extraction of 1893 linework catches the main roads, not the
# full network, so "unverified" is not the same as "newly discovered" — the
# explorer's 1893 fade overlay remains the fuller visual ground-truth.
# Data: MassGIS LiDAR + USGS 1893 Belchertown quad (both public domain).
# -------------------------------------------------------------------------
if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("POOL_M")) source(file.path(QB_DIR, "R", "00_setup.R"))
OUT <- file.path(DIR_OUTPUT, "25_prescott_xref.png")
STRIP <- file.path(DIR_CACHE, "massgis_prescott_2.tif")   # middle peninsula strip, fetched by 14_imprints
if (file.exists(OUT)) { msg("xref: 25_prescott_xref.png cached, skipping") } else if (!file.exists(STRIP)) {
  msg("xref: %s not found (run 14_imprints first); skipping", basename(STRIP))
} else {
TOPO_1893 <- file.path(DIR_CACHE, "preflood_belchertown_1893.tif")
WATER_LVL <- POOL_M + 0.5; wc <- grDevices::col2rgb(WATER_FILL)[, 1]
to_raster <- function(r) { a <- terra::as.array(r) / 255; a[is.na(a)] <- 1; grDevices::as.raster(a) }
lrm <- function(d, K = 25) d - terra::focal(d, w = K, fun = "mean", na.rm = TRUE)
mdow <- function(d, angle = 35) { slp <- terra::terrain(d, "slope", unit = "radians"); asp <- terra::terrain(d, "aspect", unit = "radians")
  hs <- Reduce(`+`, lapply(seq(0, 315, 45), function(a) terra::shade(slp, asp, angle = angle, direction = a))) / 8
  terra::clamp((hs - 0.5) * 1.6 + 0.5, 0, 1) }
relief_grey <- function(d, L, span) { hs <- mdow(d); neg <- terra::clamp(-L / span, 0, 1); pos <- terra::clamp(L / span, 0, 1)
  terra::clamp(hs * (1 - 0.5 * neg) + 0.32 * pos * (1 - hs), 0, 1) }
linfilter <- function(mask, Nmin, Emin, Lmin) {
  p <- terra::patches(mask, directions = 8, zeroAsNA = TRUE); v <- terra::values(p)[, 1]; cells <- which(!is.na(v))
  if (!length(cells)) return(p * NA)
  ids <- v[cells]; xy <- terra::xyFromCell(p, cells); spl <- split(as.data.frame(xy), ids)
  sizes <- vapply(spl, nrow, integer(1))
  st <- lapply(spl, function(z) { if (nrow(z) < 8) return(c(0, 0)); ev <- eigen(stats::cov(z), only.values = TRUE)$values
    c(sqrt(max(ev) / max(min(ev), 1e-4)), sqrt(max(ev)) * 3.5) })
  el <- vapply(st, `[`, numeric(1), 1); ln <- vapply(st, `[`, numeric(1), 2)
  keep <- as.numeric(names(sizes)[sizes >= Nmin & el >= Emin & ln >= Lmin])
  if (length(keep)) terra::subst(p, keep, 1, others = NA) else p * NA
}
extract_lines <- function(signed, thr, slope, smax, water, Nmin, Emin, Lmin)
  linfilter(terra::ifel(signed > thr & slope < smax & !water, 1, NA), Nmin, Emin, Lmin)
render_one <- function(ras, sub, e, file, w, h) {
  p <- ggplot() + annotation_raster(ras, e[1], e[2], e[3], e[4], interpolate = TRUE) +
    coord_sf(crs = st_crs(CRS_MA), xlim = c(e[1], e[2]), ylim = c(e[3], e[4]), datum = NA, expand = FALSE) +
    labs(subtitle = sub) + theme_quabbin() +
    theme(axis.text = element_blank(), axis.title = element_blank(), panel.grid = element_blank(),
          plot.subtitle = element_text(face = "bold", size = 10), panel.border = element_rect(colour = "#888888", fill = NA, linewidth = 0.5))
  ggsave(file, p, width = w, height = h, dpi = 150, bg = "white"); file
}

dem <- terra::rast(STRIP)[[1]]
demS <- terra::focal(dem, 3, "mean", na.rm = TRUE); water <- dem <= WATER_LVL; e <- terra::ext(dem)
slope <- terra::terrain(demS, "slope", unit = "degrees")
L <- lrm(demS, 25); span <- as.numeric(stats::quantile(abs(terra::values(L)), 0.985, na.rm = TRUE))
base <- terra::clamp(relief_grey(demS, L, span), 0, 1) * 255

# 1893 road network, extracted at the quad's native resolution
topo <- terra::rast(TOPO_1893); bbp <- terra::as.polygons(terra::ext(dem), crs = terra::crs(dem))
topo_ma <- terra::project(terra::crop(topo, terra::project(bbp, terra::crs(topo))), terra::crs(dem))
gn <- topo_ma / 255; mean3 <- terra::mean(gn); rng <- terra::app(gn, max) - terra::app(gn, min)
black <- terra::ifel(mean3 < 0.55 & rng < 0.22, 1, NA)
be <- terra::focal(terra::focal(terra::ifel(is.na(black), 0, 1), 3, "max"), 3, "min")   # close gaps
R93 <- terra::resample(linfilter(terra::ifel(be > 0.5, 1, NA), 18, 3.2, 38), dem, method = "near")

roads <- extract_lines(-L, 0.22, slope, 12, water, 40, 5, 40)
walls <- extract_lines( L, 0.16, slope, 13, water, 36, 5, 35)
d93 <- terra::distance(terra::ifel(is.na(R93), NA, 1))
roads_m <- !is.na(roads); conf <- roads_m & (d93 < 14); new <- roads_m & (d93 >= 14)
msg("xref: 1893 road cells %d | LiDAR roads %d | confirmed %d (%.0f%%)",
    sum(terra::values(!is.na(R93)), na.rm = TRUE), sum(terra::values(roads_m), na.rm = TRUE),
    sum(terra::values(conf), na.rm = TRUE), 100 * sum(terra::values(conf), na.rm = TRUE) / max(1, sum(terra::values(roads_m), na.rm = TRUE)))

paint <- function(lc) { R <- base; G <- base; B <- base
  for (x in lc) { col <- grDevices::col2rgb(x$col); R <- terra::ifel(x$m, col[1], R); G <- terra::ifel(x$m, col[2], G); B <- terra::ifel(x$m, col[3], B) }
  R <- terra::ifel(water, wc[1], R); G <- terra::ifel(water, wc[2], G); B <- terra::ifel(water, wc[3], B); to_raster(c(R, G, B)) }
rasC <- to_raster(c(terra::ifel(water, wc[1], base), terra::ifel(water, wc[2], base), terra::ifel(water, wc[3], base)))
rasA <- paint(list(list(m = !is.na(R93), col = "#1f6fb0")))
rasB <- paint(list(list(m = !is.na(walls), col = "#1fb6a6"), list(m = new, col = "#ff7b00"), list(m = conf, col = "#2ca02c")))

asp <- terra::nrow(dem) / terra::ncol(dem); pw <- 4.6; ph <- max(4.4, min(13, pw * asp))
t1 <- tempfile(fileext = ".png"); t2 <- tempfile(fileext = ".png"); t3 <- tempfile(fileext = ".png")
render_one(rasC, "MassGIS LiDAR relief", e, t1, pw, ph)
render_one(rasA, "1893 road network, extracted from the quad (blue)", e, t2, pw, ph)
render_one(rasB, "LiDAR lineations: confirmed by 1893 (green) - unverified (orange) - banks/walls (teal)", e, t3, pw, ph)
imgs <- lapply(c(t1, t2, t3), png::readPNG)
grDevices::png(OUT, width = pw * 3 * 150, height = (ph + 0.55) * 150, res = 150)
grid::grid.newpage()
grid::grid.text("Prescott (mid-peninsula) - cross-referencing the 1893 survey", y = grid::unit(1, "npc") - grid::unit(3, "mm"), vjust = 1, gp = grid::gpar(fontface = "bold", fontsize = 14))
grid::grid.text("Confirmed = LiDAR lineation within 14 m of an extracted 1893 road. Auto-extraction catches the main roads, not the full network; the explorer's 1893 fade overlay is the fuller ground-truth.",
                y = grid::unit(2.5, "mm"), vjust = 0, gp = grid::gpar(fontsize = 7.5, col = "#666666"))
grid::pushViewport(grid::viewport(y = grid::unit(5, "mm"), height = grid::unit(1, "npc") - grid::unit(13, "mm"), just = "bottom", layout = grid::grid.layout(1, 3)))
for (i in 1:3) { grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = i)); grid::grid.raster(imgs[[i]]); grid::popViewport() }
grDevices::dev.off(); msg("wrote 25_prescott_xref.png")
}
