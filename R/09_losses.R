# 09_losses.R -------------------------------------------------------------
# "By the numbers": documented quantities of what was removed from the Swift
# River Valley and what the reservoir provides. Renders output/12_losses.png.
# Figures are compiled from published sources (see caption) and several vary
# between sources; ranges are noted rather than implying false precision.
# -------------------------------------------------------------------------

if (!exists("QB_DIR")) QB_DIR <- if (basename(getwd()) == "quabbin") getwd() else file.path(getwd(), "quabbin")
if (!exists("CRS_MA")) source(file.path(QB_DIR, "R", "00_setup.R"))

stats <- data.frame(
  value = c("4", "~2,500", "~7,500", "1,000+",
            "39 sq mi", "412 bn gal", "181 mi", "2.7M"),
  label = c("towns disincorporated, 1938", "residents displaced", "graves relocated", "buildings razed",
            "of water surface", "at full pool", "of shoreline", "people now supplied"),
  kind  = c(rep("lost", 4), rep("built", 4)),
  stringsAsFactors = FALSE)
stats$col <- (seq_len(nrow(stats)) - 1) %% 4
stats$row <- ifelse((seq_len(nrow(stats)) - 1) %/% 4 == 0, 0, -1.25)

p_losses <- ggplot(stats) +
  geom_text(aes(col, row, label = value, colour = kind), size = 8, fontface = "bold", vjust = 0.2) +
  geom_text(aes(col, row - 0.32, label = label), size = 3.4, colour = "#555555", vjust = 1, lineheight = 0.9) +
  annotate("text", x = -0.35, y = 0.62, label = "WHAT THE VALLEY LOST", hjust = 0, fontface = "bold",
           size = 3.3, colour = "#9b2226") +
  annotate("text", x = -0.35, y = -0.63, label = "WHAT THE RESERVOIR PROVIDES", hjust = 0, fontface = "bold",
           size = 3.3, colour = "#1f6fb0") +
  scale_colour_manual(values = c(lost = "#9b2226", built = "#1f6fb0"), guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0.16, 0.13))) +
  scale_y_continuous(expand = expansion(mult = c(0.16, 0.18))) +
  labs(title = "The Quabbin in numbers",
       subtitle = "What was removed from the Swift River Valley, and what the reservoir supplies today",
       x = NULL, y = NULL,
       caption = paste0(
         "Compiled from MWRA, Massachusetts DCR, and regional histories; figures vary by source ",
         "(displaced residents reported as 2,000-2,500; graves relocated as ~6,600-7,600). ",
         "Dam sealed 1939; full pool reached 1946.")) +
  theme_quabbin() +
  theme(axis.text = element_blank(), axis.ticks = element_blank(),
        panel.grid = element_blank(), axis.title = element_blank())
save_map(p_losses, "12_losses.png", w = 13, h = 5.5)
msg("wrote 12_losses.png")
