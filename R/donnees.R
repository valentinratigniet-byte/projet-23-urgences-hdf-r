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
# SAE 2023, base administrative (DREES) : un service d'urgence par ligne (URG = GEN ou PED).
URL_SAE <- paste0("https://data.drees.solidarites-sante.gouv.fr/api/datasets/1.0/707_bases-administratives-sae/",
                  "attachments/sae_2023_base_administrative_formats_sas_csv_zip")
# Contours des départements (Etalab, d'après OpenStreetMap, licence ODbL), résolution 100 m.
URL_CONTOURS <- "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/2023/geojson/departements-100m.geojson"
# INSEE, estimations de population au 1er janvier par département (édition du 23/12/2025, années récentes révisables).
URL_INSEE_POP <- "https://www.insee.fr/fr/statistiques/fichier/8721456/estim-pop-dep-sexe-gca-1975-2026.xlsx"

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

# Population au 1er janvier, une ligne par département et par année (un onglet par année dans le fichier).
lire_population <- function(annees = 2017:2023, dossier = "data/raw") {
  f <- telecharger(URL_INSEE_POP, file.path(dossier, "insee_population_dep.xlsx"))
  purrr::map(annees, function(an) {
    # 5 lignes d'en-tête ; colonnes : code, libellé, 5 classes d'âge, total (« Ensemble »)
    d <- readxl::read_excel(f, sheet = as.character(an), skip = 5, col_names = FALSE, .name_repair = "minimal")
    d <- d[grepl("^([0-9]{2,3}|2A|2B)$", d[[1]]), 1:8]
    tibble::tibble(dep = d[[1]], annee = an, population = as.numeric(d[[8]]))
  }) |> purrr::list_rbind()
}

# Services d'urgence des 5 départements : passages, dont 80 ans et plus, moins de 18 ans, et hospitalisés
# (MCO, SMR-PSY-USLD et HAD dans la même entité juridique ; dtEXT : dans une autre entité juridique).
lire_sae_urgences <- function(dossier = "data/raw") {
  zip <- telecharger(URL_SAE, file.path(dossier, "sae_2023_base_administrative.zip"))
  base <- "SAE 2023 Base administrative - Formats SAS-CSV/Base CSV/"
  sortie <- file.path(tempdir(), "sae2023")
  utils::unzip(zip, files = paste0(base, c("ID_2023.csv", "URGENCES2_2023.csv")), exdir = sortie)
  lire <- \(f) readr::read_delim(file.path(sortie, base, f), delim = ";", show_col_types = FALSE,
                                 locale = readr::locale(encoding = "latin1"), col_types = readr::cols(.default = "c"))
  id <- lire("ID_2023.csv")
  num <- c("PASSU", "dt80", "dt18", "dtMCO", "dtLS", "dtHAD", "dtEXT", "LIT_UHCD", "SEJ_UHCD")
  lire("URGENCES2_2023.csv") |>
    dplyr::inner_join(dplyr::select(id, FI, dep = DEP), by = "FI") |>
    dplyr::filter(dep %in% DEPS_HDF) |>
    dplyr::select(finess = FI, etablissement = RS, dep, type = URG, dplyr::all_of(num)) |>
    dplyr::mutate(dplyr::across(dplyr::all_of(num), as.numeric)) |>
    dplyr::arrange(dep, dplyr::desc(PASSU))
}

# Contour de chaque département des Hauts-de-France, en points de polygone (tracé par ggplot, sans sf).
lire_contours <- function(dossier = "data/raw") {
  f <- telecharger(URL_CONTOURS, file.path(dossier, "contours_departements.geojson"))
  g <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  purrr::map(g$features, function(ft) {
    dep <- ft$properties$code
    if (!dep %in% DEPS_HDF) return(NULL)
    polys <- if (ft$geometry$type == "Polygon") list(ft$geometry$coordinates) else ft$geometry$coordinates
    # Anneau 1 : contour extérieur ; les suivants sont des trous (enclaves), tracés avec subgroup.
    purrr::imap(polys, function(p, k) purrr::imap(p, function(points, a) {
      tibble::tibble(dep = dep, morceau = k, anneau = a,
                     lon = purrr::map_dbl(points, 1), lat = purrr::map_dbl(points, 2))
    }) |> purrr::list_rbind()) |> purrr::list_rbind()
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

controler_population <- function(pop, annees = 2017:2023) {
  hdf <- pop[pop$dep %in% DEPS_HDF, ]
  stopifnot(
    "5 départements HDF chaque année" = nrow(hdf) == 5 * length(annees),
    "aucun doublon" = !anyDuplicated(pop[c("dep", "annee")]),
    "populations HDF plausibles (300 000 à 3 millions)" = all(hdf$population > 3e5 & hdf$population < 3e6)
  )
  invisible(pop)
}

controler_sae <- function(sae) {
  stopifnot(
    "5 départements HDF" = setequal(unique(sae$dep), DEPS_HDF),
    "un service par établissement et par type" = !anyDuplicated(sae[c("finess", "type")]),
    "nombre de passages renseigné partout" = !anyNA(sae$PASSU),
    "types GEN ou PED" = all(sae$type %in% c("GEN", "PED"))
  )
  invisible(sae)
}
