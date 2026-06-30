source("global.R")

# ==============================================================
# UI
# ==============================================================
ui <- fluidPage(
  tags$head(
    tags$link(
      rel = "stylesheet",
      href = "https://fonts.googleapis.com/css?family=Lato:400,700&display=swap"
    ),
    tags$style(HTML("
      * { font-family: 'Lato', sans-serif; }
      .app-header {
        background-color: #2c3e50;
        color: white;
        padding: 14px 20px;
        margin-bottom: 20px;
        font-size: 1.35em;
        font-weight: bold;
        border-radius: 4px;
      }
      .sidebar-section {
        background-color: #f8f9fa;
        border: 1px solid #e9ecef;
        border-radius: 4px;
        padding: 10px 12px;
        margin-bottom: 12px;
      }
      .section-label {
        font-weight: 700;
        color: #495057;
        font-size: 0.78em;
        text-transform: uppercase;
        letter-spacing: 0.6px;
        margin-bottom: 6px;
      }
      .status-ok {
        background-color: #d4edda;
        border: 1px solid #c3e6cb;
        border-radius: 4px;
        padding: 8px 12px;
        color: #155724;
        margin-bottom: 14px;
      }
      .status-err {
        background-color: #f8d7da;
        border: 1px solid #f5c6cb;
        border-radius: 4px;
        padding: 8px 12px;
        color: #721c24;
        margin-bottom: 14px;
      }
    "))
  ),
  div(class = "app-header", "DHS Indicator Comparison"),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      div(class = "sidebar-section",
        div(class = "section-label", "Selection"),
        selectInput("country", "Country", choices = available_countries),
        selectInput("year", "Year", choices = NULL),
        selectInput("admin_level", "Admin Level",
          choices = c("Admin 1" = 1, "Admin 2" = 2),
          selected = 1
        )
      ),
      div(class = "sidebar-section",
        div(class = "section-label", "Indicators"),
        selectInput("indicator1", "X-axis Indicator", choices = NULL),
        selectInput("indicator2", "Y-axis Indicator", choices = NULL)
      ),
      div(class = "sidebar-section",
        div(class = "section-label", "Axis Range"),
        tags$small(tags$em("Leave blank to fit to data")),
        tags$p(style = "margin: 8px 0 2px; font-weight: 600; font-size: 0.9em;", "X-axis"),
        fluidRow(
          column(6, numericInput("x_min", "Min", value = NA, step = 0.05)),
          column(6, numericInput("x_max", "Max", value = NA, step = 0.05))
        ),
        tags$p(style = "margin: 6px 0 2px; font-weight: 600; font-size: 0.9em;", "Y-axis"),
        fluidRow(
          column(6, numericInput("y_min", "Min", value = NA, step = 0.05)),
          column(6, numericInput("y_max", "Max", value = NA, step = 0.05))
        )
      ),
      div(class = "sidebar-section",
        div(class = "section-label", "Display Options"),
        checkboxInput("show_ci", "Show 95% Credible Interval Bars", value = TRUE),
        checkboxInput("interactive_plot", "Interactive Plot", value = TRUE),
        checkboxInput("log_x", "Log-transform X-axis", value = FALSE),
        checkboxInput("log_y", "Log-transform Y-axis", value = FALSE)
      ),
      div(style = "margin-top: 10px;",
        downloadButton("download_plot", "Download Plot (PDF)",
          class = "btn-primary btn-sm",
          style = "width: 100%;"
        )
      )
    ),
    mainPanel(
      width = 9,
      uiOutput("data_status"),
      uiOutput("plot_canvas")
    )
  )
)

# ==============================================================
# Server
# ==============================================================
server <- function(input, output, session) {

  # ------------------------------------------------------------
  # Pre-select country from the URL query string, e.g.
  #   .../app_direct/indicatorcomparison/?country=Kenya
  # Runs once when the session connects. Matching is case- and
  # whitespace-insensitive so the linking site needn't match casing exactly.
  # When no ?country= is supplied, this does nothing and the app loads
  # normally on the default country; the dropdown stays fully interactive.
  # ------------------------------------------------------------
  observeEvent(session$clientData$url_search, once = TRUE, {
    query <- parseQueryString(session$clientData$url_search)
    requested <- query[["country"]]
    if (!is.null(requested) && nzchar(requested)) {
      idx <- match(tolower(trimws(requested)),
                   tolower(trimws(available_countries)))
      if (!is.na(idx)) {
        updateSelectInput(session, "country",
                          selected = available_countries[idx])
      }
    }
  })

  # ------------------------------------------------------------
  # Load CSV for the selected country
  # ------------------------------------------------------------
  raw_data <- reactive({
    req(input$country)
    # Reads from the UW Stats server (http) or a local mirror, depending on
    # server_link. Path: server_link/Gates_Indicator_Comparison/estimates/<Country>/combined_results.csv
    load_country_data(server_link, input$country)
  })

  # ------------------------------------------------------------
  # Surface server / data-loading errors to the user
  # ------------------------------------------------------------
  output$data_status <- renderUI({
    result <- raw_data()
    if (!is.null(result$error)) {
      div(class = "status-err",
        tags$strong("Could not load data. "),
        tags$pre(style = "white-space: pre-wrap; margin: 6px 0 0;", result$error)
      )
    }
  })

  # ------------------------------------------------------------
  # Update Year choices from loaded data
  # ------------------------------------------------------------
  observe({
    result <- raw_data()
    req(!is.null(result$data))
    years <- sort(unique(result$data$Year), decreasing = TRUE)
    updateSelectInput(session, "year", choices = years, selected = years[1])
  })

  # ------------------------------------------------------------
  # Update Admin Level choices (only show levels present in data)
  # ------------------------------------------------------------
  observe({
    result <- raw_data()
    req(!is.null(result$data))
    available_admins <- sort(unique(result$data$Admin))
    admin_choices <- setNames(available_admins, paste0("Admin ", available_admins))
    updateSelectInput(session, "admin_level", choices = admin_choices, selected = min(available_admins))
  })

  # ------------------------------------------------------------
  # Update Indicator choices from Year + Admin Level
  # ------------------------------------------------------------
  observe({
    result <- raw_data()
    year_v <- input$year
    admin_v <- input$admin_level
    req(!is.null(result$data), year_v, admin_v)
    indicators <- result$data %>%
      filter(Year == as.numeric(year_v), Admin == as.numeric(admin_v)) %>%
      pull(Indicator) %>%
      unique() %>%
      sort()
    if (length(indicators) == 0) return()
    # Build named choices: display label => indicator ID
    indicator_labels <- sapply(indicators, get_indicator_label)
    choices <- setNames(indicators, indicator_labels)
    # Preserve current selections when possible
    cur1 <- isolate(input$indicator1)
    cur2 <- isolate(input$indicator2)
    sel1 <- if (!is.null(cur1) && cur1 %in% indicators) cur1 else indicators[1]
    sel2 <- if (!is.null(cur2) && cur2 %in% indicators && cur2 != sel1) {
      cur2
    } else if (length(indicators) >= 2) {
      indicators[indicators != sel1][1]
    } else {
      indicators[1]
    }
    updateSelectInput(session, "indicator1", choices = choices, selected = sel1)
    updateSelectInput(session, "indicator2", choices = choices, selected = sel2)
  })

  # ------------------------------------------------------------
  # Prepare wide-format plot data
  # ------------------------------------------------------------
  plot_data <- reactive({
    req(input$indicator1, input$indicator2, input$year, input$admin_level)
    result <- raw_data()
    req(!is.null(result$data))
    validate(
      need(input$indicator1 != input$indicator2, "Please select two different indicators.")
    )
    is_adm2 <- as.numeric(input$admin_level) == 2
    df <- result$data %>%
      filter(
        Admin == as.numeric(input$admin_level),
        Indicator %in% c(input$indicator1, input$indicator2),
        Year == as.numeric(input$year)
      ) %>%
      mutate(
        # Admin 1 group used for colour; for Admin 1 data this is just the region name
        admin1_name = if (is_adm2) sub("_[^_]*$", "", Region_Name) else Region_Name,
        # Display label: Admin 2 name only (after last underscore) when Admin 2
        admin_name = if (is_adm2) sub("^.*_", "", Region_Name) else Region_Name,
        Indicator = ifelse(Indicator == input$indicator1, "x", "y")
      ) %>%
      select(admin_name, admin1_name, Mean, Lower_CI, Upper_CI, Indicator) %>%
      pivot_wider(
        names_from = Indicator,
        values_from = c(Mean, Lower_CI, Upper_CI)
      )
    validate(need(nrow(df) > 0, "No data found for the selected combination."))
    df
  })

  # ------------------------------------------------------------
  # Axis labels
  # ------------------------------------------------------------
  x_label <- reactive({ req(input$indicator1); get_indicator_label(input$indicator1) })
  y_label <- reactive({ req(input$indicator2); get_indicator_label(input$indicator2) })

  # Labels that include "(log scale)" when the transform is active
  x_label_display <- reactive({
    if (isTRUE(input$log_x)) paste0(x_label(), " (log scale)") else x_label()
  })
  y_label_display <- reactive({
    if (isTRUE(input$log_y)) paste0(y_label(), " (log scale)") else y_label()
  })

  # ------------------------------------------------------------
  # Build ggplot (used for both static output and plotly conversion)
  # ------------------------------------------------------------
  # Wrap text at ~45 chars so it fits within ~75% of the axis width
  wrap_label <- function(label, width = 45) {
    paste(strwrap(label, width = width), collapse = "\n")
  }

  # Generate n breaks evenly spaced on the log scale between rmin and rmax,
  # labelled on the natural scale. Rounds to 2 significant figures for clean labels.
  log_axis_breaks <- function(rmin, rmax, n = 5) {
    rmin <- max(rmin, 1e-6)
    vals <- exp(seq(log(rmin), log(rmax), length.out = n))
    signif(vals, 2)
  }

  build_plot <- reactive({
    df <- plot_data()
    log_x <- isTRUE(input$log_x)
    log_y <- isTRUE(input$log_y)
    # Build tooltip from natural-scale values before any transformation.
    # For Admin 2, show both the Admin 1 group and the Admin 2 name.
    is_adm2 <- as.numeric(input$admin_level) == 2
    df <- df %>% mutate(
      tooltip_text = if (is_adm2) {
        paste0(
          "Admin 1: ", admin1_name,
          "<br>Admin 2: ", admin_name,
          "<br>Mean X: ", round(Mean_x, 4),
          "<br>Mean Y: ", round(Mean_y, 4)
        )
      } else {
        paste0(
          "Admin Name: ", admin_name,
          "<br>Mean X: ", round(Mean_x, 4),
          "<br>Mean Y: ", round(Mean_y, 4)
        )
      }
    )
    # Apply log transforms to means and CI bounds
    if (log_x) {
      df <- df %>% mutate(
        Mean_x = log(Mean_x),
        Lower_CI_x = log(Lower_CI_x),
        Upper_CI_x = log(Upper_CI_x)
      )
    }
    if (log_y) {
      df <- df %>% mutate(
        Mean_y = log(Mean_y),
        Lower_CI_y = log(Lower_CI_y),
        Upper_CI_y = log(Upper_CI_y)
      )
    }
    p <- ggplot(df, aes(
      x = Mean_x,
      y = Mean_y,
      color = admin1_name,
      text = tooltip_text
    ))
    if (isTRUE(input$show_ci)) {
      p <- p +
        geom_errorbar(
          aes(ymin = Lower_CI_y, ymax = Upper_CI_y),
          width = 0, alpha = 0.45, linewidth = 0.5
        ) +
        geom_errorbarh(
          aes(xmin = Lower_CI_x, xmax = Upper_CI_x),
          height = 0, alpha = 0.45, linewidth = 0.5
        )
    }
    p <- p +
      geom_point(size = 2.5) +
      theme_minimal(base_size = 13) +
      labs(
        x = wrap_label(x_label_display()),
        y = wrap_label(y_label_display()),
        color = "Admin 1 Region",
        title = paste0(input$country, " (", input$year, ")"),
        subtitle = paste0("Admin Level ", input$admin_level, " pre-modeled estimates")
      ) +
      theme(
        plot.title = element_text(face = "bold", size = 14),
        axis.title = element_text(size = 11),
        legend.title = element_text(face = "bold", size = 13)
      )
    # Per-axis user range (NA = fit to data)
    has_x_rng <- !is.na(input$x_min) && !is.na(input$x_max)
    has_y_rng <- !is.na(input$y_min) && !is.na(input$y_max)
    # X axis -------------------------------------------------------
    if (log_x) {
      # Recover natural-scale range: df$Mean_x etc. are already log-transformed
      if (has_x_rng) {
        bkmin_x <- max(input$x_min, 1e-6)
        bkmax_x <- input$x_max
      } else {
        x_nat <- exp(c(df$Mean_x, df$Lower_CI_x, df$Upper_CI_x))
        bkmin_x <- min(x_nat, na.rm = TRUE)
        bkmax_x <- max(x_nat, na.rm = TRUE)
      }
      nat_brks_x <- log_axis_breaks(bkmin_x, bkmax_x)
      if (has_x_rng) {
        p <- p + scale_x_continuous(
          limits = log(c(max(input$x_min, 1e-6), input$x_max)),
          breaks = log(nat_brks_x), labels = nat_brks_x
        )
      } else {
        p <- p + scale_x_continuous(breaks = log(nat_brks_x), labels = nat_brks_x)
      }
    } else if (has_x_rng) {
      p <- p + scale_x_continuous(limits = c(input$x_min, input$x_max))
    }
    # Y axis -------------------------------------------------------
    if (log_y) {
      if (has_y_rng) {
        bkmin_y <- max(input$y_min, 1e-6)
        bkmax_y <- input$y_max
      } else {
        y_nat <- exp(c(df$Mean_y, df$Lower_CI_y, df$Upper_CI_y))
        bkmin_y <- min(y_nat, na.rm = TRUE)
        bkmax_y <- max(y_nat, na.rm = TRUE)
      }
      nat_brks_y <- log_axis_breaks(bkmin_y, bkmax_y)
      if (has_y_rng) {
        p <- p + scale_y_continuous(
          limits = log(c(max(input$y_min, 1e-6), input$y_max)),
          breaks = log(nat_brks_y), labels = nat_brks_y
        )
      } else {
        p <- p + scale_y_continuous(breaks = log(nat_brks_y), labels = nat_brks_y)
      }
    } else if (has_y_rng) {
      p <- p + scale_y_continuous(limits = c(input$y_min, input$y_max))
    }
    p
  })

  # ------------------------------------------------------------
  # Plot canvas (switches between plotly and static)
  # ------------------------------------------------------------
  output$plot_canvas <- renderUI({
    if (isTRUE(input$interactive_plot)) {
      plotly::plotlyOutput("plot_interactive", height = "570px")
    } else {
      plotOutput("plot_static", height = "570px")
    }
  })

  output$plot_interactive <- plotly::renderPlotly({
    p <- build_plot()
    df_nat <- plot_data() # natural-scale data, before any log transform
    log_x <- isTRUE(input$log_x)
    log_y <- isTRUE(input$log_y)
    xaxis_spec <- list(title = list(text = gsub("\n", "<br>", wrap_label(x_label_display()))))
    yaxis_spec <- list(title = list(text = gsub("\n", "<br>", wrap_label(y_label_display()))))
    if (log_x) {
      has_x_rng <- !is.na(input$x_min) && !is.na(input$x_max)
      if (has_x_rng) {
        bkmin_x <- max(input$x_min, 1e-6); bkmax_x <- input$x_max
      } else {
        x_nat <- c(df_nat$Mean_x, df_nat$Lower_CI_x, df_nat$Upper_CI_x)
        bkmin_x <- min(x_nat, na.rm = TRUE); bkmax_x <- max(x_nat, na.rm = TRUE)
      }
      nat_brks_x <- log_axis_breaks(bkmin_x, bkmax_x)
      xaxis_spec$tickvals <- log(nat_brks_x)
      xaxis_spec$ticktext <- as.character(nat_brks_x)
    }
    if (log_y) {
      has_y_rng <- !is.na(input$y_min) && !is.na(input$y_max)
      if (has_y_rng) {
        bkmin_y <- max(input$y_min, 1e-6); bkmax_y <- input$y_max
      } else {
        y_nat <- c(df_nat$Mean_y, df_nat$Lower_CI_y, df_nat$Upper_CI_y)
        bkmin_y <- min(y_nat, na.rm = TRUE); bkmax_y <- max(y_nat, na.rm = TRUE)
      }
      nat_brks_y <- log_axis_breaks(bkmin_y, bkmax_y)
      yaxis_spec$tickvals <- log(nat_brks_y)
      yaxis_spec$ticktext <- as.character(nat_brks_y)
    }
    plotly::ggplotly(p, tooltip = "text") %>%
      plotly::layout(
        xaxis = xaxis_spec,
        yaxis = yaxis_spec,
        legend = list(title = list(text = "Admin 1 Region"))
      )
  })

  output$plot_static <- renderPlot({
    build_plot()
  })

  # ------------------------------------------------------------
  # Download (always available; renders the ggplot to PDF)
  # ------------------------------------------------------------
  output$download_plot <- downloadHandler(
    filename = function() {
      paste0(
        gsub(" ", "_", input$country), "_",
        input$year, "_",
        input$indicator1, "_vs_", input$indicator2,
        "_Admin", input$admin_level, "_scatter.pdf"
      )
    },
    content = function(file) {
      p <- build_plot()
      grDevices::pdf(file, width = 11, height = 8)
      print(p)
      grDevices::dev.off()
    }
  )
}

shinyApp(ui, server)
