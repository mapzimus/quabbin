# 06_aqueduct.R -----------------------------------------------------------
# The ethics, made spatial: the water doesn't stay. It leaves the drowned
# valley through Winsor Dam / Goodnough Dike and runs ~100 km east by
# aqueduct (Quabbin -> Wachusett -> Boston) to the metropolis it was taken
# for. Renders output/10_aqueduct.png and exports the infrastructure as
# GeoJSON for the web map.
# Geometry is hand-placed from known coordinates (schematic, not surveyed).
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("dem_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)

# --- Infrastructure points (lon, lat) ------------------------------------
infra <- data.frame(
  name = c("Winsor Dam", "Goodnough Dike", "Wachusett Reservoir", "Boston"),
  type = c("dam", "dam", "reservoir", "city"),
  lon  = c(-72.3370, -72.3000, -71.7430, -71.0589),
  lat  = c( 42.2967,  42.2920,  42.4230,  42.3601),
  stringsAsFactors = FALSE)
infra_sf <- st_as_sf(infra, coords = c("lon", "lat"), crs = CRS_LL)

# Aqueduct route: Quabbin intake -> Wachusett -> Boston (schematic).
route_ll <- rbind(c(-72.305, 42.363), c(-71.743, 42.423), c(-71.0589, 42.3601))
aqueduct_ll <- st_sfc(st_linestring(route_ll), crs = CRS_LL)

# straight-line distance valley -> Boston
d_km <- as.numeric(st_distance(st_sfc(st_point(c(-72.33, 42.30)), crs = CRS_LL),
                               st_sfc(st_point(c(-71.0589, 42.3601)), crs = CRS_LL))) / 1000

# --- Project for mapping --------------------------------------------------
infra_ma    <- st_transform(infra_sf, CRS_MA)
aqueduct_ma <- st_transform(aqueduct_ll, CRS_MA)
route_df    <- as.data.frame(st_coordinates(aqueduct_ma))[, 1:2]; names(route_df) <- c("x", "y")
boston_ma   <- infra_ma[infra_ma$type == "city", ]
dams_ma     <- infra_ma[infra_ma$type == "dam", ]

# label coordinates (geom_text is more robust than geom_sf_text under datum=NA)
lab_df     <- cbind(as.data.frame(st_coordinates(infra_ma)), infra_ma[, c("name", "type")] |> st_drop_geometry())
names(lab_df)[1:2] <- c("x", "y")
boston_lab <- lab_df[lab_df$type == "city", ]
wach_lab   <- lab_df[lab_df$type == "reservoir", ]

# --- 10. "Where the water goes" (state scale) -----------------------------
p_aq <- ggplot() +
  (if (!is.null(state_ma)) geom_sf(data = state_ma, fill = "#eef0ec", colour = "#c8ccc2", linewidth = 0.3)) +
  geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = WATER_LINE, linewidth = 0.2) +
  geom_path(data = route_df, aes(x, y), colour = "#1f6fb0", linewidth = 1.1,
            arrow = arrow(length = unit(0.28, "cm"), type = "closed")) +
  geom_sf(data = infra_ma[infra_ma$type == "reservoir", ], shape = 21, fill = WATER_FILL, colour = WATER_LINE, size = 2.6) +
  geom_sf(data = boston_ma, shape = 21, fill = "#d62828", colour = "white", size = 5, stroke = 0.6) +
  geom_text(data = boston_lab, aes(x, y + 9000, label = name), fontface = "bold", size = 3.6, colour = "#7a1f1f") +
  geom_text(data = wach_lab, aes(x, y + 13000, label = name), size = 2.8, colour = "#445566", fontface = "italic") +
  annotate("text", x = route_df$x[1] * 0.6 + route_df$x[2] * 0.4, y = mean(route_df$y[1:2]) - 15000,
           label = "Quabbin Aqueduct", size = 3, colour = "#1f6fb0", fontface = "italic") +
  annotate("label", x = mean(c(route_df$x[1], route_df$x[3])), y = min(route_df$y) - 26000,
           label = sprintf("~%d km (%d mi) east — to the city the valley was drowned for",
                           round(d_km), round(d_km / 1.609)),
           size = 3.1, colour = INK, fill = "white", alpha = 0.7, label.size = 0) +
  ggspatial::annotation_scale(location = "bl", height = unit(0.12, "cm"), text_cex = 0.55, line_width = 0.4) +
  coord_sf(crs = st_crs(CRS_MA), datum = NA, expand = TRUE) +
  labs(title = "Drowned for a city 100 km away",
       subtitle = "The water leaves the Swift River Valley through Winsor Dam and runs east by aqueduct to metropolitan Boston",
       caption = paste0("Aqueduct route is schematic (Quabbin → Wachusett → Boston). Dams: Winsor Dam & Goodnough Dike.\n", ATTRIB)) +
  theme_quabbin()
save_map(p_aq, "10_aqueduct.png", w = 11, h = 7)

# --- Export for the web map ----------------------------------------------
st_write(st_transform(st_sf(name = "Quabbin Aqueduct (schematic)", geometry = aqueduct_ll), CRS_LL),
         file.path(DIR_WEB, "aqueduct.geojson"), delete_dsn = TRUE, quiet = TRUE)
st_write(infra_sf, file.path(DIR_WEB, "infrastructure.geojson"), delete_dsn = TRUE, quiet = TRUE)
msg("aqueduct stage complete (valley->Boston ~%d km); wrote 10_aqueduct.png + web GeoJSON", round(d_km))
