# 07_export_web.R ---------------------------------------------------------
# Export the vector layers the interactive Leaflet map consumes, all in
# EPSG:4326, simplified for the browser. (floodstages/aqueduct/infrastructure
# are written by 05 & 06.) Writes into map/data/.
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("reservoir_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))
DIR_WEB <- file.path(QB_DIR, "map", "data"); dir.create(DIR_WEB, recursive = TRUE, showWarnings = FALSE)

# --- Drowned towns (points) with population history for popups -------------
pop <- utils::read.csv(file.path(DIR_DATA, "town_population.csv"), stringsAsFactors = FALSE)
cen <- pop[pop$kind == "census", c("town", "year", "population")]
wide <- reshape(cen, idvar = "town", timevar = "year", direction = "wide")
names(wide) <- sub("population\\.", "pop", names(wide))

# build straight from the source CSV (clean columns, native lon/lat)
tw <- utils::read.csv(file.path(DIR_DATA, "drowned_towns.csv"), stringsAsFactors = FALSE)
tw <- merge(tw, wide, by = "town", all.x = TRUE)
towns_web <- st_as_sf(tw, coords = c("lon", "lat"), crs = CRS_LL)
st_write(towns_web, file.path(DIR_WEB, "towns.geojson"), delete_dsn = TRUE, quiet = TRUE)
msg("wrote map/data/towns.geojson (%d towns w/ population)", nrow(towns_web))

# --- Reservoir (full pool) ------------------------------------------------
res_web <- st_transform(st_simplify(reservoir_ma, dTolerance = 25), CRS_LL)
st_write(res_web, file.path(DIR_WEB, "reservoir.geojson"), delete_dsn = TRUE, quiet = TRUE)

# --- Watershed (dissolved HUC-10), if available ---------------------------
if (!is.null(watershed_ma)) {
  ws_web <- st_transform(st_simplify(watershed_ma, dTolerance = 60), CRS_LL)
  st_write(ws_web, file.path(DIR_WEB, "watershed.geojson"), delete_dsn = TRUE, quiet = TRUE)
  msg("wrote map/data/watershed.geojson")
}

msg("web-export stage complete -> %s", DIR_WEB)
