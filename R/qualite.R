# Contrôles qualité d'un extrait RPU et indicateurs par établissement.
# Les noms d'anomalies sont ceux du catalogue des défauts (docs/catalogue_defauts.md).

FORMAT_CIM10 <- "^[A-Z][0-9]{2}[0-9]{0,2}$"   # format RPU : sans point, 3 à 5 caractères
SEXES_VALIDES <- c("M", "F", "I")
# Seuils retenus pour ce projet (pas une norme officielle) : tout jour non transmis est une perte sèche.
OBJECTIFS <- c(exhaustivite = 1, completude = 0.95, coherence = 0.95, exploitabilite_dp = 0.95)

DIMENSIONS <- c(
  dp_vide = "Complétude", ccmu_vide = "Complétude", mode_sortie_vide = "Complétude",
  code_postal_vide = "Complétude", dp_invalide = "Exploitabilité du DP",
  sortie_avant_entree = "Cohérence", duree_aberrante = "Cohérence", age_aberrant = "Cohérence",
  sexe_invalide = "Cohérence", deces_ccmu1 = "Cohérence", doublon = "Cohérence",
  trou_transmission = "Exhaustivité"
)

lire_rpu <- function(fichier) {
  r <- readr::read_csv(fichier, col_types = readr::cols(.default = "c"), na = "")
  r$entree <- as.POSIXct(r$entree, tz = "Europe/Paris")
  r$sortie <- as.POSIXct(r$sortie, tz = "Europe/Paris")
  r
}

# Une ligne par anomalie : finess, type_defaut, id_passage (NA pour un trou), date.
# Un doublon est signalé sur la copie : l'original reste un passage valide.
detecter_anomalies <- function(rpu, debut = as.Date("2023-01-01"), fin = as.Date("2023-12-31")) {
  doublon <- duplicated(rpu)
  r <- rpu[!doublon, ]
  age <- suppressWarnings(as.integer(r$age))
  duree_h <- as.numeric(difftime(r$sortie, r$entree, units = "hours"))

  regles <- list(
    dp_vide             = is.na(r$dp),
    ccmu_vide           = is.na(r$ccmu),
    mode_sortie_vide    = is.na(r$mode_sortie),
    code_postal_vide    = is.na(r$code_postal),
    dp_invalide         = !is.na(r$dp) & !grepl(FORMAT_CIM10, r$dp),
    sortie_avant_entree = duree_h < 0,
    duree_aberrante     = duree_h > 72,
    age_aberrant        = is.na(age) | age < 0 | age > 120,
    sexe_invalide       = !r$sexe %in% SEXES_VALIDES,
    deces_ccmu1         = r$mode_sortie %in% "9" & r$ccmu %in% "1"
  )
  par_passage <- purrr::imap(regles, \(ko, type) tibble::tibble(
    finess = r$finess[ko], type_defaut = type, id_passage = r$id_passage[ko],
    date = as.Date(r$entree[ko], tz = "Europe/Paris")))

  doublons <- tibble::tibble(finess = rpu$finess[doublon], type_defaut = "doublon",
                             id_passage = rpu$id_passage[doublon],
                             date = as.Date(rpu$entree[doublon], tz = "Europe/Paris"))

  jours <- seq(debut, fin, by = "day")
  trous <- purrr::map(unique(rpu$finess), function(f) {
    manquants <- setdiff(jours, as.Date(rpu$entree[rpu$finess == f], tz = "Europe/Paris"))
    tibble::tibble(finess = f, type_defaut = "trou_transmission", id_passage = NA_character_,
                   date = as.Date(manquants))
  })

  purrr::list_rbind(c(par_passage, list(doublons), trous))
}

# Indicateurs par établissement, chacun entre 0 et 1, et score global = moyenne des 4 dimensions.
indicateurs_qualite <- function(rpu, anomalies, debut = as.Date("2023-01-01"), fin = as.Date("2023-12-31")) {
  nb_jours <- as.numeric(fin - debut) + 1
  champs <- c("dp_vide", "ccmu_vide", "mode_sortie_vide", "code_postal_vide")
  coherence <- names(DIMENSIONS)[DIMENSIONS == "Cohérence"]

  passages <- dplyr::count(rpu[!duplicated(rpu), ], finess, etablissement, name = "passages")
  compte <- dplyr::count(anomalies, finess, type_defaut) |>
    tidyr::pivot_wider(names_from = type_defaut, values_from = n, values_fill = 0)
  for (t in setdiff(names(DIMENSIONS), names(compte))) compte[[t]] <- 0L
  # Un passage peut cumuler plusieurs incohérences : on compte des passages distincts.
  incoherents <- anomalies[anomalies$type_defaut %in% coherence, ] |>
    dplyr::summarise(passages_incoherents = dplyr::n_distinct(id_passage), .by = finess)

  dplyr::left_join(passages, compte, by = "finess") |>
    dplyr::left_join(incoherents, by = "finess") |>
    dplyr::mutate(
      dplyr::across(c(dplyr::all_of(names(DIMENSIONS)), passages_incoherents), \(x) dplyr::coalesce(x, 0L)),
      exhaustivite   = 1 - trou_transmission / nb_jours,
      completude     = 1 - rowSums(dplyr::pick(dplyr::all_of(champs))) / (length(champs) * passages),
      coherence      = 1 - passages_incoherents / passages,
      exploitabilite_dp = 1 - (dp_vide + dp_invalide) / passages,
      score          = (exhaustivite + completude + coherence + exploitabilite_dp) / 4
    ) |>
    dplyr::arrange(score)
}

# Les n anomalies à traiter en priorité : les jours non transmis d'abord (toutes les données du jour
# sont perdues), puis les plus fréquentes.
actions_prioritaires <- function(anomalies, finess_cible, n = 3) {
  anomalies[anomalies$finess == finess_cible, ] |>
    dplyr::count(type_defaut) |>
    dplyr::arrange(type_defaut != "trou_transmission", dplyr::desc(n)) |>
    dplyr::mutate(dimension = DIMENSIONS[type_defaut]) |>
    utils::head(n)
}
