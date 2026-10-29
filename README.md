# Activité des urgences en Hauts-de-France (R / R Markdown)

[![CI](https://github.com/valentinratigniet-byte/projet-23-urgences-hdf-r/actions/workflows/ci.yml/badge.svg)](https://github.com/valentinratigniet-byte/projet-23-urgences-hdf-r/actions/workflows/ci.yml)
![R 4.5](https://img.shields.io/badge/R-4.5-276DC3) ![renv](https://img.shields.io/badge/versions-renv-555) ![Licence MIT](https://img.shields.io/badge/licence-MIT-555)

**Rapports en ligne : https://valentinratigniet-byte.github.io/projet-23-urgences-hdf-r/**

Indicateurs d'activité des urgences, contrôle qualité des données RPU et restitution aux décideurs, en
R du téléchargement des sources jusqu'aux rapports paramétrés, testé et publié par la CI.

## Contexte

Un observatoire régional des urgences a trois missions : produire des indicateurs d'activité, aider les
établissements à fiabiliser les données qu'ils transmettent (les RPU, un résumé par passage), et restituer
aux décideurs (ARS, équipes de terrain). Ce projet couvre les trois sur les 5 départements des
Hauts-de-France.

| Mission | Livrable |
|---|---|
| Indicateurs d'activité | [Panorama régional](https://valentinratigniet-byte.github.io/projet-23-urgences-hdf-r/panorama.html) et 5 rapports départementaux paramétrés (`params: dep`) |
| Qualité des données | 8 rapports par établissement paramétrés (`params: finess`) : 4 critères de qualité, score, actions prioritaires, passages à corriger |
| Restitution | [Note d'une page en PDF](https://valentinratigniet-byte.github.io/projet-23-urgences-hdf-r/note_ars.pdf) : 3 constats chiffrés, 1 limite, 1 recommandation |

## Résultats (données réelles DREES)

| Constat | Chiffre |
|---|---|
| Passages aux urgences en 2023 (5 départements) | **1,99 million**, soit 5 451 par jour |
| Évolution 2019-2023 de la région | **-2,5 %** (France : -6,1 %) |
| Chute de 2020 (Covid) | -21 % |
| Pas-de-Calais / Oise, 2019-2023 | **+8,1 %** (seul département au-dessus de 2019) / -7,4 % |
| Lundi par rapport à une journée moyenne | **+10 %** ; 9 des 10 journées les plus chargées sont des lundis |

## Données

| Source | Contenu | Statut |
|---|---|---|
| DREES, [séries longues des passages aux urgences 2017-2023](https://data.drees.solidarites-sante.gouv.fr/explore/dataset/series_longues_passages_urgences_2017_2023/) | passages quotidiens par département | **réelles**, valeurs journalières **estimées** (RPU calés sur les totaux annuels de la SAE) |
| Santé publique France, ODISSE | taux hebdomadaires grippe, gastro-entérite, bronchiolite pour 100 000 passages | **réelles**, à partir de 2021 seulement (fin 2019 pour la bronchiolite) |
| Extrait RPU 2023, 8 établissements | un passage par ligne : entrée, sortie, âge, sexe, CCMU, diagnostic CIM-10, mode de sortie | **simulé** : les RPU réels sont confidentiels |

Les deux sources réelles sont sous Licence Ouverte 2.0. La série « France » est la somme des 93 départements
dont la série couvre toute la période : la Corse, le Territoire de Belfort et La Réunion (à partir de 2018) et
la Guyane (à partir de 2020) sont exclus, sinon leur arrivée créerait une fausse hausse.

## Un contrôle qualité vérifiable

L'extrait RPU simulé (164 252 passages) suit le vrai profil quotidien 2023 de chaque département. Il contient
**12 types de défauts injectés** (diagnostic vide ou hors format CIM-10, sortie avant l'entrée, séjour de
plus de 72 h, doublons, jours non transmis…), avec des profils d'établissement différents. Chaque défaut est
inscrit dans un [catalogue](docs/catalogue_defauts.md) qui sert de vérité terrain. Un test vérifie que les
contrôles retrouvent **exactement les 23 596 défauts injectés**, sans manque ni excès.

Ce test a trouvé deux bugs dans le générateur lui-même. Le premier : 62 « décès en CCMU 1 » posés sur des
passages qui n'étaient pas en CCMU 1. Le second : des heures d'arrivée calculées en UTC, qui faisaient
glisser des passages du 31 décembre au 1er janvier 2024.

| Établissement (fictif) | Score | Ce qui le pénalise |
|---|---|---|
| SIM60A | 86,7 | diagnostic exploitable dans 62,5 % des passages seulement |
| SIM62B | 97,0 | 17 jours non transmis (objectif d'exhaustivité : 100 %) |
| SIM59A | 99,7 | meilleur score |

## Structure

```
R/donnees.R          téléchargement DREES + ODISSE, contrôles d'entrée bloquants
R/simulation_rpu.R   générateur RPU reproductible (graine fixe) + injection tracée des défauts
R/qualite.R          12 contrôles, indicateurs par établissement, actions prioritaires
R/indicateurs.R      passages annuels, moyenne mobile, indices jour/mois, pics, lien avec les épidémies
rapports/            panorama, departement (params: dep), qualite (params: finess), note_ars
scripts/             01_donnees.R, 02_simuler_rpu.R, 03_rapports.R, tests.R
tests/testthat/      38 tests
```

## Lancer le projet

```r
renv::restore()                     # versions figées (renv.lock)
source("scripts/01_donnees.R")      # facultatif : données réelles déjà versionnées dans data/
source("scripts/02_simuler_rpu.R")  # régénère l'extrait simulé (identique, graine fixe)
source("scripts/tests.R")           # 38 tests
source("scripts/03_rapports.R")     # 16 rapports dans site/ (environ 5 min)
```

La note PDF est imprimée par Chrome headless, ce qui évite d'installer LaTeX. Sous Windows, si `pandoc`
n'est pas dans le PATH, le script utilise celui de RStudio.

La CI (GitHub Actions, `r-lib/actions`) restaure renv, lance les tests et vérifie que la simulation régénérée
est identique au fichier versionné. Elle rend ensuite les 16 rapports et les publie sur GitHub Pages.

## Limites

- Les volumes journaliers sont estimés : solides pour les tendances et la saisonnalité, pas pour lire une journée isolée.
- Pas de rapport à la population : les départements sont comparés par un indice base 100 en 2019.
- Les épidémies ne sont observables que de 2021 à 2023, et le lien avec les passages est une corrélation.
- L'extrait RPU est simulé : il illustre la méthode, pas la situation réelle d'un établissement.

---

Projet de portfolio, sans lien avec un organisme officiel. Code sous licence MIT.
