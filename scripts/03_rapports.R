# Phase 4 : rend tous les rapports dans site/ (panorama, 5 départements, 8 établissements, note ARS).
if (!nzchar(Sys.which("pandoc")) && !nzchar(Sys.getenv("RSTUDIO_PANDOC"))) {
  Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
}
racine <- normalizePath(".")
rendre <- function(rmd, sortie, params = list()) {
  dir.create(dirname(file.path("site", sortie)), recursive = TRUE, showWarnings = FALSE)
  rmarkdown::render(file.path("rapports", rmd), output_file = basename(sortie),
                    output_dir = file.path(racine, "site", dirname(sortie)), params = params,
                    knit_root_dir = racine, intermediates_dir = tempdir(), envir = new.env(), quiet = TRUE)
  message("  ", sortie)
}

args <- commandArgs(trailingOnly = TRUE)   # ex. : Rscript scripts/03_rapports.R panorama
tous <- length(args) == 0

dir.create("site", showWarnings = FALSE)
file.copy("rapports/index.html", "site/index.html", overwrite = TRUE)

if (tous || "panorama" %in% args) rendre("panorama.Rmd", "panorama.html")
if (tous || "departement" %in% args) {
  for (d in c("02", "59", "60", "62", "80")) rendre("departement.Rmd", sprintf("departements/%s.html", d), list(dep = d))
}
if (tous || "qualite" %in% args) {
  source("R/simulation_rpu.R")
  for (f in ETABLISSEMENTS$finess) rendre("qualite.Rmd", sprintf("qualite/%s.html", f), list(finess = f))
}
if (tous || "note" %in% args) {
  rendre("note_ars.Rmd", "note_ars.html")
  # PDF sans LaTeX : impression de la page HTML par Chrome headless.
  chrome <- Filter(nzchar, c(Sys.which(c("google-chrome", "chromium", "chrome")),
                             "C:/Program Files/Google/Chrome/Application/chrome.exe"))
  chrome <- chrome[file.exists(chrome)][1]
  if (is.na(chrome)) stop("Chrome introuvable : impossible de produire site/note_ars.pdf")
  system2(chrome, c("--headless", "--disable-gpu", "--no-sandbox", "--no-pdf-header-footer",
                    paste0("--print-to-pdf=", file.path(racine, "site", "note_ars.pdf")),
                    paste0("file:///", file.path(racine, "site", "note_ars.html"))), stdout = FALSE, stderr = FALSE)
  message("  note_ars.pdf")
}
