# Explorateur des urgences des Hauts-de-France — tourne dans le navigateur (shinylive, R en WebAssembly).
# Données préparées par scripts/04_donnees_app.R ; base R + ggplot2 pour limiter le chargement.
library(shiny)
library(ggplot2)

# Tout en texte d'abord : les codes (dep « 02 », finess « 020000162 ») gardent leurs zéros, le reste est converti.
lire <- function(f) {
  d <- read.csv(file.path("data", f), colClasses = "character", na.strings = "", encoding = "UTF-8")
  autres <- setdiff(names(d), c("dep", "finess"))
  d[autres] <- lapply(d[autres], type.convert, as.is = TRUE)
  d
}
activite <- lire("activite.csv"); activite$date <- as.Date(activite$date)
taux <- lire("taux_recours.csv")
sae <- lire("sae.csv")
qualite <- lire("qualite.csv")
anomalies <- lire("anomalies.csv")
transmis <- lire("transmis_par_jour.csv"); transmis$date <- as.Date(transmis$date)
activite_rpu <- lire("activite_rpu.csv")

DEPS <- c("Aisne" = "02", "Nord" = "59", "Oise" = "60", "Pas-de-Calais" = "62", "Somme" = "80", "France" = "FR")
NOMS <- setNames(names(DEPS), DEPS)
COULEURS <- c("59" = "#2a78d6", "62" = "#eb6834", "60" = "#1baf7a", "02" = "#eda100", "80" = "#e87ba4", "FR" = "#52514e")
nb <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = " ", decimal.mark = ",")
pct <- function(x, d = 1) ifelse(is.na(x), "non déclaré", paste0(nb(100 * x, d), " %"))
theme_set(theme_minimal(base_size = 13) +
            theme(panel.grid.minor = element_blank(), legend.position = "top", plot.title.position = "plot"))

ui <- navbarPage(
  "Urgences Hauts-de-France",
  header = tags$p(style = "color:#52514e;margin:0 15px 10px",
                  "Projet de portfolio, sans lien avec un organisme officiel. Données DREES, SAE, INSEE (réelles) ;",
                  "volet qualité RPU sur un extrait simulé."),
  tabPanel("Activité",
    sidebarLayout(
      sidebarPanel(width = 3,
        checkboxGroupInput("deps", "Départements", choices = DEPS, selected = c("59", "62", "FR")),
        dateRangeInput("periode", "Période", start = "2017-01-01", end = "2023-12-31",
                       min = "2017-01-01", max = "2023-12-31", language = "fr", separator = "au"),
        radioButtons("echelle", "Afficher", c("Passages par jour (moyenne 7 jours)" = "volume",
                                               "Indice, moyenne 2019 = 100" = "indice"))),
      mainPanel(width = 9, plotOutput("courbe", height = "380px"), h4("Passages pour 10 000 habitants"),
                tableOutput("taux")))),
  tabPanel("Services SAE 2023",
    sidebarLayout(
      sidebarPanel(width = 3, selectInput("dep_sae", "Département", c("Tous" = "tous", DEPS[1:5])),
                   tags$p("Données réelles déclarées par les établissements. « Non déclaré » : variable vide.")),
      mainPanel(width = 9, plotOutput("nuage", height = "360px"), tableOutput("services")))),
  tabPanel("Qualité RPU (simulé)",
    sidebarLayout(
      sidebarPanel(width = 3, selectInput("etab", "Établissement fictif", setNames(qualite$finess, qualite$finess)),
                   tags$p("Établissements et passages simulés ; défauts injectés et catalogués.")),
      mainPanel(width = 9, uiOutput("scores"), plotOutput("calendrier", height = "240px"), tableOutput("anomalies"))))
)

server <- function(input, output, session) {
  serie <- reactive({
    d <- activite[activite$dep %in% input$deps & activite$date >= input$periode[1] &
                    activite$date <= input$periode[2], ]
    if (input$echelle == "indice") {
      ref <- tapply(activite$nb_passages[format(activite$date, "%Y") == "2019"],
                    activite$dep[format(activite$date, "%Y") == "2019"], mean)
      d$mm7 <- 100 * d$mm7 / ref[d$dep]
    }
    d
  })
  output$courbe <- renderPlot({
    d <- serie()
    validate(need(nrow(d) > 0, "Choisissez au moins un département."))
    ggplot(d, aes(date, mm7, colour = dep)) +
      geom_line(linewidth = 0.6, na.rm = TRUE) +
      scale_colour_manual(values = COULEURS, labels = NOMS, name = NULL) +
      scale_y_continuous(labels = function(x) nb(x)) +
      labs(x = NULL, y = if (input$echelle == "indice") "indice (2019 = 100)" else "passages par jour",
           caption = "Source : DREES, passages journaliers estimés (moyenne mobile sur 7 jours).")
  })
  output$taux <- renderTable({
    t <- taux[taux$dep %in% input$deps, ]
    validate(need(nrow(t) > 0, ""))
    large <- reshape(t[c("dep", "annee", "taux")], idvar = "annee", timevar = "dep", direction = "wide")
    names(large) <- c("Année", NOMS[sub("taux.", "", names(large)[-1])])
    large[-1] <- lapply(large[-1], nb)
    large$Année <- as.character(large$Année)
    large
  }, align = "r")

  services <- reactive(if (input$dep_sae == "tous") sae else sae[sae$dep == input$dep_sae, ])
  output$nuage <- renderPlot({
    d <- services()[!is.na(services()$taux_hospit), ]
    validate(need(nrow(d) > 0, "Aucun service de ce département ne déclare ses hospitalisations."))
    ggplot(d, aes(PASSU, taux_hospit, colour = dep)) +
      geom_point(size = 3) +
      scale_colour_manual(values = COULEURS, labels = NOMS, name = NULL) +
      scale_x_continuous(labels = function(x) nb(x)) +
      scale_y_continuous(labels = function(x) pct(x, 0), limits = c(0, NA)) +
      labs(x = "passages par an", y = "part des passages hospitalisés",
           title = paste(nrow(d), "services qui déclarent leurs hospitalisations"))
  })
  output$services <- renderTable({
    d <- services()
    data.frame(Département = NOMS[d$dep], Établissement = d$etablissement,
               Service = ifelse(d$type == "PED", "pédiatrique", "général"), Passages = nb(d$PASSU),
               `80 ans et +` = pct(d$part_80), Hospitalisés = pct(d$taux_hospit), check.names = FALSE)
  })

  output$scores <- renderUI({
    q <- qualite[qualite$finess == input$etab, ]
    a <- activite_rpu[activite_rpu$finess == input$etab, ]
    carte <- function(valeur, libelle) tags$div(
      style = "display:inline-block;background:#f3f3f1;border-radius:6px;padding:8px 14px;margin:0 8px 8px 0;min-width:150px",
      tags$b(style = "font-size:1.4em;display:block", valeur), tags$span(style = "color:#52514e", libelle))
    tagList(carte(paste0(nb(100 * q$score, 1), " / 100"), "score qualité"),
            carte(pct(q$exhaustivite), "exhaustivité"), carte(pct(q$completude), "complétude"),
            carte(pct(q$coherence), "cohérence"), carte(pct(q$exploitabilite_dp), "DP exploitable"),
            carte(pct(a$hospitalisation), "hospitalisés"), carte(pct(a$ecartes_ccmu), "écartés (CCMU vide)"))
  })
  output$calendrier <- renderPlot({
    d <- transmis[transmis$finess == input$etab, ]
    jours <- data.frame(date = seq(as.Date("2023-01-01"), as.Date("2023-12-31"), "day"))
    d <- merge(jours, d, all.x = TRUE); d$n[is.na(d$n)] <- 0
    ggplot(d, aes(date, n)) + geom_line(colour = "#2a78d6", linewidth = 0.45) +
      scale_y_continuous(limits = c(0, NA)) +
      labs(x = NULL, y = "passages", title = "Passages transmis par jour en 2023")
  })
  output$anomalies <- renderTable({
    d <- anomalies[anomalies$finess == input$etab, ]
    d <- d[order(-d$n), ]
    data.frame(Anomalie = d$type_defaut, Dimension = d$dimension, Nombre = nb(d$n))
  })
}

shinyApp(ui, server)
