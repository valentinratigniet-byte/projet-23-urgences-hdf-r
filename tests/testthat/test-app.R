test_that("l'application répond aux choix de l'utilisateur", {
  shiny::testServer(test_path("../../app"), {
    session$setInputs(deps = c("59", "FR"), periode = as.Date(c("2019-01-01", "2019-12-31")), echelle = "indice",
                      dep_sae = "62", etab = "SIM60A")
    expect_setequal(unique(serie()$dep), c("59", "FR"))
    expect_true(all(format(serie()$date, "%Y") == "2019"))
    expect_equal(mean(serie()$mm7[serie()$dep == "59"], na.rm = TRUE), 100, tolerance = 0.01)  # indice 2019 = 100
    expect_true(all(services()$dep == "62"))
    expect_match(output$taux, "Nord")
  })
})
