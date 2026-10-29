serie <- function(debut, valeurs, dep = "59") {
  tibble::tibble(date = as.Date(debut) + seq_along(valeurs) - 1, dep = dep, libelle_dep = dep, nb_passages = valeurs)
}

test_that("passages annuels et évolution", {
  p <- dplyr::bind_rows(serie("2019-12-31", c(100, 110)))
  a <- passages_annuels(p)
  expect_equal(a$passages, c(100, 110))
  expect_equal(a$evolution, c(NA, 0.1))
})

test_that("moyenne mobile : NA tant que la fenêtre est incomplète", {
  expect_equal(moyenne_mobile(1:5, k = 3), c(NA, NA, 2, 3, 4))
})

test_that("indice du jour de la semaine (2023-01-02 est un lundi)", {
  i <- indice_jour_semaine(serie("2023-01-02", c(140, rep(100, 6))))
  expect_identical(as.character(i$jour[1]), "lundi")
  expect_equal(i$indice[1], 140 / mean(c(140, rep(100, 6))))
  expect_equal(mean(i$indice), 1)
})

test_that("jours de pic par département", {
  p <- dplyr::bind_rows(serie("2023-01-01", c(1:99, 500)), serie("2023-01-01", c(1:99, 50), dep = "62"))
  pics <- jours_pic(p, q = 0.99)
  expect_equal(pics$nb_passages, c(500, 99))
})

test_that("rapprochement hebdomadaire : semaines complètes seulement", {
  p <- serie("2023-01-02", rep(10, 10))   # une semaine complète + 3 jours
  e <- tibble::tibble(semaine = as.Date(c("2023-01-02", "2023-01-09")), dep = "59",
                      pathologie = "grippe", taux_passages = c(1, 2))
  r <- rapprocher_epidemies(p, e)
  expect_equal(nrow(r), 1)
  expect_equal(r$passages, 70)
})
