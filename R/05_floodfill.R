# 05_floodfill.R ----------------------------------------------------------
# Animate the valley drowning. Raise the pool level up the DEM in stages,
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

# Carve the main waterbody at a given pool elevation (metres): land <= level,
# largest contiguous component, clipped to the study window.
carve <- function(level) {
  m <- terra::ifel(dem_ma <= level, 1, NA)
  p <- suppressWarnings(st_cast(st_make_valid(sf::st_as_sf(terra::as.polygons(m, dissolve = TRUE))), "POLYGON"))
  p <- p[which.max(as.numeric(st_area(p))), ]
  st_intersection(st_union(st_geometry(p)), st_geometry(aoi_ma))
}

# Even elevation steps from just above the valley floor up to full pool, so
# each frame visibly raises the water (a linear sweep, not quantiles which
# bunch up near the broad rim).
uw     <- terra::values(dem_ma); uw <- uw[!is.na(uw) & uw <= POOL_M]
floor  <- as.numeric(quantile(uw, 0.05))
levels <- seq(floor, POOL_M, length.out = 10)
msg("flood stages (m): %s", paste(round(levels, 1), collapse = ", "))

water_list <- lapply(levels, carve)
area_full  <- as.numeric(st_area(water_list[[length(water_list)]]))

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
    labs(title = sprintf("Filling the Quabbin — pool at %d ft", round(level / 0.3048)),
         subtitle = sprintf("%d%% of full surface%s", pct, if (full) " (full pool, 1946)" else ""),
         caption = "Water = land below the rising pool, carved from the DEM. Full pool = 530 ft ASL.") +
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
    title = "The valley drowning, stage by stage (1939–1946)",
    caption = "Each panel raises the pool another step toward the 530 ft full pool. Carved from the DEM.")
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
