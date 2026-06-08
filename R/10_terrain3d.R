# 10_terrain3d.R ----------------------------------------------------------
# A 3D oblique view of the Swift River Valley, with the reservoir drawn as a
# flat pool surface (530 ft) over the real relief. Base-R persp() so it renders
# headless with no extra dependencies. Writes output/13_terrain3d.png.
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("dem_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))

# Coarsen for a clean 3D surface
dem_a <- terra::aggregate(dem_ma, fact = 4, fun = mean, na.rm = TRUE)
hil_a <- terra::aggregate(hill,   fact = 4, fun = mean, na.rm = TRUE)
res_a <- terra::rasterize(terra::vect(reservoir_ma), dem_a)

# orient matrices as z[x, y] with north up (persp wants x=cols, y=rows ascending)
toXY <- function(r) { m <- terra::as.matrix(r, wide = TRUE); t(m[nrow(m):1, ]) }
z  <- toXY(dem_a); hs <- toXY(hil_a); wr <- toXY(res_a)
nx <- nrow(z); ny <- ncol(z)
z[is.na(z)] <- min(z, na.rm = TRUE)

# flat pool surface inside the reservoir footprint
isw <- !is.na(wr)
zlake <- z; zlake[isw] <- POOL_M

# facet colours: hillshade grey for land, flat blue for water
fac_w <- isw[-nx, -ny] | isw[-1, -ny] | isw[-nx, -1] | isw[-1, -1]
hsf   <- (hs[-nx, -ny] + hs[-1, -ny] + hs[-nx, -1] + hs[-1, -1]) / 4
g     <- (hsf - min(hsf, na.rm = TRUE)) / (max(hsf, na.rm = TRUE) - min(hsf, na.rm = TRUE))
g[is.na(g)] <- 0.7
colmat <- matrix(grey(0.4 + 0.55 * g), nx - 1, ny - 1)
colmat[fac_w] <- "#2b6cb0"

png(file.path(DIR_OUTPUT, "13_terrain3d.png"), width = 1200, height = 900, res = 135)
par(mar = c(2.4, 0, 3.2, 0), bg = "white")
persp(x = seq_len(nx), y = seq_len(ny), z = zlake,
      theta = -40, phi = 26, expand = 0.16, scale = TRUE,
      col = colmat, border = NA, box = FALSE, shade = 0.3, ltheta = -50)
title(main = "The Swift River Valley in three dimensions",
      cex.main = 1.25, font.main = 2, col.main = "#1a1a1a")
mtext("The 530 ft reservoir (blue) drawn as a flat pool over the surrounding relief",
      side = 3, line = 0.3, cex = 0.85, col = "#555555")
mtext("Terrain: AWS Terrain Tiles (SRTM/USGS). Vertical scale exaggerated; reservoir surface shown flat at full pool.",
      side = 1, line = 1.1, cex = 0.62, col = "#888888")
dev.off()
msg("wrote 13_terrain3d.png")
