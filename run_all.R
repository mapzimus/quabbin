#!/usr/bin/env Rscript
# run_all.R ---------------------------------------------------------------
# One-command reproduction of the Quabbin study.
#   Rscript quabbin/run_all.R          # from the repo root
# Sources the numbered scripts in order in a single session; rasters stay in
# memory between stages. Downloaded data is cached under quabbin/data/cache/
# so re-runs are fast and offline-friendly.
# -------------------------------------------------------------------------

get_script_dir <- function() {
  a <- commandArgs(FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m)) return(dirname(normalizePath(sub("^--file=", "", m[1]))))
  getwd()
}
QB_DIR <- get_script_dir()

t0 <- Sys.time()
source(file.path(QB_DIR, "R", "00_setup.R"))
source(file.path(QB_DIR, "R", "01_fetch_data.R"))
source(file.path(QB_DIR, "R", "02_build_layers.R"))
source(file.path(QB_DIR, "R", "03_maps.R"))
source(file.path(QB_DIR, "R", "04_population.R"))
source(file.path(QB_DIR, "R", "05_floodfill.R"))
source(file.path(QB_DIR, "R", "06_aqueduct.R"))
source(file.path(QB_DIR, "R", "07_export_web.R"))

pngs <- list.files(DIR_OUTPUT, pattern = "\\.png$")
msg("DONE in %.0f s - %d figure(s) in %s",
    as.numeric(difftime(Sys.time(), t0, units = "secs")), length(pngs), DIR_OUTPUT)
cat(paste0("  - ", pngs, collapse = "\n"), "\n")
