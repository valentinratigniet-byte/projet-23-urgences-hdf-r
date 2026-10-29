# Phase 2 : génère l'extrait RPU SIMULÉ 2023 et le catalogue des défauts injectés (vérité terrain).
source("R/simulation_rpu.R")

profil <- readr::read_csv("data/passages_hdf.csv", show_col_types = FALSE) |>
  dplyr::filter(format(date, "%Y") == "2023")

sim <- simuler_rpu(profil)

readr::write_csv(dplyr::mutate(sim$rpu, dplyr::across(c(entree, sortie), \(x) format(x, "%Y-%m-%d %H:%M"))),
                 "data/rpu_simule_2023.csv.gz", na = "")
readr::write_csv(dplyr::arrange(sim$catalogue, finess, type_defaut, date), "data/rpu_defauts_injectes.csv", na = "")

message(sprintf("RPU simulé : %d passages, %d établissements ; %d défauts catalogués",
                nrow(sim$rpu), dplyr::n_distinct(sim$rpu$finess), nrow(sim$catalogue)))
print(table(sim$catalogue$finess, sim$catalogue$type_defaut))
