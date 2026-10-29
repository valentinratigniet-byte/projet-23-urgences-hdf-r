# Socle commun aux rapports : fonctions du projet, données, thème graphique, formats français.
for (f in list.files("R", full.names = TRUE)) source(f, encoding = "UTF-8")
suppressPackageStartupMessages(library(ggplot2))

knitr::opts_chunk$set(echo = FALSE, message = FALSE, warning = FALSE,
                      fig.width = 9, fig.height = 4.2, dpi = 110, fig.align = "center")

passages <- readr::read_csv("data/passages_hdf.csv", show_col_types = FALSE, col_types = readr::cols(dep = "c"))
epidemies <- readr::read_csv("data/epidemies_hdf.csv", show_col_types = FALSE, col_types = readr::cols(dep = "c"))
NOMS_DEP <- c("02" = "Aisne", "59" = "Nord", "60" = "Oise", "62" = "Pas-de-Calais", "80" = "Somme", "FR" = "France")

# Palette catégorielle de référence (validée CVD, ordre fixe) ; la France est la référence neutre.
COULEURS_DEP <- c("59" = "#2a78d6", "62" = "#eb6834", "60" = "#1baf7a", "02" = "#eda100", "80" = "#e87ba4",
                  "FR" = "#52514e")
COULEURS_PATHO <- c(grippe = "#2a78d6", bronchiolite = "#eb6834", gastro = "#1baf7a")
ENCRE <- "#52514e"

theme_set(
  theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(colour = "#e6e5e1", linewidth = 0.3),
          axis.text = element_text(colour = ENCRE), axis.title = element_text(colour = ENCRE, size = 9.5),
          plot.title = element_text(face = "bold", size = 12), plot.title.position = "plot",
          plot.caption = element_text(colour = "#8a8985", size = 8.5, hjust = 0),
          legend.position = "top", legend.justification = "left", strip.text = element_text(face = "bold"))
)

nb <- function(x, acc = 1) scales::number(x, accuracy = acc, big.mark = " ", decimal.mark = ",")
pct <- function(x, acc = 0.1, signe = FALSE) {
  scales::percent(x, accuracy = acc, big.mark = " ", decimal.mark = ",", style_positive = if (signe) "plus" else "none")
}
axe_nb <- scales::label_number(big.mark = " ", decimal.mark = ",")
axe_pct <- scales::label_percent(decimal.mark = ",")

SOURCE_DREES <- "Source : DREES, séries longues des passages aux urgences 2017-2023 (valeurs journalières estimées)."
SOURCE_ODISSE <- "Sources : DREES ; Santé publique France, ODISSE (taux pour 100 000 passages)."

tableau <- function(d) {
  gt::gt(d) |>
    gt::tab_options(table.font.size = gt::px(13), column_labels.font.weight = "bold",
                    table.border.top.style = "hidden", data_row.padding = gt::px(4))
}
