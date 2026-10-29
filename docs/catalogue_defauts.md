# Extrait RPU simulé : catalogue des défauts injectés

> **Données simulées.** Les RPU réels sont des données de santé confidentielles. Les 8 établissements
> (`SIM59A`… `SIM80A`), leurs patients et leurs passages sont fictifs. Seul le volume quotidien suit le
> profil réel 2023 du département (DREES). Générateur : `R/simulation_rpu.R`, graine 2023 (reproductible).

Fichiers : `data/rpu_simule_2023.csv.gz` (164 251 lignes) et `data/rpu_defauts_injectes.csv`
(vérité terrain : une ligne par défaut, avec `finess`, `type_defaut`, `id_passage`, `date`).
Chaque passage porte au plus un défaut, ce qui permet de mesurer exactement ce que détectent les
contrôles qualité.

| Défaut | Ce qui est fait | Taux de base |
|---|---|---|
| `dp_vide` | diagnostic principal vide | 3 % |
| `ccmu_vide` | gravité CCMU vide | 2 % |
| `mode_sortie_vide` | mode de sortie vide | 1 % |
| `code_postal_vide` | code postal vide | 2 % |
| `dp_invalide` | DP hors format CIM-10 (`J1O9`, `R50.9`, `grippe`, `999`…) | 1 % |
| `sortie_avant_entree` | sortie 10 min à 2 h avant l'entrée | 0,3 % |
| `duree_aberrante` | séjour de plus de 72 h | 0,2 % |
| `age_aberrant` | âge `-1`, `131`, `150` ou `999` | 0,1 % |
| `sexe_invalide` | sexe hors nomenclature (`X`, `0`, `H`) | 0,2 % |
| `deces_ccmu1` | décès (mode de sortie 9) d'un patient classé CCMU 1 | 0,05 % |
| `doublon` | passage transmis deux fois (même identifiant) | 0,3 % |
| `trou_transmission` | jours entiers sans aucun passage | `SIM62B` seulement : 13-19 mars et 1er-10 août |

Les taux sont multipliés selon le profil de l'établissement : qualité **bonne** ×0,2 (`SIM59A`,
`SIM02A`), **moyenne** ×1, **faible** ×3 (`SIM59C`, `SIM60A`). `SIM60A` a en plus 35 % de DP vides :
c'est le cas d'école « diagnostic non exploitable ».

Limites connues : le code postal est un préfixe de département suivi de 3 chiffres (format plausible, pas
vérifié contre un référentiel) ; les diagnostics sont tirés parmi une trentaine de codes courants, sans
saisonnalité (celle-ci vient des données réelles ODISSE) ; les durées naturelles sont plafonnées à
48 h, pour qu'un séjour de plus de 72 h soit toujours un défaut injecté.

Contrôle : `tests/testthat/test-qualite.R` vérifie que `detecter_anomalies()` retrouve **exactement**
ce catalogue, sans défaut manquant ni anomalie en trop.
