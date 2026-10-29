a_h <- function(h) as.POSIXct("2023-01-01 10:00", tz = "Europe/Paris") + h * 3600

jeu <- function() dplyr::bind_rows(
  hospitalise(id_passage = "A", sortie = a_h(6), naissance = "1940-01-01", transport = "AMBU"),   # 83 ans
  passage(id_passage = "B", sortie = a_h(2), naissance = "2022-06-01"),                          # moins d'1 an
  passage(id_passage = "C", sortie = a_h(1), orientation = "PSA", dp = "Z53.2", ccmu = NA_character_),
  passage(id_passage = "D", sortie = a_h(-1), ccmu = "4")                                        # sortie avant entrée
)

test_that("indicateurs d'activité : chaque calcul écarte les données inexploitables", {
  rpu <- jeu()
  ind <- indicateurs_activite_rpu(rpu, detecter_anomalies(rpu, as.Date("2023-01-01"), as.Date("2023-01-01")))
  e <- ind[ind$finess == "Ensemble", ]
  expect_equal(e$passages, 4)
  expect_equal(e$hospitalisation, 1 / 4)
  expect_equal(e$plus_75_ans, 1 / 4)
  expect_equal(e$moins_1_an, 1 / 4)
  expect_equal(e$transport_sanitaire, 1 / 4)
  expect_equal(e$partis_sans_soins, 1 / 4)
  expect_equal(e$ecartes_duree, 1 / 4)            # D : dates incohérentes
  expect_equal(e$duree_mediane_h, 2)              # médiane de 6, 2 et 1 h
  expect_equal(e$duree_mediane_hospit_h, 6)
  expect_equal(e$plus_4h, 1 / 3)
  expect_equal(e$ccmu_4_5, 1 / 3)                 # C (parti sans soins) n'a pas de CCMU, et ce n'est pas un défaut
  expect_equal(e$ecartes_ccmu, 0)
})

test_that("classes de durée : parts par établissement, passages à dates cohérentes seulement", {
  rpu <- jeu()
  cl <- classes_duree(rpu, detecter_anomalies(rpu, as.Date("2023-01-01"), as.Date("2023-01-01")))
  expect_equal(sum(cl$n), 3)
  expect_equal(sum(cl$part), 1)
  expect_equal(cl$n[cl$classe == "4 à 8 h"], 1)
})
