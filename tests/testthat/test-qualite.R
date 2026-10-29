passage <- function(...) {
  base <- tibble::tibble(
    id_passage = "X-1", finess = "X", etablissement = "Test", dep = "59",
    entree = as.POSIXct("2023-01-01 10:00", tz = "Europe/Paris"),
    sortie = as.POSIXct("2023-01-01 13:00", tz = "Europe/Paris"),
    age = "40", sexe = "F", code_postal = "59000", transport = "PERSO",
    ccmu = "2", dp = "R104", mode_sortie = "8"
  )
  modifs <- list(...)
  base[names(modifs)] <- modifs
  base
}
detecter_un_jour <- function(rpu) {
  detecter_anomalies(rpu, as.Date("2023-01-01"), as.Date("2023-01-01"))$type_defaut
}

test_that("un passage conforme ne déclenche aucune anomalie", {
  expect_length(detecter_un_jour(passage()), 0)
})

test_that("chaque règle détecte son défaut", {
  cas <- list(
    dp_vide = passage(dp = NA_character_),
    ccmu_vide = passage(ccmu = NA_character_),
    mode_sortie_vide = passage(mode_sortie = NA_character_),
    code_postal_vide = passage(code_postal = NA_character_),
    dp_invalide = passage(dp = "R50.9"),
    sortie_avant_entree = passage(sortie = as.POSIXct("2023-01-01 09:00", tz = "Europe/Paris")),
    duree_aberrante = passage(sortie = as.POSIXct("2023-01-05 10:00", tz = "Europe/Paris")),
    age_aberrant = passage(age = "131"),
    sexe_invalide = passage(sexe = "X"),
    deces_ccmu1 = passage(ccmu = "1", mode_sortie = "9")
  )
  for (type in names(cas)) expect_identical(detecter_un_jour(cas[[type]]), type, info = type)
})

test_that("les cas limites restent conformes", {
  expect_length(detecter_un_jour(passage(dp = "R51", age = "0", sexe = "I")), 0)
  expect_length(detecter_un_jour(passage(sortie = as.POSIXct("2023-01-04 10:00", tz = "Europe/Paris"))), 0) # 72 h pile
  expect_length(detecter_un_jour(passage(ccmu = "5", mode_sortie = "9")), 0)
})

test_that("un doublon est signalé une seule fois, sur la copie", {
  expect_identical(detecter_un_jour(dplyr::bind_rows(passage(), passage())), "doublon")
})

test_that("un jour sans passage est un trou de transmission", {
  a <- detecter_anomalies(passage(), as.Date("2023-01-01"), as.Date("2023-01-03"))
  expect_identical(a$type_defaut, rep("trou_transmission", 2))
  expect_identical(a$date, as.Date(c("2023-01-02", "2023-01-03")))
})

test_that("la cohérence compte les passages, pas les anomalies", {
  rpu <- dplyr::bind_rows(passage(age = "150", sexe = "X"), passage(id_passage = "X-2"))
  ind <- indicateurs_qualite(rpu, detecter_anomalies(rpu, as.Date("2023-01-01"), as.Date("2023-01-01")),
                             as.Date("2023-01-01"), as.Date("2023-01-01"))
  expect_equal(ind$coherence, 0.5)
  expect_equal(ind$exhaustivite, 1)
})

test_that("les contrôles retrouvent exactement les défauts injectés dans l'extrait simulé", {
  rpu <- lire_rpu(test_path("../../data/rpu_simule_2023.csv.gz"))
  attendu <- readr::read_csv(test_path("../../data/rpu_defauts_injectes.csv"),
                             col_types = readr::cols(date = "D", .default = "c"), na = "")
  trouve <- detecter_anomalies(rpu)
  cle <- \(d) sort(paste(d$finess, d$type_defaut, d$id_passage, d$date))
  manquants <- setdiff(cle(attendu), cle(trouve))
  en_trop <- setdiff(cle(trouve), cle(attendu))
  expect_length(manquants, 0)
  expect_length(en_trop, 0)
  expect_identical(nrow(trouve), nrow(attendu))
})

test_that("le score classe les établissements selon leur qualité simulée", {
  rpu <- lire_rpu(test_path("../../data/rpu_simule_2023.csv.gz"))
  ind <- indicateurs_qualite(rpu, detecter_anomalies(rpu))
  expect_true(all(ind$score > 0 & ind$score <= 1))
  expect_identical(ind$finess[1], "SIM60A")                       # 35 % de DP vides
  expect_true(all(c("SIM59A", "SIM02A") %in% utils::tail(ind$finess, 2)))  # profils « bonne »
  expect_lt(ind$exhaustivite[ind$finess == "SIM62B"], 1)
})

test_that("toutes les entrées simulées tombent en 2023, heure de Paris", {
  rpu <- lire_rpu(test_path("../../data/rpu_simule_2023.csv.gz"))
  jours <- as.Date(rpu$entree, tz = "Europe/Paris")
  expect_true(all(jours >= as.Date("2023-01-01") & jours <= as.Date("2023-12-31")))
  expect_true(any(format(rpu$entree, "%H") == "00"))   # des arrivées entre minuit et 1 h existent
})

test_that("les jours non transmis passent en tête des actions prioritaires", {
  a <- tibble::tibble(finess = "X", type_defaut = c(rep("dp_vide", 50), "trou_transmission"),
                      id_passage = NA_character_, date = as.Date("2023-01-01"))
  expect_identical(actions_prioritaires(a, "X")$type_defaut, c("trou_transmission", "dp_vide"))
})
