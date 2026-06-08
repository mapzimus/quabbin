# 04_population.R ---------------------------------------------------------
# The human layer, on real numbers:
#   06  the four towns' "lifelines" — chartered across three centuries,
#       all cut off at the same instant (28 April 1938)
#   07  decennial U.S. Census counts 1900-1920 for all four towns (every one
#       already shrinking), then the Water Commission buyouts dashed down to
#       the 1938 disincorporation.
# Census figures: 1920 "Number of Inhabitants, Massachusetts", Table 2.
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("CRS_MA")) source(file.path(QB_DIR, "R", "00_setup.R"))

DISINCORP <- 1938
PALETTE4  <- c(Dana = "#1b9e77", Enfield = "#d95f02", Greenwich = "#7570b3", Prescott = "#e7298a")

towns_df <- utils::read.csv(file.path(DIR_DATA, "drowned_towns.csv"),    stringsAsFactors = FALSE)
pop      <- utils::read.csv(file.path(DIR_DATA, "town_population.csv"),  stringsAsFactors = FALSE)

# --- 06. Town lifelines ---------------------------------------------------
life <- towns_df |>
  dplyr::transmute(town, start = as.integer(incorporated), end = DISINCORP) |>
  dplyr::arrange(start) |>
  dplyr::mutate(town = factor(town, levels = town))

p_life <- ggplot(life) +
  geom_segment(aes(x = start, xend = end, y = town, yend = town, colour = town),
               linewidth = 3.2, lineend = "round", show.legend = FALSE) +
  geom_point(aes(x = start, y = town, colour = town), size = 3, show.legend = FALSE) +
  geom_point(aes(x = end, y = town), colour = INK, shape = 4, size = 3, stroke = 1.1) +
  geom_text(aes(x = start, y = town, label = start), vjust = -1.1, size = 3, colour = "#555555") +
  geom_vline(xintercept = DISINCORP, linetype = "22", colour = "#7a1f1f") +
  annotate("text", x = DISINCORP, y = 0.62, label = "all disincorporated\n28 April 1938",
           hjust = 1.05, vjust = 0, size = 3.1, colour = "#7a1f1f", fontface = "bold", lineheight = 0.9) +
  scale_colour_manual(values = PALETTE4) +
  scale_x_continuous(limits = c(1740, 1960), breaks = seq(1750, 1950, 50)) +
  labs(title = "Four lifelines, one ending",
       subtitle = "Each town was chartered in a different era — and all four were dissolved on the same day",
       x = NULL, y = NULL,
       caption = "Charter & disincorporation dates: town records (Wikipedia town pages).") +
  theme_quabbin() +
  theme(axis.text.y = element_text(face = "bold", size = rel(0.95), colour = INK),
        panel.grid.major.x = element_line(colour = "#ededed"))
save_map(p_life, "06_town_lifelines.png", w = 9, h = 5.5)

# --- 07. Census decline 1900-1920 + buyouts to 1938 -----------------------
census <- pop[pop$kind == "census", ]
diss   <- pop[pop$kind == "dissolved", ]
census$town <- factor(census$town, levels = names(PALETTE4))

# bridge each town from its last census year (1920) down to 1938
last_c <- do.call(rbind, lapply(split(census, census$town), \(d) d[which.max(d$year), ]))
bridge <- rbind(
  data.frame(town = last_c$town, year = last_c$year, population = last_c$population),
  data.frame(town = diss$town,   year = diss$year,   population = diss$population))
lab_left <- census[census$year == min(census$year), ]

p_decline <- ggplot() +
  annotate("rect", xmin = 1920, xmax = DISINCORP, ymin = -Inf, ymax = Inf, fill = "#7a1f1f", alpha = 0.05) +
  geom_line(data = bridge, aes(year, population, group = town, colour = town),
            linetype = "22", linewidth = 0.7, show.legend = FALSE) +
  geom_line(data = census, aes(year, population, colour = town), linewidth = 1.2, show.legend = FALSE) +
  geom_point(data = census, aes(year, population, colour = town), size = 2.6, show.legend = FALSE) +
  geom_point(data = diss, aes(year, population, colour = town), shape = 4, size = 2.8, stroke = 1.1, show.legend = FALSE) +
  geom_vline(xintercept = DISINCORP, linetype = "22", colour = "#7a1f1f") +
  ggrepel::geom_text_repel(data = lab_left, aes(year, population, label = town, colour = town),
            hjust = 1, nudge_x = -2.5, direction = "y", segment.color = NA,
            fontface = "bold", size = 3.5, show.legend = FALSE, seed = 1) +
  annotate("text", x = 1929, y = 1015, label = "Water Commission\nbuyouts, 1928–38",
           size = 3, colour = "#7a1f1f", lineheight = 0.9) +
  annotate("text", x = DISINCORP, y = 470, label = "disincorporated\n1938", hjust = 1.08,
           size = 3, colour = "#7a1f1f", fontface = "bold", lineheight = 0.9) +
  scale_colour_manual(values = PALETTE4) +
  scale_x_continuous(breaks = c(1900, 1910, 1920, 1930, 1938), limits = c(1889, 1946)) +
  scale_y_continuous(limits = c(0, 1100), expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Four towns, already emptying",
       subtitle = "Every one of the four was shrinking for decades before the reservoir — and all were gone by 1938",
       x = NULL, y = "Population",
       caption = paste0(
         "Solid: U.S. Census decennial counts, 1900–1920 (1920 Number of Inhabitants, Massachusetts, Table 2).\n",
         "Dashed: Water Commission buyouts to the 1938 disincorporation. Earlier peaks (not shown): Enfield ~1,100 (1850), Prescott ~750 (1830).")) +
  theme_quabbin() +
  theme(panel.grid.major.y = element_line(colour = "#ededed"),
        axis.title.y = element_text(colour = "#777777", size = rel(0.8)))
save_map(p_decline, "07_population_decline.png", w = 9, h = 6)

msg("population stage complete — census 1900-1920 for all four towns")
msg("about 2,500 residents were displaced in all (commonly cited figure)")
