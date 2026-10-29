# Indicateurs d'activité sur les séries quotidiennes de passages (DREES).

JOURS <- c("lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche")

passages_annuels <- function(p) {
  p |>
    dplyr::mutate(annee = lubridate::year(date)) |>
    dplyr::summarise(passages = sum(nb_passages), .by = c(dep, libelle_dep, annee)) |>
    dplyr::arrange(dep, annee) |>
    dplyr::mutate(evolution = passages / dplyr::lag(passages) - 1, .by = dep)
}

# Taux de recours : passages de l'année pour 10 000 habitants (population INSEE au 1er janvier).
taux_recours <- function(annuel, population) {
  dplyr::inner_join(annuel, population, by = c("dep", "annee")) |>
    dplyr::mutate(taux = 1e4 * passages / population)
}

moyenne_mobile <- function(x, k = 7) slider::slide_dbl(x, mean, .before = k - 1, .complete = TRUE)

# Indice = moyenne du jour / moyenne globale du département (1 = journée moyenne).
indice_jour_semaine <- function(p) {
  p |>
    dplyr::mutate(jour = factor(JOURS[lubridate::wday(date, week_start = 1)], JOURS)) |>
    dplyr::summarise(moyenne = mean(nb_passages), .by = c(dep, jour)) |>
    dplyr::mutate(indice = moyenne / mean(moyenne), .by = dep) |>
    dplyr::arrange(dep, jour)
}

indice_mensuel <- function(p) {
  p |>
    dplyr::mutate(mois = lubridate::month(date)) |>
    dplyr::summarise(moyenne = mean(nb_passages), .by = c(dep, mois)) |>
    dplyr::mutate(indice = moyenne / mean(moyenne), .by = dep) |>
    dplyr::arrange(dep, mois)
}

# Jours au-dessus du quantile q de leur département.
jours_pic <- function(p, q = 0.99) {
  p |>
    dplyr::filter(nb_passages > stats::quantile(nb_passages, q), .by = dep) |>
    dplyr::arrange(dep, dplyr::desc(nb_passages))
}

# Passages hebdomadaires (semaine du lundi, comme ODISSE) rapprochés des taux épidémiques.
rapprocher_epidemies <- function(p, e) {
  p |>
    dplyr::mutate(semaine = lubridate::floor_date(date, "week", week_start = 1)) |>
    dplyr::summarise(passages = sum(nb_passages), jours = dplyr::n(), .by = c(dep, semaine)) |>
    dplyr::filter(jours == 7) |>
    dplyr::inner_join(e, by = c("dep", "semaine"), relationship = "one-to-many")
}

# SAE 2023, par service : part des 80 ans et plus, des moins de 18 ans, et taux d'hospitalisation
# (MCO, SMR-PSY-USLD, HAD de la même entité juridique + autre entité). Sans dtMCO, le taux n'est pas
# calculable ; les autres destinations vides sont comptées à zéro (service sans unité de ce type).
indicateurs_sae <- function(sae) {
  hospit <- rowSums(sae[c("dtMCO", "dtLS", "dtHAD", "dtEXT")], na.rm = TRUE)
  sae |>
    dplyr::mutate(
      part_80 = dt80 / PASSU,
      part_18 = dt18 / PASSU,
      hospitalises = ifelse(is.na(dtMCO), NA, hospit),
      taux_hospit = hospitalises / PASSU,
      declaration_complete = !is.na(dtMCO) & (type == "PED" | !is.na(dt80)),
      incoherent = (hospit > PASSU) | dplyr::coalesce(dt80 > PASSU, FALSE) | dplyr::coalesce(dt18 > PASSU, FALSE)
    )
}

# Rapprochement des passages annuels DREES et de la somme des services SAE, par département.
rapprocher_sae <- function(annuel, sae, an = 2023) {
  dplyr::filter(annuel, annee == an, dep %in% DEPS_HDF) |>
    dplyr::select(dep, drees = passages) |>
    dplyr::inner_join(dplyr::summarise(sae, sae = sum(PASSU), services = dplyr::n(), .by = dep), by = "dep") |>
    dplyr::mutate(ecart = drees / sae - 1)
}
