# Phase 1 : télécharge les sources réelles, contrôle, et écrit les tables propres dans data/.
source("R/donnees.R")

passages <- controler_passages(lire_passages())

# France = somme des départements publiés sur toute la période (série absente de la source).
# Exclus : 2A, 2B, 90, 974 (à partir de 2018) et 973 (à partir de 2020), sinon fausse hausse à leur entrée.
complets <- passages |> dplyr::count(dep) |> dplyr::filter(n == max(n)) |> dplyr::pull(dep)
france <- passages |>
  dplyr::filter(dep %in% complets) |>
  dplyr::summarise(nb_passages = sum(nb_passages), .by = date) |>
  dplyr::mutate(dep = "FR", libelle_dep = sprintf("France (%d dép. à série complète)", length(complets)))

passages_hdf <- passages |>
  dplyr::filter(dep %in% DEPS_HDF) |>
  dplyr::bind_rows(france) |>
  dplyr::arrange(dep, date)

epidemies <- controler_epidemies(lire_epidemies()) |> dplyr::arrange(pathologie, dep, semaine)

# Population de référence : mêmes départements que les passages (la France sur les mêmes 93 départements).
population <- controler_population(lire_population())
stopifnot("population connue pour chaque département de la série France" = all(complets %in% population$dep))
population_hdf <- population |>
  dplyr::filter(dep %in% DEPS_HDF) |>
  dplyr::bind_rows(population |> dplyr::filter(dep %in% complets) |>
                     dplyr::summarise(population = sum(population), .by = annee) |> dplyr::mutate(dep = "FR")) |>
  dplyr::arrange(dep, annee)

readr::write_csv(passages_hdf, "data/passages_hdf.csv")
readr::write_csv(epidemies, "data/epidemies_hdf.csv")
readr::write_csv(population_hdf, "data/population_hdf.csv")

message(sprintf("passages : %d lignes (%s → %s) ; épidémies : %d lignes ; population : %d lignes",
                nrow(passages_hdf), min(passages_hdf$date), max(passages_hdf$date), nrow(epidemies),
                nrow(population_hdf)))
