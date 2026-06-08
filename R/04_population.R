# 04_population.R ---------------------------------------------------------
# The human layer. Popular sources give well-documented anchor figures rather
# than a clean per-decade table for all four towns, so this stays honest:
#   06  the four towns' "lifelines" — each incorporated in a different century,
#       all cut off at the same instant (28 April 1938)
#   07  Prescott, the best-documented town: a textbook rural decline that the
#       reservoir merely finished (750 in 1830 -> ~300 by 1900 -> ~18 -> 0)
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("CRS_MA")) source(file.path(QB_DIR, "R", "00_setup.R"))

DISINCORP <- 1938
PALETTE4  <- c(Dana = "#1b9e77", Enfield = "#d95f02", Greenwich = "#7570b3", Prescott = "#e7298a")

towns_df <- utils::read.csv(file.path(DIR_DATA, "drowned_towns.csv"), stringsAsFactors = FALSE)
pop_df   <- utils::read.csv(file.path(DIR_DATA, "town_population.csv"), stringsAsFactors = FALSE)

# --- 06. Town lifelines ---------------------------------------------------
life <- towns_df |>
  dplyr::transmute(town,
                   start = as.integer(incorporated),
                   end   = DISINCORP,
                   span  = end - start) |>
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

# --- 07. Prescott decline -------------------------------------------------
pres <- dplyr::filter(pop_df, town == "Prescott") |> dplyr::arrange(year)

p_pres <- ggplot(pres, aes(year, population)) +
  geom_area(fill = PALETTE4["Prescott"], alpha = 0.12) +
  geom_line(colour = PALETTE4["Prescott"], linewidth = 1.1) +
  geom_point(colour = PALETTE4["Prescott"], size = 3) +
  ggrepel::geom_text_repel(aes(label = scales::comma(population)),
                           size = 3.2, fontface = "bold", colour = INK,
                           direction = "y", min.segment.length = 0, seed = 1) +
  annotate("label", x = 1844, y = 690,
           label = "peak: a hill town\nof farms & mills", hjust = 0, vjust = 1,
           size = 3, colour = "#666666", lineheight = 0.9,
           fill = "white", alpha = 0.65, label.size = 0) +
  scale_y_continuous(limits = c(0, 800), expand = expansion(mult = c(0, 0.05))) +
  scale_x_continuous(limits = c(1825, 1945), breaks = seq(1830, 1940, 20)) +
  labs(title = "Prescott was dying long before the water came",
       subtitle = "The smallest of the four towns: ~750 residents in 1830, barely 18 by 1938",
       x = NULL, y = "Population",
       caption = "Figures: NEHGS Vita Brevis; Wikipedia. Documented anchor points, not a full decennial series.") +
  theme_quabbin() +
  theme(panel.grid.major.y = element_line(colour = "#ededed"),
        axis.title.y = element_text(colour = "#777777", size = rel(0.8)))
save_map(p_pres, "07_population_decline.png", w = 8, h = 6)

msg("population stage complete")
msg("about 2,500 residents were displaced in all (commonly cited figure)")
