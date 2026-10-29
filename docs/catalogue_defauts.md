# Extrait RPU simulé : format, règles et catalogue des défauts injectés

> **Données simulées.** Les RPU réels sont des données de santé confidentielles. Les 8 établissements
> (`SIM59A`… `SIM80A`), leurs patients et leurs passages sont fictifs. Seul le volume quotidien suit le
> profil réel 2023 du département (DREES). Générateur : `R/simulation_rpu.R`, graine 2023 (reproductible).

Fichiers : `data/rpu_simule_2023.csv.gz` (163 945 lignes) et `data/rpu_defauts_injectes.csv`
(vérité terrain : 24 757 défauts, une ligne par défaut, avec `finess`, `type_defaut`, `id_passage`, `date`).
Chaque passage porte au plus un défaut, ce qui permet de mesurer exactement ce que détectent les
contrôles qualité.

## Format : correspondance avec le RPU national

Les champs et leurs nomenclatures suivent le format national V2006 et les règles de codage de la FEDORU
([GT1 « Format des éléments collectés et règles de codage », V02](https://fedoru.fr/wp-content/uploads/2022/03/2_GT1_V02_Format_des_elements_collectes_et_regles_de_codage.pdf)).
Le fichier est un CSV à plat (une ligne par passage), pas le XML transmis aux plateformes régionales.

| Colonne | Balise | Valeurs |
|---|---|---|
| `code_postal` | `<CP>` | code postal de résidence |
| `naissance` | `<NAISSANCE>` | date ; `1800-01-01` = inconnue (exclue des calculs d'âge) |
| `sexe` | `<SEXE>` | `M`, `F`, `I` (indéterminé), `X` (inconnu) |
| `entree` | `<ENTREE>` | date et heure d'enregistrement administratif, **heure locale sans décalage** |
| `mode_entree` | `<MODE_ENTREE>` | `6` mutation, `7` transfert, `8` domicile |
| `provenance` | `<PROVENANCE>` | `1` à `4` (MCO, SSR, SLD, PSY) si mutation ou transfert ; `5` à `8` si domicile |
| `transport` | `<TRANSPORT>` | `PERSO`, `AMBU`, `VSAV`, `SMUR`, `HELI`, `FO` |
| `transport_pec` | `<TRANSPORT_PEC>` | `MED`, `PARAMED`, `AUCUN` |
| `motif` | `<MOTIF>` | code CIM-10, facultatif |
| `ccmu` | `<GRAVITE>` | `1` à `5`, `P`, `D` |
| `dp` | `<DP>` | code CIM-10 |
| `liste_da` | `<LISTE_DA>` | diagnostic associé, facultatif |
| `sortie` | `<SORTIE>` | date et heure de sortie de la zone de soins (une admission en UHCD est une sortie) |
| `mode_sortie` | `<MODE_SORTIE>` | `6` mutation, `7` transfert, `8` domicile, `9` décès |
| `destination` | `<DESTINATION>` | `1` à `4` si hospitalisé (obligatoire) ; `6`, `7` ou vide si domicile ; vide si décès |
| `orientation` | `<ORIENTATION>` | `UHCD`, `MED`, `CHIR`, `OBST`, `SC`, `SI`, `REA`, `SDT`, `SDRE`… si hospitalisé ; `PSA`, `FUGUE`, `REO`, `SCAM` ou vide si domicile ; vide si décès |

Non simulés : la commune de résidence et la liste des actes CCAM (facultative).

## Règles appliquées par les contrôles

- **Partis sans soins** (`PSA`, `FUGUE`, `REO`) : le diagnostic et la gravité ne sont pas obligatoires
  (FEDORU) ; un DP ou une CCMU vide n'y est pas un défaut. Une sortie contre avis médical (`SCAM`) a été
  vue par un médecin : ses champs restent obligatoires.
- **CIM-10** : accepté avec ou sans point (`Z53.2` ou `Z532`).
- **Changement d'heure** : la nuit du passage à l'heure d'hiver, 02:00-02:59 existe deux fois et le RPU
  n'indique pas le décalage. Une sortie relue moins d'une heure avant l'entrée, toutes deux dans cette
  heure-là, est la seconde occurrence de l'heure : `lire_rpu()` la corrige. Le cas s'est présenté dans
  l'extrait (entrée à 02:25, sortie à 02:10, le 29 octobre 2023) et a d'abord été pris pour une anomalie.

## Défauts injectés

| Défaut | Ce qui est fait | Taux de base |
|---|---|---|
| `dp_vide` | diagnostic principal vide | 3 % |
| `ccmu_vide` | gravité CCMU vide | 2 % |
| `mode_sortie_vide` | mode de sortie vide | 1 % |
| `code_postal_vide` | code postal vide | 2 % |
| `destination_vide` | destination vide pour un patient hospitalisé (obligatoire) | 0,4 % |
| `dp_invalide` | DP hors format CIM-10 (`J1O9`, `grippe`, `999`, `J06.9X`…) | 1 % |
| `sortie_avant_entree` | sortie 10 min à 2 h avant l'entrée | 0,3 % |
| `duree_aberrante` | séjour de plus de 72 h | 0,2 % |
| `age_aberrant` | naissance après l'entrée, ou plus de 120 ans | 0,1 % |
| `sexe_invalide` | sexe hors nomenclature (`0`, `H`, `2`) | 0,2 % |
| `deces_ccmu1` | décès (mode de sortie 9) d'un patient classé CCMU 1 | 0,05 % |
| `provenance_incoherente` | venue du domicile avec une provenance « service » (`1`), ou mutation avec une provenance « domicile » (`5`) | 0,3 % |
| `orientation_incoherente` | hospitalisé « parti sans attendre », retour à domicile « en réanimation », ou orientation renseignée pour un décès | 0,2 % |
| `doublon` | passage transmis deux fois (même identifiant) | 0,3 % |
| `trou_transmission` | jours entiers sans aucun passage | `SIM62B` seulement : 13-19 mars et 1er-10 août |

Les taux sont multipliés selon le profil de l'établissement : qualité **bonne** ×0,2 (`SIM59A`,
`SIM02A`), **moyenne** ×1, **faible** ×3 (`SIM59C`, `SIM60A`). `SIM60A` a en plus 35 % de DP vides :
c'est le cas d'école « diagnostic non exploitable ». Les partis sans soins ne reçoivent aucun défaut.

Limites connues : le code postal est un préfixe de département suivi de 3 chiffres (format plausible, pas
vérifié contre un référentiel) ; les diagnostics sont tirés parmi une trentaine de codes courants, sans
saisonnalité (celle-ci vient des données réelles ODISSE) ; les durées naturelles sont plafonnées à 48 h,
pour qu'un séjour de plus de 72 h soit toujours un défaut injecté ; les 8 établissements partagent les
mêmes paramètres de simulation, donc leurs indicateurs d'activité ne diffèrent que par le hasard et la
qualité des données.

Contrôle : `tests/testthat/test-qualite.R` vérifie que `detecter_anomalies()` retrouve **exactement**
ce catalogue, sans défaut manquant ni anomalie en trop.
