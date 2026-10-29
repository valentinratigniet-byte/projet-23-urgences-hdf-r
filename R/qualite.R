# Contrôles qualité d'un extrait RPU et indicateurs par établissement.
# Les noms d'anomalies sont ceux du catalogue des défauts (docs/catalogue_defauts.md).

# CIM-10 : lettre + 2 chiffres, puis 0 à 2 chiffres, avec ou sans point (« Z53.2 » ou « Z532 »).
FORMAT_CIM10 <- "^[A-Z][0-9]{2}([.]?[0-9]{1,2})?$"
SEXES_VALIDES <- c("M", "F", "I", "X")          # X : inconnu (code par défaut FEDORU)
NAISSANCE_INCONNUE <- "1800-01-01"              # date par défaut FEDORU, exclue des calculs d'âge
ORIENT_HOSPIT <- c("HDT", "HO", "SDT", "SDRE", "SC", "SI", "REA", "UHCD", "MED", "CHIR", "OBST")
ORIENT_DOMICILE <- c("FUGUE", "PSA", "REO", "SCAM")
SANS_SOINS <- c("PSA", "FUGUE", "REO")          # DP et CCMU non obligatoires pour ces sorties
# Seuils retenus pour ce projet (pas une norme officielle) : tout jour non transmis est une perte sèche.
OBJECTIFS <- c(exhaustivite = 1, completude = 0.95, coherence = 0.95, exploitabilite_dp = 0.95)

DIMENSIONS <- c(
  dp_vide = "Complétude", ccmu_vide = "Complétude", mode_sortie_vide = "Complétude",
  code_postal_vide = "Complétude", destination_vide = "Complétude", dp_invalide = "Exploitabilité du DP",
  sortie_avant_entree = "Cohérence", duree_aberrante = "Cohérence", age_aberrant = "Cohérence",
  sexe_invalide = "Cohérence", deces_ccmu1 = "Cohérence", provenance_incoherente = "Cohérence",
  orientation_incoherente = "Cohérence", doublon = "Cohérence",
  trou_transmission = "Exhaustivité"
)

lire_rpu <- function(fichier) {
  r <- readr::read_csv(fichier, col_types = readr::cols(.default = "c"), na = "")
  r$entree <- as.POSIXct(r$entree, tz = "Europe/Paris")
  r$sortie <- as.POSIXct(r$sortie, tz = "Europe/Paris")
  r$sortie <- corriger_heure_hiver(r$entree, r$sortie)
  r$age <- age_rpu(r)
  r
}

# La nuit du passage à l'heure d'hiver, 02:00-02:59 existe deux fois et le RPU n'indique pas le décalage.
# Une sortie relue moins d'une heure avant l'entrée, toutes deux dans cette heure-là, est la seconde
# occurrence de l'heure : on lui rend son heure. Toute autre sortie avant l'entrée reste une anomalie.
corriger_heure_hiver <- function(entree, sortie) {
  jour <- as.Date(entree, tz = "Europe/Paris")
  decalage <- \(h) format(as.POSIXct(paste(jour, h), tz = "Europe/Paris"), "%z")
  nuit_hiver <- decalage("00:30") == "+0200" & decalage("12:00") == "+0100"
  ambigu <- !is.na(sortie) & nuit_hiver & format(entree, "%H") == "02" & format(sortie, "%H") == "02" &
    sortie < entree & as.numeric(difftime(entree, sortie, units = "mins")) < 60
  sortie[ambigu] <- sortie[ambigu] + 3600
  sortie
}

# Âge en années révolues à l'entrée ; NA si la naissance est inconnue (1800-01-01) ou illisible.
age_rpu <- function(r) {
  naissance <- suppressWarnings(as.Date(r$naissance, optional = TRUE))
  naissance[r$naissance %in% NAISSANCE_INCONNUE] <- NA
  jours <- as.numeric(as.Date(r$entree, tz = "Europe/Paris") - naissance)
  as.integer(floor(jours / 365.25))
}

# Une ligne par anomalie : finess, type_defaut, id_passage (NA pour un trou), date.
# Un doublon est signalé sur la copie : l'original reste un passage valide.
detecter_anomalies <- function(rpu, debut = as.Date("2023-01-01"), fin = as.Date("2023-12-31")) {
  doublon <- duplicated(rpu)
  r <- rpu[!doublon, ]
  age <- age_rpu(r)
  sans_soins <- r$orientation %in% SANS_SOINS
  duree_h <- as.numeric(difftime(r$sortie, r$entree, units = "hours"))

  regles <- list(
    dp_vide             = is.na(r$dp) & !sans_soins,
    ccmu_vide           = is.na(r$ccmu) & !sans_soins,
    mode_sortie_vide    = is.na(r$mode_sortie),
    code_postal_vide    = is.na(r$code_postal),
    destination_vide    = r$mode_sortie %in% c("6", "7") & is.na(r$destination),
    dp_invalide         = !is.na(r$dp) & !grepl(FORMAT_CIM10, r$dp),
    sortie_avant_entree = duree_h < 0,
    duree_aberrante     = duree_h > 72,
    age_aberrant        = !r$naissance %in% NAISSANCE_INCONNUE & (is.na(age) | age < 0 | age > 120),
    sexe_invalide       = !r$sexe %in% SEXES_VALIDES,
    deces_ccmu1         = r$mode_sortie %in% "9" & r$ccmu %in% "1",
    # Provenance 1 à 4 si mutation ou transfert, 5 à 8 si venue du domicile (FEDORU).
    provenance_incoherente = !is.na(r$provenance) &
      ((r$mode_entree %in% c("6", "7") & !r$provenance %in% c("1", "2", "3", "4")) |
       (r$mode_entree %in% "8" & !r$provenance %in% c("5", "6", "7", "8"))),
    # Orientation : liste hospitalisation si mutation/transfert, liste domicile si retour, vide si décès.
    orientation_incoherente = !is.na(r$orientation) &
      ((r$mode_sortie %in% c("6", "7") & !r$orientation %in% ORIENT_HOSPIT) |
       (r$mode_sortie %in% "8" & !r$orientation %in% ORIENT_DOMICILE) |
       r$mode_sortie %in% "9")
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
  champs <- c("dp_vide", "ccmu_vide", "mode_sortie_vide", "code_postal_vide", "destination_vide")
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
