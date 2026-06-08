# 13_roads.R --------------------------------------------------------------
# "The roads the reservoir drowned." Instead of a schematic, this renders the
# real Swift River Valley road network from the georeferenced 1893 USGS
# Belchertown quadrangle -- its village roads, mills, and the four town centres --
# and overlays the present Quabbin Reservoir so you can see exactly which roads
# and villages went under. Edge labels mark the routes out to the surviving
# neighbours. Renders output/16_roads.png.
# Source: USGS Historical Topographic Map Collection (public domain).
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("reservoir_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))

tif <- file.path(DIR_DATA, "cache", "preflood_belchertown_1893.tif")
url <- "https://prd-tnm.s3.amazonaws.com/StagedProducts/Maps/HistoricalTopo/GeoTIFF/MA/MA_Belchertown_352469_1893_62500_geo.tif"
if (!file.exists(tif)) {
  dir.create(dirname(tif), recursive = TRUE, showWarnings = FALSE)
  try(download.file(url, tif, mode = "wb", quiet = TRUE), silent = TRUE)
}
stopifnot(file.exists(tif))

# crop to the valley core (in the quad's native CRS), reproject to State Plane
valley_ll <- terra::as.polygons(terra::ext(-72.47, -72.25, 42.26, 42.47), crs = "EPSG:4326")
topo  <- terra::rast(tif)
topo_c <- terra::crop(topo, terra::project(valley_ll, terra::crs(topo)))
topo_ma <- terra::project(topo_c, "EPSG:26986", method = "bilinear")
f <- floor(terra::ncol(topo_ma) / 1800); if (f > 1) topo_ma <- terra::aggregate(topo_ma, f, fun = "mean", na.rm = TRUE)

arr <- terra::as.array(topo_ma) / 255       # [row, col, band], north = row 1
arr[is.na(arr)] <- 1                          # white out reprojection corners
base_ras <- grDevices::as.raster(arr)
e <- terra::ext(topo_ma); xmn <- e[1]; xmx <- e[2]; ymn <- e[3]; ymx <- e[4]

# the four drowned town centres
tw <- utils::read.csv(file.path(DIR_DATA, "drowned_towns.csv"), stringsAsFactors = FALSE)
tw_ma <- st_transform(st_as_sf(tw, coords = c("lon", "lat"), crs = CRS_LL), CRS_MA)
tw$X <- st_coordinates(tw_ma)[, 1]; tw$Y <- st_coordinates(tw_ma)[, 2]

# directions out to the surviving neighbours, placed at the frame edges
edge <- data.frame(
  label = c("to Petersham", "to Hardwick", "to Ware", "to Belchertown",
            "to Pelham &\nAmherst", "to Shutesbury", "to New Salem"),
  lon = c(-72.258, -72.256, -72.272, -72.448, -72.460, -72.452, -72.345),
  lat = c( 42.455,  42.352,  42.270,  42.276,  42.398,  42.452,  42.462), stringsAsFactors = FALSE)
edge_ma <- st_transform(st_as_sf(edge, coords = c("lon", "lat"), crs = CRS_LL), CRS_MA)
edge$X <- st_coordinates(edge_ma)[, 1]; edge$Y <- st_coordinates(edge_ma)[, 2]

p_roads <- ggplot() +
  annotation_raster(base_ras, xmin = xmn, xmax = xmx, ymin = ymn, ymax = ymx, interpolate = TRUE) +
  geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = "#1b4a6b", alpha = 0.34, linewidth = 0.4) +
  geom_label(data = edge, aes(X, Y, label = label), size = 2.7, fontface = "italic",
             colour = "#34403a", fill = "#ffffffcc", label.size = 0, label.r = unit(0.05, "lines"),
             lineheight = 0.9) +
  geom_point(data = tw, aes(X, Y), shape = 21, fill = "#7a1f1f", colour = "white", size = 4, stroke = 0.7) +
  ggrepel::geom_text_repel(data = tw, aes(X, Y, label = town), size = 3.6, fontface = "bold",
                           colour = "#5c1414", bg.color = "white", bg.r = 0.18, seed = 1,
                           point.padding = 6, box.padding = 0.5, min.segment.length = 0.3, segment.color = "#5c1414") +
  ggspatial::annotation_scale(location = "br", width_hint = 0.26, height = unit(0.18, "cm"),
                              text_cex = 0.6, pad_y = unit(0.35, "cm")) +
  coord_sf(crs = st_crs(CRS_MA), xlim = c(xmn, xmx), ylim = c(ymn, ymx), expand = FALSE, datum = NA) +
  labs(title = "The roads the reservoir drowned",
       subtitle = "The valley's 1893 road network and villages, with the present Quabbin Reservoir overlaid in blue",
       caption = paste0("Base map: USGS Belchertown 15-minute quadrangle, 1893, 1:62,500 (public domain).\n",
                        "Blue: the 530 ft full-pool reservoir. Red: the four drowned town centres.")) +
  theme_quabbin() +
  theme(axis.text = element_blank(), axis.title = element_blank(),
        panel.grid = element_blank(), panel.border = element_rect(colour = "#888888", fill = NA, linewidth = 0.4))
save_map(p_roads, "16_roads.png", w = 8.4, h = 9.4)
msg("wrote 16_roads.png")
