# Lance tous les tests ; code de sortie non nul en cas d'échec (utilisé par la CI).
testthat::test_dir("tests/testthat", stop_on_failure = TRUE)
