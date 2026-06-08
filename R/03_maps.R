# 03_maps.R ---------------------------------------------------------------
# Render the spatial figures to output/. A shaded-relief base (grey hillshade
# + hypsometric DEM, layered with ggnewscale) carries the terrain; vector
# layers are drawn with fixed colours so they never fight the fill scales.
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("dem_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))

# --- Rasters -> data frames (downsampled for snappy rendering) ------------
.agg <- function(r, max_cells = 3e5) {
  n <- terra::ncell(r)
  if (n > max_cells) r <- terra::aggregate(r, fact = ceiling(sqrt(n / max_cells)))
  r
}
.df <- function(r) {
  d <- terra::as.data.frame(.agg(r), xy = TRUE, na.rm = FALSE)
  names(d) <- c("x", "y", "z"); d
}
DEM_DF  <- .df(dem_ma)
HILL_DF <- .df(hill)

# --- Reusable map furniture ----------------------------------------------
relief_colored <- function() list(
  geom_raster(data = HILL_DF, aes(x, y, fill = z), show.legend = FALSE, na.rm = TRUE),
  scale_fill_gradient(low = "#3a3a3a", high = "#ffffff", guide = "none"),
  new_scale_fill(),
  geom_raster(data = DEM_DF, aes(x, y, fill = z), alpha = 0.55, na.rm = TRUE),
  scale_fill_gradientn(colours = HYPSO_PAL, name = "Elevation\n(m)", na.value = NA)
)
relief_gray <- function() list(
  geom_raster(data = HILL_DF, aes(x, y, fill = z), show.legend = FALSE, na.rm = TRUE),
  scale_fill_gradient(low = "#4a4a4a", high = "#f4f4f4", guide = "none", na.value = NA)
)

drowned$lab     <- drowned$town
drowned$lab_end <- paste0(drowned$town, "\n1938")

town_pts  <- geom_sf(data = drowned, shape = 21, fill = "white",
                     colour = INK, size = 2.8, stroke = 0.5)
town_labs <- ggrepel::geom_text_repel(
  data = drowned, aes(label = lab, geometry = geometry), stat = "sf_coordinates",
  size = 3.7, fontface = "bold", colour = INK, bg.color = "white", bg.r = 0.22,
  box.padding = 0.5, point.padding = 6, min.segment.length = 0,
  max.overlaps = Inf, seed = 1)

bb    <- st_bbox(aoi_ma)
coord <- coord_sf(crs = st_crs(CRS_MA),
                  xlim = c(bb["xmin"], bb["xmax"]),
                  ylim = c(bb["ymin"], bb["ymax"]),
                  expand = FALSE, datum = NA)
deco  <- list(
  ggspatial::annotation_scale(location = "bl", height = unit(0.12, "cm"),
                              text_cex = 0.55, line_width = 0.4),
  ggspatial::annotation_north_arrow(location = "tr", which_north = "true",
    height = unit(0.7, "cm"), width = unit(0.7, "cm"),
    style = ggspatial::north_arrow_minimal())
)

# --- 1. Locator -----------------------------------------------------------
p1 <- ggplot() +
  (if (!is.null(state_ma)) geom_sf(data = state_ma, fill = "#ededed", colour = "#c4c4c4", linewidth = 0.2)) +
  geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = WATER_LINE, linewidth = 0.2) +
  geom_sf(data = aoi_ma, fill = NA, colour = "#d62828", linewidth = 0.7) +
  coord_sf(crs = st_crs(CRS_MA), datum = NA, expand = TRUE) +
  labs(title = "Quabbin Reservoir, Massachusetts",
       subtitle = "Boston's water supply, on the site of four former towns",
       caption = ATTRIB) +
  theme_quabbin()
save_map(p1, "01_locator.png", w = 9, h = 7)

# --- 2. Terrain: why this valley -----------------------------------------
p2 <- ggplot() + relief_colored() +
  geom_sf(data = reservoir_ma, fill = NA, colour = WATER_LINE, linewidth = 0.3, linetype = "22") +
  town_pts + deco + coord +
  labs(title = "The Swift River Valley",
       subtitle = "A long, low north-south basin, walled by hills, that became the reservoir",
       caption = ATTRIB) +
  theme_quabbin()
save_map(p2, "02_dem_hillshade.png")

# --- 3. Four towns under the water ---------------------------------------
p3 <- ggplot() + relief_gray() +
  geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = WATER_LINE, linewidth = 0.25, alpha = 0.92) +
  town_pts + town_labs + deco + coord +
  labs(title = "Four towns under the water",
       subtitle = "Dana, Enfield, Greenwich, and Prescott, disincorporated 28 April 1938",
       caption = paste0("Reservoir extent: ", RES_SRC, "\n", ATTRIB)) +
  theme_quabbin()
save_map(p3, "03_reservoir_towns.png")

# --- 4. Watershed in regional context (only if the WBD service answered) ---
# 5 dissolved HUC-10s are far larger than the ~120 sq mi Quabbin watershed,
# so this is shown zoomed out as honest regional drainage context, not as the
# precise DCR boundary.
if (!is.null(watershed_ma)) {
  wbb <- st_bbox(st_buffer(st_union(watershed_ma), 4000))
  p4 <- ggplot() +
    (if (!is.null(state_ma)) geom_sf(data = state_ma, fill = "#efeee8", colour = "#dad6cc", linewidth = 0.2)) +
    geom_sf(data = watershed_ma, fill = "#2a9d8f", colour = "#13564d", linewidth = 0.7, alpha = 0.16) +
    geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = WATER_LINE, linewidth = 0.3) +
    town_pts +
    ggspatial::annotation_scale(location = "bl", height = unit(0.12, "cm"), text_cex = 0.55, line_width = 0.4) +
    coord_sf(crs = st_crs(CRS_MA),
             xlim = c(wbb["xmin"], wbb["xmax"]), ylim = c(wbb["ymin"], wbb["ymax"]),
             expand = FALSE, datum = NA) +
    labs(title = "The reservoir sits inside its drainage",
         subtitle = "USGS HUC-10 hydrologic units around the reservoir (regional context, not the exact watershed)",
         caption = ATTRIB) +
    theme_quabbin()
  save_map(p4, "04_watershed.png", w = 9.5, h = 9)
} else {
  msg("watershed layer absent - skipping 04_watershed.png")
}

# --- 5. Erased from the map ----------------------------------------------
if (!is.null(towns_aoi)) {
  surv_lab <- if ("NAME" %in% names(towns_aoi)) {
    geom_sf_text(data = towns_aoi, aes(label = NAME), size = 2.5,
                 colour = "#8a857c", fontface = "italic", check_overlap = TRUE)
  }
  p5 <- ggplot() +
    geom_sf(data = towns_aoi, fill = "#f7f5f0", colour = "#a9a399", linewidth = 0.45) +
    geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = WATER_LINE, linewidth = 0.25, alpha = 0.92) +
    surv_lab +
    town_pts +
    ggrepel::geom_text_repel(data = drowned, aes(label = lab_end, geometry = geometry),
      stat = "sf_coordinates", size = 3.3, fontface = "bold", lineheight = 0.9, colour = "#7a1f1f",
      bg.color = "white", bg.r = 0.2, box.padding = 0.8, point.padding = 8,
      min.segment.length = 0, max.overlaps = Inf, seed = 1) +
    deco + coord +
    labs(title = "The four towns' land today",
         subtitle = "The former town land, now divided among the surrounding municipalities",
         caption = ATTRIB) +
    theme_quabbin()
  save_map(p5, "05_erasure.png")
} else {
  msg("modern municipalities absent - skipping 05_erasure.png")
}

# --- 8. Hero --------------------------------------------------------------
p_hero <- ggplot() + relief_colored() +
  geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = WATER_LINE, linewidth = 0.3, alpha = 0.9) +
  town_pts + town_labs + deco + coord +
  labs(title = "The Quabbin Reservoir and the Swift River Valley",
       subtitle = "Terrain, water, and the sites of the four former towns, Massachusetts",
       caption = paste0("Reservoir extent: ", RES_SRC, "\n", ATTRIB)) +
  theme_quabbin(base = 13)
save_map(p_hero, "08_hero.png", w = 10, h = 10)

msg("map stage complete")
