# 05_floodfill.R ----------------------------------------------------------
# Animate the reservoir filling. Raise the pool level up the DEM in stages,
# carve the water at each level, and render:
#   - output/floodfill_frames/f_##.png  (frames)
#   - output/quabbin_floodfill.gif      (animation, via ImageMagick)
#   - output/09_floodfill.png           (small-multiples panel)
#   - map/data/floodstages.geojson      (per-stage water polygons for the web slider)
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("dem_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))

DIR_FRAMES <- file.path(DIR_OUTPUT, "floodfill_frames"); dir.create(DIR_FRAMES, showWarnings = FALSE)
DIR_WEB    <- file.path(QB_DIR, "map", "data");          dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)

# Grey relief base (shared by every frame)
.agg <- function(r, maxc = 2.5e5) { n <- terra::ncell(r); if (n > maxc) r <- terra::aggregate(r, ceiling(sqrt(n / maxc))); r }
hill_df <- terra::as.data.frame(.agg(hill), xy = TRUE, na.rm = FALSE); names(hill_df) <- c("x", "y", "z")
bb     <- st_bbox(aoi_ma)
coordf <- coord_sf(crs = st_crs(CRS_MA), xlim = c(bb["xmin"], bb["xmax"]),
                   ylim = c(bb["ymin"], bb["ymax"]), expand = FALSE, datum = NA)

# Modern DEMs (AWS Terrain and LiDAR alike) capture only today's WATER SURFACE
# (~530 ft), not the drowned valley floor, so a true elevation fill is impossible.
# Model the basin SCHEMATICALLY: synthetic depth grows with distance from shore
# (broad main basin deepest, narrow arms shallow), scaled to the reservoir's
# surveyed ~150 ft maximum depth. The pool then rises over this synthetic bed,
# filling the deep central channel first and spreading out to the arms.
reservoir_full <- st_make_valid(st_union(st_geometry(reservoir_ma)))
area_full      <- as.numeric(st_area(reservoir_full))
.fpv           <- terra::vect(st_sf(geometry = reservoir_full))
.grid   <- terra::crop(dem_ma, terra::ext(.fpv), snap = "out")
.inside <- terra::rasterize(.fpv, .grid, field = 1, background = NA)
dshore  <- terra::mask(terra::distance(terra::ifel(is.na(.inside), 1, NA)), .fpv)  # metres to shore, inside only
bed     <- POOL_M - (dshore / as.numeric(terra::global(dshore, "max", na.rm = TRUE))) * (150 * 0.3048)

# EQUAL-AREA stages: quantiles of the synthetic bed -> each frame floods about the
# same extra surface, rising from a small central channel up to the full footprint.
N      <- 14
bvals  <- terra::values(bed); bvals <- bvals[!is.na(bvals)]
levels <- as.numeric(quantile(bvals, probs = seq(1 / N, 1, length.out = N)))
levels[length(levels)] <- POOL_M
msg("schematic flood stages (%d, ft): %s", length(levels), paste(round(levels / 0.3048), collapse = ", "))

# Water inside the footprint at a given fill level (subset of the next by design).
carve_fill <- function(level) {
  m <- terra::ifel(bed <= level, 1, NA)
  if (all(is.na(terra::values(m)))) return(reservoir_full)
  st_make_valid(st_union(sf::st_as_sf(terra::as.polygons(m, dissolve = TRUE))))
}
water_list <- lapply(levels, carve_fill)
water_list[[length(water_list)]] <- reservoir_full   # final frame == full footprint (exactly 100%)

frame_plot <- function(water, level) {
  pct  <- round(as.numeric(st_area(water)) / area_full * 100)
  full <- isTRUE(abs(level - POOL_M) < 1e-6)
  ggplot() +
    geom_raster(data = hill_df, aes(x, y, fill = z), show.legend = FALSE, na.rm = TRUE) +
    scale_fill_gradient(low = "#4a4a4a", high = "#f4f4f4", na.value = NA) +
    geom_sf(data = st_sf(geometry = water),
            fill = WATER_FILL, colour = WATER_LINE, linewidth = 0.2, alpha = 0.95) +
    geom_sf(data = drowned, shape = 21, fill = "white", colour = INK, size = 1.9, stroke = 0.4) +
    coordf +
    labs(title = sprintf("Filling the reservoir, pool at %d ft", round(level / 0.3048)),
         subtitle = sprintf("%d%% of full surface%s", pct, if (full) " (full pool, 1946)" else ""),
         caption = "Schematic fill: the drowned valley floor isn't in modern DEMs, so depth is modeled from distance-to-shore (surveyed max ~150 ft). Full pool = 530 ft.") +
    theme_quabbin()
}

# --- Frames + GIF ---------------------------------------------------------
frame_files <- character(0)
for (i in seq_along(levels)) {
  f <- file.path(DIR_FRAMES, sprintf("f_%02d.png", i))
  ggsave(f, frame_plot(water_list[[i]], levels[i]), width = 7, height = 7, dpi = 100, bg = "white")
  frame_files <- c(frame_files, f)
}
hold <- rep(frame_files[length(frame_files)], 4)   # pause on the full pool
gif  <- file.path(DIR_OUTPUT, "quabbin_floodfill.gif")
ok <- tryCatch({
  system2("convert", c("-delay", "45", "-loop", "0", c(frame_files, hold), "-layers", "optimize", gif)); TRUE
}, warning = function(w) FALSE, error = function(e) FALSE)
msg(if (file.exists(gif)) sprintf("wrote output/quabbin_floodfill.gif (%.1f MB)", file.size(gif)/1e6) else "GIF assembly skipped (ImageMagick not found)")

# --- Small-multiples panel (6 stages) -------------------------------------
pick <- round(seq(2, length(levels), length.out = 6))
panel <- patchwork::wrap_plots(
  lapply(pick, \(i) frame_plot(water_list[[i]], levels[i]) +
           theme(plot.caption = element_blank(), plot.subtitle = element_text(size = rel(0.8)),
                 plot.title = element_text(size = rel(0.95)))),
  ncol = 3) +
  patchwork::plot_annotation(
    title = "Filling the reservoir, stage by stage (1939-1946)",
    caption = "Each panel raises the pool another step toward the 530 ft full pool. Schematic synthetic bathymetry (the drowned valley floor isn't captured by modern DEMs).")
save_map(panel, "09_floodfill.png", w = 12, h = 8)

# --- Export per-stage polygons for the web slider -------------------------
stages <- do.call(rbind, lapply(seq_along(levels), function(i) {
  g <- water_list[[i]]
  st_sf(stage = i,
        pool_ft = round(levels[i] / 0.3048),
        pct = round(as.numeric(st_area(g)) / area_full * 100),
        geometry = g)
}))
stages <- st_transform(st_simplify(stages, dTolerance = 35), CRS_LL)
st_write(stages, file.path(DIR_WEB, "floodstages.geojson"), delete_dsn = TRUE, quiet = TRUE)
msg("wrote map/data/floodstages.geojson (%d stages)", nrow(stages))

msg("floodfill stage complete")
