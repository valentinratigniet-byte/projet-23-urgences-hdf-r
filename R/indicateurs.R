# Indicateurs d'activité sur les séries quotidiennes de passages (DREES).

JOURS <- c("lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche")

passages_annuels <- function(p) {
  p |>
    dplyr::mutate(annee = lubridate::year(date)) |>
    dplyr::summarise(passages = sum(nb_passages), .by = c(dep, libelle_dep, annee)) |>
    dplyr::arrange(dep, annee) |>
    dplyr::mutate(evolution = passages / dplyr::lag(passages) - 1, .by = dep)
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
