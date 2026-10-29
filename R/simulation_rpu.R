# Générateur d'un extrait au format RPU (Résumé de Passage aux Urgences) — données SIMULÉES.
# Les RPU réels sont des données de santé confidentielles : établissements, patients et passages
# sont fictifs. Seul le profil de volume quotidien vient des données réelles DREES du département.
# Champs et nomenclatures : format national V2006 et règles de codage FEDORU (GT1, « Format des éléments
# collectés et règles de codage », V02). Correspondance colonne → balise dans docs/catalogue_defauts.md.

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
  destination_vide = 0.004, dp_invalide = 0.01, sortie_avant_entree = 0.003, duree_aberrante = 0.002,
  age_aberrant = 0.001, sexe_invalide = 0.002, deces_ccmu1 = 0.0005, provenance_incoherente = 0.003,
  orientation_incoherente = 0.002, doublon = 0.003
)
FACTEUR_QUALITE <- c(bonne = 0.2, moyenne = 1, faible = 3)

# Défauts propres à un établissement (en plus des taux ci-dessus).
TROUS_TRANSMISSION <- list(SIM62B = c(seq(as.Date("2023-03-13"), as.Date("2023-03-19"), "day"),
                                      seq(as.Date("2023-08-01"), as.Date("2023-08-10"), "day")))
DP_VIDE_SPECIFIQUE <- c(SIM60A = 0.35)

# Diagnostics principaux (CIM-10, sans point comme dans la plupart des logiciels) par tranche d'âge.
DP <- list(
  enfant = c(J069 = 6, R509 = 5, A099 = 4, J219 = 3, S099 = 3, S934 = 2, S610 = 2, H660 = 2),
  adulte = c(R104 = 5, S934 = 4, R074 = 4, M545 = 3, S610 = 3, N390 = 2, J111 = 2, F100 = 2, R51 = 2),
  age    = c(R296 = 5, I509 = 4, J189 = 4, S720 = 3, N390 = 3, R410 = 2, I489 = 2, R53 = 2)
)
DA <- c(I10 = 5, E119 = 3, Z590 = 2, F102 = 2, I489 = 1, J449 = 1)
DP_INVALIDES <- c("J1O9", "grippe", "999", "J06.9X", "XXX", "R5")

# Orientations autorisées selon le mode de sortie (FEDORU) ; PSA, FUGUE et REO dispensent de DP et de CCMU.
ORIENT_HOSPIT <- c("HDT", "HO", "SDT", "SDRE", "SC", "SI", "REA", "UHCD", "MED", "CHIR", "OBST")
ORIENT_DOMICILE <- c("FUGUE", "PSA", "REO", "SCAM")
SANS_SOINS <- c("PSA", "FUGUE", "REO")

tirer <- function(n, poids) sample(names(poids), n, replace = TRUE, prob = poids)

# Passages « propres » d'un établissement, volume quotidien calé sur le profil réel du département.
simuler_etablissement <- function(etab, profil) {
  p <- profil[profil$dep == etab$dep, ]
  n_jour <- stats::rpois(nrow(p), etab$volume_moyen * p$nb_passages / mean(p$nb_passages))
  n <- sum(n_jour)
  u <- function() stats::runif(n)

  heure <- sample(0:23, n, replace = TRUE,
                  prob = c(2, 1.5, 1, 1, 1, 1.5, 2, 3, 5, 7, 8, 8, 7, 7, 7, 7, 7, 7, 7, 6, 5, 4, 3, 2.5))
  jour <- rep(p$date, n_jour)
  # format() d'abord : as.POSIXct(<Date>) donnerait minuit UTC, soit 1 h ou 2 h du matin à Paris.
  entree <- as.POSIXct(format(jour), tz = "Europe/Paris") + heure * 3600 + sample(0:3599, n, replace = TRUE)

  # Tranche d'âge d'abord, puis âge uniforme dans la tranche.
  tranche <- tirer(n, c(enfant = 25, adulte = 61, age = 14))
  bornes <- list(enfant = 0:14, adulte = 15:74, age = 75:100)
  age <- integer(n)
  for (t in names(bornes)) age[tranche == t] <- sample(bornes[[t]], sum(tranche == t), TRUE)
  naissance <- jour - round(age * 365.25 + stats::runif(n, 0, 364))
  dp <- character(n)
  for (t in names(DP)) dp[tranche == t] <- tirer(sum(tranche == t), DP[[t]])

  # Entrée : domicile (provenance 5 spontanée, 7 médico-social, 8 organisationnelle) ou mutation/transfert.
  mode_entree <- tirer(n, c("8" = 95.5, "7" = 3.5, "6" = 1))
  provenance <- ifelse(mode_entree == "8",
                       ifelse(age >= 75 & u() < 0.15, "7", ifelse(u() < 0.02, "8", "5")),
                       tirer(n, c("1" = 85, "2" = 6, "3" = 2, "4" = 7)))

  transport <- tirer(n, c(PERSO = 70, AMBU = 14, VSAV = 11, SMUR = 2, FO = 2, HELI = 0.2))
  transport[age >= 75 & transport == "PERSO" & u() < 0.4] <- "AMBU"
  transport_pec <- ifelse(transport %in% c("SMUR", "HELI"), "MED",
                          ifelse(transport %in% c("AMBU", "VSAV") & u() < 0.3, "PARAMED", "AUCUN"))

  ccmu <- tirer(n, c("1" = 15, "2" = 64, "3" = 15, "4" = 2, "5" = 0.5, "P" = 3, "D" = 0.5))
  grave <- ccmu %in% c("3", "4", "5")
  mode_sortie <- ifelse(u() < 0.08 + 0.25 * (age >= 75) + 0.40 * grave, "6", "8")
  mode_sortie[u() < 0.03 & mode_sortie == "8"] <- "7"
  mode_sortie[ccmu == "D" | (ccmu == "5" & u() < 0.2)] <- "9"

  hospit <- mode_sortie %in% c("6", "7")
  destination <- rep(NA_character_, n)
  destination[hospit] <- ifelse(ccmu[hospit] == "P", "4", tirer(sum(hospit), c("1" = 95, "2" = 4, "3" = 1)))
  orientation <- rep(NA_character_, n)
  orientation[hospit] <- ifelse(ccmu[hospit] %in% c("4", "5"), tirer(sum(hospit), c(REA = 4, SI = 3, SC = 3)),
                         ifelse(ccmu[hospit] == "P", tirer(sum(hospit), c(MED = 6, SDT = 3, SDRE = 1)),
                                tirer(sum(hospit), c(UHCD = 38, MED = 38, CHIR = 18, OBST = 3, SC = 3))))
  domicile <- which(mode_sortie == "8")
  orientation[domicile] <- tirer(length(domicile), c(aucune = 95.7, PSA = 2.5, SCAM = 0.8, REO = 0.6, FUGUE = 0.4))
  orientation[orientation %in% "aucune"] <- NA
  destination[domicile[provenance[domicile] == "7"]] <- "7"   # retour vers la structure médico-sociale

  # Plafond 48 h : au-delà de 72 h, la durée est un défaut injecté (duree_aberrante), jamais naturelle.
  duree_min <- pmin(stats::rlnorm(n, log(170), 0.7) * ifelse(age >= 75, 1.5, 1) * ifelse(hospit, 1.6, 1), 48 * 60)
  sans_soins <- orientation %in% SANS_SOINS
  duree_min[sans_soins] <- stats::runif(sum(sans_soins), 15, 240)
  # Partis sans soins : pas de CCMU ; DP « Z53.2 » pour PSA et FUGUE, vide pour une réorientation (FEDORU).
  ccmu[sans_soins] <- NA
  dp[orientation %in% c("PSA", "FUGUE")] <- "Z53.2"
  dp[orientation %in% "REO"] <- NA
  liste_da <- ifelse(u() < 0.2 & !sans_soins, tirer(n, DA), NA)

  tibble::tibble(
    finess = etab$finess, etablissement = etab$etablissement, dep = etab$dep,
    # ponytail: préfixe département + 3 chiffres, format plausible mais pas un vrai référentiel des codes postaux
    code_postal = paste0(etab$dep, sprintf("%03d", sample(seq(0, 990, 10), n, TRUE))),
    naissance = format(naissance), sexe = sample(c("M", "F"), n, TRUE),
    entree = entree, mode_entree = mode_entree, provenance = provenance,
    transport = transport, transport_pec = transport_pec,
    motif = ifelse(u() < 0.7 & !sans_soins, dp, NA),  # motif de recours : facultatif
    ccmu = ccmu, dp = dp, liste_da = liste_da,
    sortie = entree + round(duree_min) * 60, mode_sortie = mode_sortie,
    destination = destination, orientation = orientation
  )
}

# Injecte les défauts sur des passages distincts (un défaut au plus par passage) et les trace.
# Les partis sans soins (PSA, FUGUE, REO) ne reçoivent aucun défaut : leurs champs vides sont légitimes.
injecter_defauts <- function(rpu, etab) {
  taux <- TAUX_DEFAUTS * FACTEUR_QUALITE[[etab$qualite]]
  if (etab$finess %in% names(DP_VIDE_SPECIFIQUE)) taux[["dp_vide"]] <- DP_VIDE_SPECIFIQUE[[etab$finess]]
  n_defaut <- stats::setNames(stats::rbinom(length(taux), nrow(rpu), taux), names(taux))

  eligibles <- which(!rpu$orientation %in% SANS_SOINS)
  # Deux défauts ne peuvent toucher qu'un sous-ensemble : on les tire d'abord, les autres ailleurs.
  restreints <- list(deces_ccmu1 = intersect(eligibles, which(rpu$ccmu == "1")),
                     destination_vide = intersect(eligibles, which(rpu$mode_sortie %in% c("6", "7"))))
  i <- list(); pris <- integer()
  for (t in names(restreints)) {
    i[[t]] <- sample(setdiff(restreints[[t]], pris), n_defaut[[t]])
    pris <- c(pris, i[[t]])
  }
  autres_types <- setdiff(names(taux), names(restreints))
  autres <- sample(setdiff(eligibles, pris), sum(n_defaut[autres_types]))
  i <- c(split(autres, factor(rep(autres_types, n_defaut[autres_types]), levels = autres_types)), i)

  rpu$dp[i$dp_vide] <- NA
  rpu$ccmu[i$ccmu_vide] <- NA
  rpu$mode_sortie[i$mode_sortie_vide] <- NA
  rpu$code_postal[i$code_postal_vide] <- NA
  rpu$destination[i$destination_vide] <- NA
  rpu$dp[i$dp_invalide] <- sample(DP_INVALIDES, length(i$dp_invalide), TRUE)
  rpu$sortie[i$sortie_avant_entree] <- rpu$entree[i$sortie_avant_entree] - sample(600:7200, length(i$sortie_avant_entree), TRUE)
  rpu$sortie[i$duree_aberrante] <- rpu$entree[i$duree_aberrante] + sample(73:400, length(i$duree_aberrante), TRUE) * 3600
  # Naissance postérieure à l'entrée, ou âge de plus de 120 ans.
  rpu$naissance[i$age_aberrant] <- sample(c("2024-06-01", "2031-01-01", "1890-03-15", "1875-11-02"),
                                          length(i$age_aberrant), TRUE)
  rpu$sexe[i$sexe_invalide] <- sample(c("0", "H", "2"), length(i$sexe_invalide), TRUE)
  # Un décès vide aussi destination et orientation (elles doivent l'être) : seul le couple CCMU 1 / décès est fautif.
  rpu$mode_sortie[i$deces_ccmu1] <- "9"
  rpu$destination[i$deces_ccmu1] <- NA
  rpu$orientation[i$deces_ccmu1] <- NA
  # Provenance contraire au mode d'entrée : domicile venant d'un service (1), ou mutation « spontanée » (5).
  k <- i$provenance_incoherente
  rpu$provenance[k] <- ifelse(rpu$mode_entree[k] == "8", "1", "5")
  # Orientation contraire au mode de sortie : hospitalisé « parti sans attendre », ou retour à domicile « en réanimation ».
  k <- i$orientation_incoherente
  rpu$orientation[k] <- ifelse(rpu$mode_sortie[k] %in% c("6", "7"), "PSA", "REA")
  rpu$orientation[k][rpu$mode_sortie[k] %in% "9"] <- "MED"

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
