# Passage RPU conforme de référence, modifiable champ par champ dans les tests.
passage <- function(...) {
  base <- tibble::tibble(
    id_passage = "X-1", finess = "X", etablissement = "Test", dep = "59", code_postal = "59000",
    naissance = "1983-05-10", sexe = "F",
    entree = as.POSIXct("2023-01-01 10:00", tz = "Europe/Paris"), mode_entree = "8", provenance = "5",
    transport = "PERSO", transport_pec = "AUCUN", motif = "R104",
    ccmu = "2", dp = "R104", liste_da = NA_character_,
    sortie = as.POSIXct("2023-01-01 13:00", tz = "Europe/Paris"), mode_sortie = "8",
    destination = NA_character_, orientation = NA_character_
  )
  modifs <- list(...)
  base[names(modifs)] <- modifs
  base
}
detecter_un_jour <- function(rpu) {
  detecter_anomalies(rpu, as.Date("2023-01-01"), as.Date("2023-01-01"))$type_defaut
}
hospitalise <- function(...) {
  do.call(passage, utils::modifyList(list(mode_sortie = "6", destination = "1", orientation = "MED"), list(...)))
}

