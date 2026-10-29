# Prépare les données de l'application Shiny (app/data/) : l'application tourne dans le navigateur
# (shinylive), on lui donne des tables déjà calculées plutôt que de refaire les contrôles qualité.
for (f in list.files("R", full.names = TRUE)) source(f, encoding = "UTF-8")
dir.create("app/data", showWarnings = FALSE, recursive = TRUE)
ecrire <- \(d, nom) readr::write_csv(d, file.path("app/data", nom), na = "")

lire <- \(f) readr::read_csv(f, show_col_types = FALSE, col_types = readr::cols(dep = "c", finess = "c"))
passages <- lire("data/passages_hdf.csv")
population <- lire("data/population_hdf.csv")

# Activité : moyenne mobile 7 jours par série, et taux de recours annuel.
ecrire(passages |> dplyr::mutate(mm7 = round(moyenne_mobile(nb_passages), 1), .by = dep) |>
         dplyr::select(date, dep, nb_passages, mm7), "activite.csv")
ecrire(taux_recours(passages_annuels(passages), population) |> dplyr::select(dep, annee, passages, population, taux),
       "taux_recours.csv")

# Services SAE 2023 (réels).
ecrire(lire("data/sae_urgences_hdf_2023.csv") |> indicateurs_sae() |>
         dplyr::select(finess, etablissement, dep, type, PASSU, part_80, part_18, taux_hospit, LIT_UHCD),
       "sae.csv")

# Qualité RPU (extrait simulé) : scores, anomalies par type, passages transmis par jour.
rpu <- lire_rpu("data/rpu_simule_2023.csv.gz")
anomalies <- detecter_anomalies(rpu)
ecrire(indicateurs_qualite(rpu, anomalies) |>
         dplyr::select(finess, etablissement, passages, exhaustivite, completude, coherence, exploitabilite_dp, score),
       "qualite.csv")
ecrire(dplyr::count(anomalies, finess, type_defaut) |> dplyr::mutate(dimension = DIMENSIONS[type_defaut]), "anomalies.csv")
r <- rpu[!duplicated(rpu), ]
ecrire(dplyr::count(r, finess, date = as.Date(entree, tz = "Europe/Paris")), "transmis_par_jour.csv")
ecrire(indicateurs_activite_rpu(rpu, anomalies) |>
         dplyr::select(finess, passages, hospitalisation, duree_mediane_h, plus_4h, plus_75_ans, ecartes_duree, ecartes_ccmu),
       "activite_rpu.csv")

message("app/data : ", paste(list.files("app/data"), collapse = ", "))
