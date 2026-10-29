# Téléchargement et contrôles d'entrée des données réelles (DREES, Santé publique France).

DEPS_HDF <- c("02", "59", "60", "62", "80")

URL_DREES <- paste0(
  "https://data.drees.solidarites-sante.gouv.fr/api/explore/v2.1/catalog/datasets/",
  "series_longues_passages_urgences_2017_2023/exports/csv?delimiter=%3B"
)
URL_ODISSE <- "https://odisse.santepubliquefrance.fr/api/explore/v2.1/catalog/datasets/%s/exports/csv?delimiter=%%3B&where=reg%%3D%%2232%%22"
JEUX_ODISSE <- c(
  grippe       = "grippe-passages-aux-urgences-et-actes-sos-medecins-departement",
  bronchiolite = "bronchiolite-passages-aux-urgences-et-actes-sos-medecins-departement",
  gastro       = "gastro-enterite-aigue-passages-aux-urgences-et-actes-sos-medecins-departement"
)

# Télécharge une fois, puis relit le cache local (data/raw/ n'est pas versionné).
telecharger <- function(url, fichier) {
  if (!file.exists(fichier)) {
    dir.create(dirname(fichier), recursive = TRUE, showWarnings = FALSE)
    utils::download.file(url, fichier, mode = "wb", quiet = TRUE)
  }
  fichier
}

lire_passages <- function(dossier = "data/raw") {
  f <- telecharger(URL_DREES, file.path(dossier, "drees_passages_2017_2023.csv"))
  readr::read_delim(f, delim = ";", show_col_types = FALSE,
                    col_types = readr::cols(date = "D", dep = "c", libelle_dep = "c", nb_passages = "d"))
}

# Une ligne par semaine, département et pathologie, tous âges (bronchiolite : moins de 1 an seulement).
# Taux = passages pour la pathologie pour 100 000 passages toutes causes.
lire_epidemies <- function(dossier = "data/raw") {
  purrr::imap(JEUX_ODISSE, function(id, patho) {
    f <- telecharger(sprintf(URL_ODISSE, id), file.path(dossier, paste0("odisse_", patho, ".csv")))
    d <- readr::read_delim(f, delim = ";", show_col_types = FALSE, col_types = readr::cols(.default = "c"))
    d <- d[d$sursaud_cl_age_gene %in% c("Tous âges", "0 an"), ]
    tibble::tibble(
      semaine = as.Date(substr(d$date_complet, 1, 10)),
      dep = d$dep,
      pathologie = patho,
      taux_passages = as.numeric(d[[grep("^taux_passages_", names(d))]])
    )
  }) |> purrr::list_rbind()
}

# Contrôles d'entrée : arrête le traitement si la source a changé de forme.
controler_passages <- function(p) {
  jours <- seq(as.Date("2017-01-01"), as.Date("2023-12-31"), by = "day")
  hdf <- p[p$dep %in% DEPS_HDF, ]
  stopifnot(
    "colonnes attendues" = all(c("date", "dep", "libelle_dep", "nb_passages") %in% names(p)),
    "5 départements HDF présents" = setequal(unique(hdf$dep), DEPS_HDF),
    "aucun doublon date x dep" = !anyDuplicated(p[c("date", "dep")]),
    "calendrier complet en HDF" = all(table(hdf$dep) == length(jours)),
    "aucun volume manquant ou négatif en HDF" = all(!is.na(hdf$nb_passages) & hdf$nb_passages >= 0)
  )
  invisible(p)
}

controler_epidemies <- function(e) {
  stopifnot(
    "3 pathologies" = setequal(unique(e$pathologie), names(JEUX_ODISSE)),
    "5 départements HDF" = setequal(unique(e$dep), DEPS_HDF),
    "dates valides" = !anyNA(e$semaine),
    "aucun doublon" = !anyDuplicated(e[c("semaine", "dep", "pathologie")])
  )
  invisible(e)
}
