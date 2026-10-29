test_that("un passage conforme ne déclenche aucune anomalie", {
  expect_length(detecter_un_jour(passage()), 0)
  expect_length(detecter_un_jour(hospitalise()), 0)
})

test_that("chaque règle détecte son défaut", {
  cas <- list(
    dp_vide = passage(dp = NA_character_),
    ccmu_vide = passage(ccmu = NA_character_),
    mode_sortie_vide = passage(mode_sortie = NA_character_),
    code_postal_vide = passage(code_postal = NA_character_),
    destination_vide = hospitalise(destination = NA_character_),
    dp_invalide = passage(dp = "J1O9"),
    sortie_avant_entree = passage(sortie = as.POSIXct("2023-01-01 09:00", tz = "Europe/Paris")),
    duree_aberrante = passage(sortie = as.POSIXct("2023-01-05 10:00", tz = "Europe/Paris")),
    age_aberrant = passage(naissance = "1890-03-15"),
    sexe_invalide = passage(sexe = "0"),
    deces_ccmu1 = passage(ccmu = "1", mode_sortie = "9"),
    provenance_incoherente = passage(provenance = "1"),
    orientation_incoherente = hospitalise(orientation = "PSA")
  )
  for (type in names(cas)) expect_identical(detecter_un_jour(cas[[type]]), type, info = type)
  expect_identical(detecter_un_jour(passage(naissance = "2024-06-01")), "age_aberrant")    # née après l'entrée
  expect_identical(detecter_un_jour(passage(orientation = "REA")), "orientation_incoherente")
  expect_identical(detecter_un_jour(passage(mode_entree = "7", provenance = "5")), "provenance_incoherente")
})

test_that("les cas limites restent conformes", {
  expect_length(detecter_un_jour(passage(dp = "R51", naissance = "2023-01-01", sexe = "I")), 0)  # né le jour même
  expect_length(detecter_un_jour(passage(dp = "Z53.2", sexe = "X")), 0)          # CIM-10 avec point ; sexe inconnu
  expect_length(detecter_un_jour(passage(naissance = "1800-01-01")), 0)          # naissance inconnue (FEDORU)
  expect_length(detecter_un_jour(passage(sortie = as.POSIXct("2023-01-04 10:00", tz = "Europe/Paris"))), 0) # 72 h pile
  expect_length(detecter_un_jour(passage(ccmu = "5", mode_sortie = "9")), 0)
  expect_length(detecter_un_jour(passage(mode_entree = "6", provenance = "1")), 0)
})

test_that("partis sans soins : DP et CCMU vides sont légitimes", {
  expect_length(detecter_un_jour(passage(orientation = "PSA", dp = "Z53.2", ccmu = NA_character_)), 0)
  expect_length(detecter_un_jour(passage(orientation = "REO", dp = NA_character_, ccmu = NA_character_)), 0)
  # une sortie contre avis médical (SCAM) a été vue : DP et CCMU restent obligatoires
  expect_setequal(detecter_un_jour(passage(orientation = "SCAM", dp = NA_character_, ccmu = NA_character_)),
                  c("dp_vide", "ccmu_vide"))
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
  rpu <- dplyr::bind_rows(passage(naissance = "1870-01-01", sexe = "0"), passage(id_passage = "X-2"))
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

test_that("nuit du passage à l'heure d'hiver : l'heure 02:xx répétée n'est pas une sortie avant l'entrée", {
  entree <- as.POSIXct(c("2023-10-29 02:25", "2023-10-29 02:25", "2023-06-11 02:25"), tz = "Europe/Paris")
  sortie <- as.POSIXct(c("2023-10-29 02:10", "2023-10-29 01:10", "2023-06-11 02:10"), tz = "Europe/Paris")
  corrige <- corriger_heure_hiver(entree, sortie)
  expect_equal(as.numeric(difftime(corrige[1], entree[1], units = "mins")), 45)  # seconde occurrence de 02:10
  expect_true(corrige[2] < entree[2])                                            # 01:10 : vraie anomalie
  expect_true(corrige[3] < entree[3])                                            # nuit ordinaire : anomalie
})
