# 13_roads.R --------------------------------------------------------------
# How the valley connected: the principal road links between the four drowned
# towns and out to their surviving neighbours. A connectivity diagram -- node
# positions are town centres; links are the principal roads shown on the 1893
# USGS quadrangle, drawn schematically (not exact alignments). The precise
# historic roads are visible in the 1893 overlay in the interactive map.
# Renders output/16_roads.png.
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("reservoir_ma")) source(file.path(QB_DIR, "R", "02_build_layers.R"))

tw <- utils::read.csv(file.path(DIR_DATA, "drowned_towns.csv"), stringsAsFactors = FALSE)

nodes <- rbind(
  data.frame(name = tw$town, lon = tw$lon, lat = tw$lat, kind = "drowned"),
  data.frame(name = c("Petersham", "New Salem", "Belchertown", "Ware", "Hardwick", "Pelham", "Shutesbury"),
             lon  = c(-72.189,     -72.325,     -72.401,       -72.240, -72.199,    -72.404,  -72.408),
             lat  = c( 42.487,      42.502,      42.277,        42.261,  42.350,     42.392,   42.454),
             kind = "neighbour"))

# principal links (valley spine + connections out), from the 1893 quad pattern
edges <- rbind(
  c("Enfield", "Greenwich"), c("Greenwich", "Dana"), c("Greenwich", "Prescott"),
  c("Enfield", "Prescott"),  c("Enfield", "Belchertown"), c("Enfield", "Ware"),
  c("Greenwich", "Hardwick"), c("Dana", "Petersham"), c("Dana", "New Salem"),
  c("Prescott", "Pelham"), c("Prescott", "Shutesbury"), c("Greenwich", "New Salem"))

nm <- st_transform(st_as_sf(nodes, coords = c("lon", "lat"), crs = CRS_LL), CRS_MA)
nodes$X <- st_coordinates(nm)[, 1]; nodes$Y <- st_coordinates(nm)[, 2]
ix  <- setNames(seq_len(nrow(nodes)), nodes$name)
seg <- data.frame(x = nodes$X[ix[edges[, 1]]], y = nodes$Y[ix[edges[, 1]]],
                  xend = nodes$X[ix[edges[, 2]]], yend = nodes$Y[ix[edges[, 2]]])
dn <- nodes[nodes$kind == "drowned", ]; nb <- nodes[nodes$kind == "neighbour", ]
padx <- 2500; pady <- 2500

p_roads <- ggplot() +
  geom_sf(data = reservoir_ma, fill = WATER_FILL, colour = NA, alpha = 0.45) +
  geom_segment(data = seg, aes(x, y, xend = xend, yend = yend), colour = "#8a6d3b", linewidth = 0.7) +
  geom_point(data = nb, aes(X, Y), shape = 21, fill = "white", colour = "#888888", size = 2.4, stroke = 0.6) +
  geom_point(data = dn, aes(X, Y), shape = 21, fill = "#7a1f1f", colour = "white", size = 4, stroke = 0.6) +
  ggrepel::geom_text_repel(data = nb, aes(X, Y, label = name), size = 3, colour = "#666666",
                           seed = 1, box.padding = 0.4, min.segment.length = 0.4) +
  ggrepel::geom_text_repel(data = dn, aes(X, Y, label = name), size = 3.5, colour = "#7a1f1f",
                           fontface = "bold", seed = 1, box.padding = 0.5, min.segment.length = 0.4) +
  coord_sf(crs = st_crs(CRS_MA), datum = NA,
           xlim = c(min(nodes$X) - padx, max(nodes$X) + padx),
           ylim = c(min(nodes$Y) - pady, max(nodes$Y) + pady), expand = FALSE) +
  labs(title = "Roads of the Swift River Valley, about 1893",
       subtitle = "How the four towns (red) connected to each other and to their surviving neighbours",
       caption = paste0("Connectivity diagram: nodes are town centres; links are principal 1893 roads, drawn schematically (not exact alignments).\n",
                        "Reservoir shown in blue for reference.")) +
  theme_quabbin() +
  theme(axis.text = element_blank())
save_map(p_roads, "16_roads.png", w = 9, h = 8)
msg("wrote 16_roads.png")
