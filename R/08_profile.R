# 08_profile.R ------------------------------------------------------------
# Valley cross-section: a west-east elevation transect at the reservoir's
# widest point, showing the 530 ft pool over the drowned valley floor that the
# DEM still retains. Water is clipped to the reservoir footprint (so low ground
# outside the basin is not drawn as water). Renders output/11_crosssection.png.
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("dem_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))

POOL_FT <- POOL_M / 0.3048

# Footprint elevations, and the raster row where the reservoir is widest.
demR <- terra::mask(dem_ma, terra::vect(reservoir_ma))
mm   <- matrix(!is.na(terra::values(demR)[, 1]), nrow = terra::nrow(demR), ncol = terra::ncol(demR), byrow = TRUE)
ry   <- which.max(rowSums(mm))
y0   <- terra::yFromRow(demR, ry)
cin  <- which(mm[ry, ])
xr   <- terra::xFromCol(demR, range(cin))

# Sample the DEM along the transect; flag which samples fall inside the footprint.
pad <- 2200
xs  <- seq(min(xr) - pad, max(xr) + pad, length.out = 520)
pts <- terra::vect(cbind(xs, rep(y0, length(xs))), type = "points", crs = terra::crs(dem_ma))
prof <- data.frame(x = xs,
                   elev_ft = terra::extract(dem_ma, pts)[, 2] / 0.3048,
                   inside  = !is.na(terra::extract(demR, pts)[, 2]))
prof <- prof[!is.na(prof$elev_ft), ]
prof$mi <- (prof$x - min(prof$x)) / 1609.34
rr <- rle(prof$inside); prof$run <- rep(seq_along(rr$lengths), rr$lengths)  # contiguous in/out segments

under   <- prof[prof$inside & prof$elev_ft <= POOL_FT, ]
ins     <- prof$elev_ft[prof$inside]
depth   <- round(POOL_FT - min(ins))

# Locator inset
tline <- st_sfc(st_linestring(cbind(range(xs), rep(y0, 2))), crs = CRS_MA)
loc <- ggplot() +
  geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = NA) +
  geom_sf(data = tline, colour = "#c1121f", linewidth = 0.8) +
  theme_void()

g <- ggplot(prof, aes(mi, elev_ft)) +
  geom_ribbon(data = under, aes(ymin = elev_ft, ymax = POOL_FT, group = run), fill = WATER_FILL, alpha = 0.9) +
  geom_hline(yintercept = POOL_FT, colour = WATER_LINE, linetype = "22", linewidth = 0.5) +
  geom_line(colour = "#6b5a48", linewidth = 0.9) +
  annotate("text", x = max(prof$mi), y = POOL_FT, label = "full pool, 530 ft", hjust = 1, vjust = -0.6,
           size = 3.1, colour = WATER_LINE, fontface = "bold") +
  scale_y_continuous(labels = function(z) paste0(z, " ft")) +
  scale_x_continuous(labels = function(z) paste0(z, " mi"), expand = expansion(mult = c(0.01, 0.01))) +
  labs(title = "The drowned valley in cross-section",
       subtitle = "West-east profile across the dendritic reservoir: the 530 ft pool fills each arm of the valley between the hills",
       x = NULL, y = NULL,
       caption = paste0("Surveyed maximum depth is about 150 ft, near Winsor Dam; the DEM's sub-pool values run deeper and are approximate. Vertical scale exaggerated.\n", ATTRIB)) +
  theme_quabbin() +
  theme(panel.grid.major.y = element_line(colour = "#ededed"))

final <- g + patchwork::inset_element(loc, left = 0.02, bottom = 0.58, right = 0.24, top = 1.0, align_to = "panel")
save_map(final, "11_crosssection.png", w = 10, h = 5.5)
msg("wrote 11_crosssection.png (transect max depth ~%d ft)", depth)
