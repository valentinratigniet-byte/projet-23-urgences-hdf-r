# Générateur d'un extrait au format RPU (Résumé de Passage aux Urgences) — données SIMULÉES.
# Les RPU réels sont des données de santé confidentielles : établissements, patients et passages
# sont fictifs. Seul le profil de volume quotidien vient des données réelles DREES du département.

ETABLISSEMENTS <- tibble::tribble(
  ~finess,     ~etablissement,                ~dep, ~volume_moyen, ~qualite,
  "SIM59A",   "Établissement simulé 59-A",   "59", 95, "bonne",
  "SIM59B",   "Établissement simulé 59-B",   "59", 60, "moyenne",
  "SIM59C",   "Établissement simulé 59-C",   "59", 35, "faible",
  "SIM62A",   "Établissement simulé 62-A",   "62", 70, "moyenne",
  "SIM62B",   "Établissement simulé 62-B",   "62", 40, "moyenne",
  "SIM02A",   "Établissement simulé 02-A",   "02", 45, "bonne",
  "SIM60A",   "Établissement simulé 60-A",   "60", 50, "faible",
  "SIM80A",   "Établissement simulé 80-A",   "80", 55, "moyenne"
)

# Taux de base par défaut (part des passages touchés), multipliés selon la qualité de l'établissement.
TAUX_DEFAUTS <- c(
  dp_vide = 0.03, ccmu_vide = 0.02, mode_sortie_vide = 0.01, code_postal_vide = 0.02,
  dp_invalide = 0.01, sortie_avant_entree = 0.003, duree_aberrante = 0.002,
  age_aberrant = 0.001, sexe_invalide = 0.002, deces_ccmu1 = 0.0005, doublon = 0.003
)
FACTEUR_QUALITE <- c(bonne = 0.2, moyenne = 1, faible = 3)

# Défauts propres à un établissement (en plus des taux ci-dessus).
TROUS_TRANSMISSION <- list(SIM62B = c(seq(as.Date("2023-03-13"), as.Date("2023-03-19"), "day"),
                                      seq(as.Date("2023-08-01"), as.Date("2023-08-10"), "day")))
DP_VIDE_SPECIFIQUE <- c(SIM60A = 0.35)

# Diagnostics principaux (CIM-10, format RPU sans point) par tranche d'âge.
DP <- list(
  enfant = c(J069 = 6, R509 = 5, A099 = 4, J219 = 3, S099 = 3, S934 = 2, S610 = 2, H660 = 2),
  adulte = c(R104 = 5, S934 = 4, R074 = 4, M545 = 3, S610 = 3, N390 = 2, J111 = 2, F100 = 2, R51 = 2),
  age    = c(R296 = 5, I509 = 4, J189 = 4, S720 = 3, N390 = 3, R410 = 2, I489 = 2, R53 = 2)
)
DP_INVALIDES <- c("J1O9", "R50.9", "grippe", "999", "J06.9X", "XXX")

tirer <- function(n, poids) sample(names(poids), n, replace = TRUE, prob = poids)

# Passages « propres » d'un établissement, volume quotidien calé sur le profil réel du département.
simuler_etablissement <- function(etab, profil) {
  p <- profil[profil$dep == etab$dep, ]
  n_jour <- stats::rpois(nrow(p), etab$volume_moyen * p$nb_passages / mean(p$nb_passages))
  n <- sum(n_jour)

  heure <- sample(0:23, n, replace = TRUE,
                  prob = c(2, 1.5, 1, 1, 1, 1.5, 2, 3, 5, 7, 8, 8, 7, 7, 7, 7, 7, 7, 7, 6, 5, 4, 3, 2.5))
  # format() d'abord : as.POSIXct(<Date>) donnerait minuit UTC, soit 1 h ou 2 h du matin à Paris.
  entree <- as.POSIXct(format(rep(p$date, n_jour)), tz = "Europe/Paris") +
    heure * 3600 + sample(0:3599, n, replace = TRUE)

  age <- c(sample(0:14, n, TRUE), sample(15:74, n, TRUE), sample(75:100, n, TRUE))
  age <- age[(seq_len(n) - 1) * 3 + sample(1:3, n, TRUE, prob = c(0.25, 0.55, 0.20))]
  tranche <- ifelse(age < 15, "enfant", ifelse(age < 75, "adulte", "age"))
  dp <- character(n)
  for (t in names(DP)) dp[tranche == t] <- tirer(sum(tranche == t), DP[[t]])

  ccmu <- tirer(n, c("1" = 15, "2" = 64, "3" = 15, "4" = 2, "5" = 0.5, "P" = 3, "D" = 0.5))
  grave <- ccmu %in% c("3", "4", "5")
  p_mutation <- 0.08 + 0.25 * (age >= 75) + 0.40 * grave
  mode_sortie <- ifelse(stats::runif(n) < p_mutation, "6", "8")
  mode_sortie[stats::runif(n) < 0.03 & mode_sortie == "8"] <- "7"
  mode_sortie[ccmu == "D" | (ccmu == "5" & stats::runif(n) < 0.2)] <- "9"

  # Plafond 48 h : au-delà de 72 h, la durée est un défaut injecté (duree_aberrante), jamais naturelle.
  duree_min <- pmin(stats::rlnorm(n, log(170), 0.7) * ifelse(age >= 75, 1.5, 1) * ifelse(mode_sortie == "6", 1.6, 1),
                    48 * 60)

  tibble::tibble(
    finess = etab$finess, etablissement = etab$etablissement, dep = etab$dep,
    entree = entree, sortie = entree + round(duree_min) * 60,
    age = as.character(age),
    sexe = sample(c("M", "F"), n, TRUE),
    # ponytail: préfixe département + 3 chiffres, format plausible mais pas un vrai référentiel des codes postaux
    code_postal = paste0(etab$dep, sprintf("%03d", sample(seq(0, 990, 10), n, TRUE))),
    transport = tirer(n, c(PERSO = 70, AMBU = 14, VSAB = 11, SMUR = 2, FO = 2, HELI = 0.2)),
    ccmu = ccmu, dp = dp, mode_sortie = mode_sortie
  )
}

# Injecte les défauts sur des passages distincts (un défaut au plus par passage) et les trace.
injecter_defauts <- function(rpu, etab) {
  taux <- TAUX_DEFAUTS * FACTEUR_QUALITE[[etab$qualite]]
  if (etab$finess %in% names(DP_VIDE_SPECIFIQUE)) taux[["dp_vide"]] <- DP_VIDE_SPECIFIQUE[[etab$finess]]
  n_defaut <- stats::setNames(stats::rbinom(length(taux), nrow(rpu), taux), names(taux))
  # deces_ccmu1 ne peut toucher qu'un passage CCMU 1 : on le tire parmi eux, les autres ailleurs.
  ccmu1 <- sample(which(rpu$ccmu == "1"), n_defaut[["deces_ccmu1"]])
  autres_types <- setdiff(names(taux), "deces_ccmu1")
  autres <- sample(setdiff(seq_len(nrow(rpu)), ccmu1), sum(n_defaut[autres_types]))
  i <- c(split(autres, factor(rep(autres_types, n_defaut[autres_types]), levels = autres_types)),
         list(deces_ccmu1 = ccmu1))

  rpu$dp[i$dp_vide] <- NA
  rpu$ccmu[i$ccmu_vide] <- NA
  rpu$mode_sortie[i$mode_sortie_vide] <- NA
  rpu$code_postal[i$code_postal_vide] <- NA
  rpu$dp[i$dp_invalide] <- sample(DP_INVALIDES, length(i$dp_invalide), TRUE)
  rpu$sortie[i$sortie_avant_entree] <- rpu$entree[i$sortie_avant_entree] - sample(600:7200, length(i$sortie_avant_entree), TRUE)
  rpu$sortie[i$duree_aberrante] <- rpu$entree[i$duree_aberrante] + sample(73:400, length(i$duree_aberrante), TRUE) * 3600
  rpu$age[i$age_aberrant] <- sample(c("-1", "131", "150", "999"), length(i$age_aberrant), TRUE)
  rpu$sexe[i$sexe_invalide] <- sample(c("X", "0", "H"), length(i$sexe_invalide), TRUE)
  rpu$mode_sortie[i$deces_ccmu1] <- "9"

  catalogue <- tibble::tibble(
    finess = etab$finess,
    type_defaut = rep(names(i), lengths(i)),
    id_passage = rpu$id_passage[unlist(i)],
    date = as.Date(rpu$entree[unlist(i)], tz = "Europe/Paris")
  )
  # Doublon = même passage transmis deux fois : la copie garde le même identifiant.
  rpu <- dplyr::bind_rows(rpu, rpu[i$doublon, ])

  trous <- TROUS_TRANSMISSION[[etab$finess]]
  if (!is.null(trous)) {
    rpu <- rpu[!as.Date(rpu$entree, tz = "Europe/Paris") %in% trous, ]
    catalogue <- catalogue[!catalogue$date %in% trous, ]
    catalogue <- dplyr::bind_rows(catalogue, tibble::tibble(
      finess = etab$finess, type_defaut = "trou_transmission", id_passage = NA_character_, date = trous))
  }
  list(rpu = rpu, catalogue = catalogue)
}

simuler_rpu <- function(profil, graine = 2023) {
  set.seed(graine)
  res <- purrr::map(seq_len(nrow(ETABLISSEMENTS)), function(k) {
    etab <- ETABLISSEMENTS[k, ]
    rpu <- simuler_etablissement(etab, profil)
    rpu <- rpu[order(rpu$entree), ]
    rpu$id_passage <- sprintf("%s-%06d", etab$finess, seq_len(nrow(rpu)))
    injecter_defauts(rpu[c("id_passage", setdiff(names(rpu), "id_passage"))], etab)
  })
  list(rpu = purrr::list_rbind(purrr::map(res, "rpu")) |> dplyr::arrange(finess, entree),
       catalogue = purrr::list_rbind(purrr::map(res, "catalogue")))
}
