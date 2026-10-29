# Cadrage — Projet 23 : activité des urgences en Hauts-de-France (R / R Markdown)

## Pourquoi ce projet

Le portfolio ne contient aucun projet en R. Le projet reprend les trois missions d'un observatoire
régional des urgences :

| Mission | Ce que le projet montre |
|---|---|
| Produire des indicateurs sur l'activité des urgences | Séries quotidiennes réelles 2017-2023 des 5 départements, tendance, saisonnalité, pics |
| Aider les établissements à améliorer la qualité de leurs données | Contrôles qualité sur un extrait au format RPU, rapport de retour par établissement |
| Restituer aux décideurs (ARS, équipes de terrain) | Rapport R Markdown **paramétré** : un département ou un établissement → un rapport complet |

## Données

1. **Réelles : passages aux urgences par jour et par département, 2017-2023** (DREES, Etalab 2.0).
   API : `data.drees.solidarites-sante.gouv.fr`, jeu `series_longues_passages_urgences_2017_2023`
   (colonnes `date`, `dep`, `libelle_dep`, `nb_passages`). Filtre sur 02, 59, 60, 62, 80 + France
   entière comme référence.
   ⚠️ À dire dans le README : valeurs journalières **estimées** (RPU calés sur les totaux annuels de
   la SAE par la méthode Denton-Cholette), pas observées directement.
2. **Réelles : indicateurs épidémiques par département** (Santé publique France, ODISSE : grippe,
   bronchiolite, gastro-entérite) pour expliquer les pics. Disponibilité exacte à vérifier en phase 1.
3. **Simulées : extrait au format RPU** (une ligne par passage : établissement, âge, sexe, dates
   d'entrée et de sortie, mode de sortie, CCMU, diagnostic principal CIM-10). Les RPU réels sont des
   données de santé confidentielles. Le jeu est généré en R à partir de la structure nationale du RPU,
   avec des défauts injectés et documentés (champs vides, sortie avant entrée, codes CIM-10
   invalides, trous de transmission). **Présenté comme simulé partout.**

## Livrables

1. **Panorama régional** (R Markdown → HTML) : volumes, évolution 2017-2023, saisonnalité, jour de
   la semaine, effet Covid 2020, comparaison des 5 départements et de la France, pics épidémiques.
2. **Rapport départemental paramétré** (`params: dep`), rendu en boucle pour les 5 départements.
3. **Rapport qualité des données paramétré par établissement** : exhaustivité calendaire,
   complétude champ par champ, cohérence, exploitabilité du diagnostic (indicateurs du livret qualité
   des urgences de la FHF), avec un score et des actions prioritaires.
4. **Note d'une page pour l'ARS** (PDF) : 3 constats chiffrés, 1 limite, 1 recommandation.
5. Bonus si le temps le permet : petite app Shiny d'exploration.

## Stack et rigueur

- R 4.5.1 + RStudio (`.Rproj`), tidyverse, lubridate, slider (moyennes mobiles), fable/feasts
  pour la décomposition saisonnière (STL), gt pour les tableaux, ggplot2.
- `renv` (versions figées), `testthat` (contrôles qualité et calculs testés), fonctions dans `R/`,
  rapports dans `rapports/`.
- CI GitHub Actions (r-lib/actions) : restaure renv, lance les tests, tricote les rapports.
- Publication des rapports HTML sur GitHub Pages.

## Phases

1. **Données** : téléchargement API DREES + ODISSE, contrôles d'entrée, cache local `data/raw/`.
2. **Simulation RPU** : générateur reproductible (graine fixe) + catalogue des défauts injectés.
3. **Fonctions et tests** : indicateurs d'activité et de qualité dans `R/`, tests `testthat`.
4. **Rapports R Markdown** : panorama, départemental paramétré, qualité paramétré, note ARS.
5. **Industrialisation** : renv, CI, GitHub Pages.
6. **Publication** : README vitrine, schéma, index du portfolio, profil GitHub, mémoire.

## Pièges connus

- `Rscript` ne voit pas pandoc : définir `RSTUDIO_PANDOC` vers
  `C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools`.
- Interception SSL de la machine : vérifier que `install.packages()` passe (R utilise le magasin de
  certificats Windows) ; sinon `options(download.file.method = "wininet")`.
- Ne pas sur-interpréter les valeurs journalières (estimées) ni le jeu RPU (simulé).
