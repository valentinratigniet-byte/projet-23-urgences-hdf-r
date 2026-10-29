# Indicateurs d'activité calculés sur les RPU, par établissement et pour l'ensemble.
# Chaque indicateur n'utilise que les passages où le champ concerné est exploitable : une durée n'est
# calculée que sans anomalie de dates, une gravité que si la CCMU est renseignée, etc. La part de
# passages écartés est publiée à côté, pour que la qualité des données reste visible dans les chiffres.

TRANSPORTS_SANITAIRES <- c("AMBU", "VSAV", "SMUR", "HELI")

indicateurs_activite_rpu <- function(rpu, anomalies) {
  r <- rpu[!duplicated(rpu), ]
  if (!"age" %in% names(r)) r$age <- age_rpu(r)
  dates_ko <- anomalies$id_passage[anomalies$type_defaut %in% c("sortie_avant_entree", "duree_aberrante")]
  r$duree_h <- ifelse(r$id_passage %in% dates_ko, NA,
                      as.numeric(difftime(r$sortie, r$entree, units = "hours")))
  r$age[r$id_passage %in% anomalies$id_passage[anomalies$type_defaut == "age_aberrant"]] <- NA
  r$heure <- as.integer(format(r$entree, "%H"))
  r$hospit <- ifelse(r$mode_sortie %in% c("6", "7", "8", "9"), r$mode_sortie %in% c("6", "7"), NA)

  calculer <- function(d) {
    tibble::tibble(
      passages = nrow(d),
      moins_1_an = mean(d$age < 1, na.rm = TRUE),
      plus_75_ans = mean(d$age >= 75, na.rm = TRUE),
      nuit_20h_8h = mean(d$heure >= 20 | d$heure < 8),
      transport_sanitaire = mean(d$transport %in% TRANSPORTS_SANITAIRES),
      ccmu_1 = mean(d$ccmu[!is.na(d$ccmu)] == "1"),
      ccmu_4_5 = mean(d$ccmu[!is.na(d$ccmu)] %in% c("4", "5")),
      hospitalisation = mean(d$hospit, na.rm = TRUE),
      partis_sans_soins = mean(d$orientation %in% c("PSA", "FUGUE", "REO")),
      duree_mediane_h = stats::median(d$duree_h, na.rm = TRUE),
      duree_mediane_hospit_h = stats::median(d$duree_h[d$hospit %in% TRUE], na.rm = TRUE),
      duree_mediane_domicile_h = stats::median(d$duree_h[d$hospit %in% FALSE], na.rm = TRUE),
      plus_4h = mean(d$duree_h > 4, na.rm = TRUE),
      plus_8h = mean(d$duree_h > 8, na.rm = TRUE),
      # part des passages écartés de chaque calcul faute de donnée exploitable
      ecartes_duree = mean(is.na(d$duree_h)),
      ecartes_ccmu = mean(is.na(d$ccmu) & !d$orientation %in% c("PSA", "FUGUE", "REO")),
      ecartes_sortie = mean(is.na(d$hospit))
    )
  }
  par_etab <- r |> dplyr::group_by(finess, etablissement, dep) |> dplyr::group_modify(\(d, k) calculer(d)) |>
    dplyr::ungroup()
  ensemble <- dplyr::mutate(calculer(r), finess = "Ensemble", etablissement = "Ensemble des 8 établissements",
                            dep = NA_character_)
  dplyr::bind_rows(par_etab, ensemble)
}

# Profil horaire des arrivées : part des passages arrivés à chaque heure.
profil_horaire <- function(rpu) {
  r <- rpu[!duplicated(rpu), ]
  tibble::tibble(heure = as.integer(format(r$entree, "%H"))) |>
    dplyr::count(heure) |>
    dplyr::mutate(part = n / sum(n))
}

# Répartition des durées de passage par classe, par établissement (passages à dates cohérentes).
classes_duree <- function(rpu, anomalies) {
  r <- rpu[!duplicated(rpu), ]
  ko <- anomalies$id_passage[anomalies$type_defaut %in% c("sortie_avant_entree", "duree_aberrante")]
  r <- r[!r$id_passage %in% ko, ]
  h <- as.numeric(difftime(r$sortie, r$entree, units = "hours"))
  tibble::tibble(finess = r$finess,
                 classe = cut(h, c(0, 2, 4, 8, Inf), right = FALSE,
                              labels = c("moins de 2 h", "2 à 4 h", "4 à 8 h", "8 h et plus"))) |>
    dplyr::count(finess, classe) |>
    dplyr::mutate(part = n / sum(n), .by = finess)
}
