# ============================================================
# ELEMENT 2 — STACKED BAR PLOTS
# WIO ecological representativeness
# ============================================================
#
# PLOT 1
# Distribution of each WIO habitat among sovereign states.
#
# PLOT 2
# Protected share of each WIO habitat.
#
# COMBINED FIGURE
# Plot 1 LEFT | gap | Plot 2 RIGHT
#
# ============================================================


rm(list = ls())



# ============================================================
# 1. PACKAGES
# ============================================================

pkgs <- c(
  "dplyr",
  "tibble",
  "ggplot2",
  "readr",
  "scales",
  "patchwork"
)


missing_pkgs <-
  pkgs[
    !vapply(
      pkgs,
      requireNamespace,
      logical(1),
      quietly = TRUE
    )
  ]


if (length(missing_pkgs) > 0) {
  install.packages(missing_pkgs)
}


invisible(
  lapply(
    pkgs,
    library,
    character.only = TRUE
  )
)



# ============================================================
# 2. INPUT / OUTPUT
# ============================================================

ELEMENT2_CSV <-
  file.path(
    "outputs",
    "element2",
    "element2_habitat_protection_by_sovereign.csv"
  )



# ------------------------------------------------------------
# WIO EEZ / protected-area summary
# ------------------------------------------------------------
#
# Used ONLY if:
#
# WIO_TOTAL_PROTECTED_PERCENT_OVERRIDE <- NA_real_
#
# ------------------------------------------------------------

WIO_COVERAGE_CSV_CANDIDATES <-
  c(
    
    file.path(
      "outputs",
      "eez_unique_total_protected_area_by_sovereign.csv"
    ),
    
    file.path(
      "outputs",
      "wio_eez_protected_area_by_sovereign.csv"
    ),
    
    file.path(
      "outputs",
      "wio_eez_protection_by_sovereign.csv"
    )
  )



# ------------------------------------------------------------
# WIO-wide protected proportion
# ------------------------------------------------------------

WIO_TOTAL_PROTECTED_PERCENT_OVERRIDE <-
  5.4



# ------------------------------------------------------------
# Output folder
# ------------------------------------------------------------

ELEMENT2_PLOT_DIR <-
  file.path(
    "outputs",
    "publication_plots",
    "element2"
  )


dir.create(
  ELEMENT2_PLOT_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)



# ============================================================
# 3. GENERAL SETTINGS
# ============================================================

EXCLUDED_GENERAL <-
  c(
    "WIO",
    "Disputed"
  )



# ============================================================
# 4. HABITATS
# ============================================================

ELEMENT2_HABITAT_MAP <-
  c(
    "Mangroves" = "Mangroves",
    "Coral"      = "Coral",
    "Seagrass"   = "Seagrass",
    "Seamounts"  = "Seamounts"
  )



# ============================================================
# 5. COUNTRY COLOURS
# ============================================================

ELEMENT2_COUNTRY_COLOURS_USER <-
  c(
    "Kenya"          = "#bebada",
    "Madagascar"     = "#ff7f7b",
    "Mozambique"     = "#81b1d3",
    "Mauritius"      = "#fdb462",
    "Seychelles"     = "#de5d5d",
    "Tanzania"       = "#3e9ea8",
    "Comoro Islands" = "#ffe478",
    "France"         = "#57c193",
    "South Africa"   = "#bc80bd",
    "Somalia"        = "#b3de69"
  )



# ============================================================
# 6. COUNTRY LEGEND LABELS
# ============================================================

ELEMENT2_COUNTRY_CODES <-
  c(
    "Kenya"          = "KEN",
    "Madagascar"     = "MDG",
    "Mozambique"     = "MOZ",
    "Mauritius"      = "MUS",
    "Seychelles"     = "SYC",
    "Tanzania"       = "TZA",
    "Comoro Islands" = "COM",
    "France"         = "FRA",
    "South Africa"   = "ZAF",
    "Somalia"        = "SOM"
  )



# ============================================================
# 7. REFERENCE LINES
# ============================================================

GLOBAL_PROTECTION_TARGET_PERCENT <-
  30



# Solid WIO line.

WIO_REFERENCE_LINE_COLOUR <-
  "grey20"


WIO_REFERENCE_LINE_WIDTH <-
  0.8



# Dashed 30% line.

GLOBAL_TARGET_LINE_COLOUR <-
  "grey20"


GLOBAL_TARGET_LINE_WIDTH <-
  0.8



# ============================================================
# 8. BAR WIDTH / BAR SPACING
# ============================================================
#
# Larger = wider bars = smaller gaps between habitat bars.
#
# 0.80 = larger gaps
# 0.90 = fairly close
# 0.92 = current
# 0.96 = very close
#
# ============================================================

ELEMENT2_BAR_WIDTH <-
  0.92



# ------------------------------------------------------------
# Padding outside first / last habitat
# ------------------------------------------------------------
#
# Smaller = less blank space at left/right edge of each panel.
# ------------------------------------------------------------

ELEMENT2_X_SIDE_PADDING <-
  0.6



ELEMENT2_BAR_BORDER_COLOUR <-
  NA_character_


ELEMENT2_BAR_BORDER_WIDTH <-
  0



# ============================================================
# 9. TEXT SIZE SETTINGS
# ============================================================


# Habitat names:
# Mangroves / Coral / Seagrass / Seamounts

ELEMENT2_X_AXIS_TEXT_SIZE <-
  10



# Y-axis tick labels:
# 0%, 20%, 40% etc.

ELEMENT2_Y_AXIS_TEXT_SIZE <-
  10



# Y-axis titles.

ELEMENT2_Y_AXIS_TITLE_SIZE <-
  13


# ============================================================
# 10. LEGEND SETTINGS
# ============================================================

ELEMENT2_LEGEND_TITLE <-
  "WIO Countries"



ELEMENT2_LEGEND_TITLE_SIZE <-
  13



ELEMENT2_LEGEND_TEXT_SIZE <-
  10



# ------------------------------------------------------------
# NUMBER OF LEGEND ROWS
# ------------------------------------------------------------
#
# 1 = all countries in one row
# 2 = countries split over two rows
#
# This is the ONLY setting you need to change for this.
# ------------------------------------------------------------

ELEMENT2_LEGEND_NROW <-
  2



# ------------------------------------------------------------
# GAP BETWEEN X AXES AND LEGEND
# ------------------------------------------------------------
#
# Larger number = legend farther below plots.
# ------------------------------------------------------------

ELEMENT2_LEGEND_TOP_GAP_PT <-
  30



# Legend key dimensions.

ELEMENT2_LEGEND_KEY_WIDTH_CM <-
  0.45


ELEMENT2_LEGEND_KEY_HEIGHT_CM <-
  0.35



# Horizontal gap between legend entries.

ELEMENT2_LEGEND_ITEM_SPACING_CM <-
  0.20



# ============================================================
# 11. PLOT MARGINS
# ============================================================

ELEMENT2_PLOT_MARGIN_TOP_PT <-
  5


ELEMENT2_PLOT_MARGIN_RIGHT_PT <-
  5


ELEMENT2_PLOT_MARGIN_BOTTOM_PT <-
  5


ELEMENT2_PLOT_MARGIN_LEFT_PT <-
  5



# ============================================================
# 12. Y AXES
# ============================================================


# Plot 1.

ELEMENT2_PLOT1_Y_BREAKS <-
  seq(
    0,
    1,
    by = 0.2
  )



# Plot 2.

ELEMENT2_PLOT2_Y_MAX <-
  100


ELEMENT2_PLOT2_Y_BREAKS <-
  seq(
    0,
    ELEMENT2_PLOT2_Y_MAX,
    by = 20
  )



# ============================================================
# 13. COMBINED FIGURE SETTINGS
# ============================================================


# Individual plots.

ELEMENT2_SINGLE_PLOT_WIDTH <-
  8


ELEMENT2_SINGLE_PLOT_HEIGHT <-
  6



# ------------------------------------------------------------
# Combined landscape output
# ------------------------------------------------------------

ELEMENT2_COMBINED_WIDTH <-
  14


ELEMENT2_COMBINED_HEIGHT <-
  5



# ------------------------------------------------------------
# GAP BETWEEN PLOT 1 AND PLOT 2
# ------------------------------------------------------------
#
# THIS controls the white space in the centre.
#
# 0.03 = tiny
# 0.05 = subtle
# 0.07 = current
# 0.10 = more obvious
# 0.15 = large
#
# ------------------------------------------------------------

ELEMENT2_COMBINED_PANEL_GAP_REL <-
  0.07



ELEMENT2_PLOT_DPI <-
  400



# ============================================================
# 14. HELPERS
# ============================================================

sum_or_na <- function(x) {
  
  if (all(is.na(x))) {
    
    return(
      NA_real_
    )
  }
  
  
  sum(
    x,
    na.rm = TRUE
  )
}



find_first_column <- function(
    data,
    candidates,
    description) {
  
  
  found <-
    candidates[
      candidates %in%
        names(data)
    ]
  
  
  if (length(found) == 0) {
    
    stop(
      paste0(
        "\nCould not find ",
        description,
        " column.\n\n",
        "Tried:\n",
        paste(
          candidates,
          collapse = "\n"
        ),
        "\n\nAvailable columns:\n",
        paste(
          names(data),
          collapse = "\n"
        )
      )
    )
  }
  
  
  found[[1]]
}



complete_element2_country_colours <- function(
    observed_countries) {
  
  
  observed_countries <-
    unique(
      as.character(
        observed_countries
      )
    )
  
  
  supplied <-
    ELEMENT2_COUNTRY_COLOURS_USER[
      intersect(
        observed_countries,
        names(
          ELEMENT2_COUNTRY_COLOURS_USER
        )
      )
    ]
  
  
  missing_countries <-
    setdiff(
      observed_countries,
      names(supplied)
    )
  
  
  if (length(missing_countries) > 0) {
    
    message(
      "No custom colour supplied for: ",
      paste(
        missing_countries,
        collapse = ", "
      ),
      ". Fallback colours will be used."
    )
    
    
    fallback <-
      stats::setNames(
        
        grDevices::hcl.colors(
          
          n =
            length(
              missing_countries
            ),
          
          palette =
            "Dark 3"
        ),
        
        missing_countries
      )
    
    
    supplied <-
      c(
        supplied,
        fallback
      )
  }
  
  
  supplied[
    observed_countries
  ]
}



# ============================================================
# 15. READ ELEMENT 2 DATA
# ============================================================

if (!file.exists(ELEMENT2_CSV)) {
  
  stop(
    "Element 2 CSV not found:\n",
    ELEMENT2_CSV
  )
}



element2 <-
  readr::read_csv(
    ELEMENT2_CSV,
    show_col_types = FALSE
  )



required_element2_cols <-
  c(
    "sovereign_state",
    "indicator",
    "measure_type",
    "indicator_area_km2",
    "protected_indicator_area_km2"
  )



missing_element2_cols <-
  setdiff(
    required_element2_cols,
    names(element2)
  )



if (length(missing_element2_cols) > 0) {
  
  stop(
    "Element 2 CSV is missing required columns:\n",
    paste(
      missing_element2_cols,
      collapse = "\n"
    )
  )
}



# ============================================================
# 16. CALCULATE WIO-WIDE PROTECTED-AREA REFERENCE
# ============================================================

if (
  is.finite(
    WIO_TOTAL_PROTECTED_PERCENT_OVERRIDE
  )
) {
  
  
  wio_total_protected_percent <-
    WIO_TOTAL_PROTECTED_PERCENT_OVERRIDE
  
  
  message(
    "\nUsing manual WIO protected-area percentage: ",
    round(
      wio_total_protected_percent,
      3
    ),
    "%"
  )
  
  
} else {
  
  
  existing_wio_files <-
    WIO_COVERAGE_CSV_CANDIDATES[
      file.exists(
        WIO_COVERAGE_CSV_CANDIDATES
      )
    ]
  
  
  if (length(existing_wio_files) == 0) {
    
    stop(
      paste0(
        "\nCould not find WIO EEZ/protected-area summary CSV.\n\n",
        "Either add its path to WIO_COVERAGE_CSV_CANDIDATES ",
        "or enter the WIO percentage directly in ",
        "WIO_TOTAL_PROTECTED_PERCENT_OVERRIDE."
      )
    )
  }
  
  
  
  WIO_COVERAGE_CSV <-
    existing_wio_files[[1]]
  
  
  
  wio_coverage <-
    readr::read_csv(
      WIO_COVERAGE_CSV,
      show_col_types = FALSE
    )
  
  
  
  eez_area_col <-
    find_first_column(
      
      data =
        wio_coverage,
      
      candidates =
        c(
          "eez_area_km2",
          "EEZ_area_km2",
          "eez_km2",
          "eez_area",
          "total_eez_area_km2",
          "EEZ_km2"
        ),
      
      description =
        "EEZ area"
    )
  
  
  
  protected_area_col <-
    find_first_column(
      
      data =
        wio_coverage,
      
      candidates =
        c(
          "total_protected_area_km2",
          "protected_area_km2",
          "unique_total_protected_area_km2",
          "protected_total_area_km2",
          "total_protected_km2",
          "protected_km2"
        ),
      
      description =
        "total protected area"
    )
  
  
  
  sovereign_candidates <-
    c(
      "sovereign_state",
      "Sovereign",
      "sovereign",
      "country"
    )
  
  
  
  sovereign_found <-
    sovereign_candidates[
      sovereign_candidates %in%
        names(wio_coverage)
    ]
  
  
  
  if (length(sovereign_found) > 0) {
    
    
    sovereign_col <-
      sovereign_found[[1]]
    
    
    
    wio_rows <-
      wio_coverage |>
      dplyr::filter(
        
        as.character(
          .data[[sovereign_col]]
        ) ==
          "WIO"
      )
    
    
    
    if (nrow(wio_rows) > 0) {
      
      
      total_wio_eez_area_km2 <-
        sum(
          readr::parse_number(
            as.character(
              wio_rows[[eez_area_col]]
            )
          ),
          na.rm = TRUE
        )
      
      
      
      total_wio_protected_area_km2 <-
        sum(
          readr::parse_number(
            as.character(
              wio_rows[[protected_area_col]]
            )
          ),
          na.rm = TRUE
        )
      
      
    } else {
      
      
      wio_sovereign_rows <-
        wio_coverage |>
        dplyr::filter(
          
          !as.character(
            .data[[sovereign_col]]
          ) %in%
            c(
              "WIO",
              "Disputed"
            )
        )
      
      
      
      total_wio_eez_area_km2 <-
        sum(
          readr::parse_number(
            as.character(
              wio_sovereign_rows[[eez_area_col]]
            )
          ),
          na.rm = TRUE
        )
      
      
      
      total_wio_protected_area_km2 <-
        sum(
          readr::parse_number(
            as.character(
              wio_sovereign_rows[[protected_area_col]]
            )
          ),
          na.rm = TRUE
        )
    }
    
    
  } else {
    
    
    total_wio_eez_area_km2 <-
      sum(
        readr::parse_number(
          as.character(
            wio_coverage[[eez_area_col]]
          )
        ),
        na.rm = TRUE
      )
    
    
    
    total_wio_protected_area_km2 <-
      sum(
        readr::parse_number(
          as.character(
            wio_coverage[[protected_area_col]]
          )
        ),
        na.rm = TRUE
      )
  }
  
  
  
  if (
    !is.finite(
      total_wio_eez_area_km2
    ) ||
    total_wio_eez_area_km2 <= 0
  ) {
    
    stop(
      "Calculated WIO EEZ area is invalid."
    )
  }
  
  
  
  wio_total_protected_percent <-
    100 *
    total_wio_protected_area_km2 /
    total_wio_eez_area_km2
}



# ============================================================
# 17. FILTER HABITAT DATA
# ============================================================

habitat_names <-
  names(
    ELEMENT2_HABITAT_MAP
  )



element2_area <-
  element2 |>
  dplyr::filter(
    
    !sovereign_state %in%
      EXCLUDED_GENERAL,
    
    measure_type ==
      "area",
    
    indicator %in%
      habitat_names,
    
    !is.na(
      sovereign_state
    ),
    
    nzchar(
      trimws(
        sovereign_state
      )
    ),
    
    !is.na(
      indicator_area_km2
    ),
    
    indicator_area_km2 >
      0
  )



# ============================================================
# 18. CHECK HABITAT NAMES
# ============================================================

available_area_habitats <-
  element2 |>
  dplyr::filter(
    measure_type ==
      "area"
  ) |>
  dplyr::distinct(
    indicator
  ) |>
  dplyr::pull(
    indicator
  )



missing_habitats <-
  setdiff(
    habitat_names,
    available_area_habitats
  )



if (length(missing_habitats) > 0) {
  
  stop(
    paste0(
      "\nRequested habitats not found:\n\n",
      paste(
        missing_habitats,
        collapse = "\n"
      ),
      "\n\nAvailable area indicators:\n\n",
      paste(
        available_area_habitats,
        collapse = "\n"
      )
    )
  )
}



# ============================================================
# 19. AGGREGATE HABITAT x COUNTRY
# ============================================================

habitat_country <-
  element2_area |>
  dplyr::group_by(
    indicator,
    sovereign_state
  ) |>
  dplyr::summarise(
    
    habitat_area_km2 =
      sum(
        indicator_area_km2,
        na.rm = TRUE
      ),
    
    protected_habitat_area_km2 =
      sum_or_na(
        protected_indicator_area_km2
      ),
    
    .groups =
      "drop"
  )



# ============================================================
# 20. CHECK PROTECTED VALUES
# ============================================================

missing_protected <-
  habitat_country |>
  dplyr::filter(
    is.na(
      protected_habitat_area_km2
    )
  )



if (nrow(missing_protected) > 0) {
  
  stop(
    paste0(
      "\nMissing protected habitat area for:\n\n",
      paste(
        paste0(
          missing_protected$indicator,
          " — ",
          missing_protected$sovereign_state
        ),
        collapse = "\n"
      )
    )
  )
}



# ============================================================
# 21. VALIDATE PROTECTED <= TOTAL HABITAT
# ============================================================

habitat_country <-
  habitat_country |>
  dplyr::mutate(
    
    numerical_tolerance =
      1e-6 *
      pmax(
        1,
        habitat_area_km2
      )
  )



invalid_protection <-
  habitat_country |>
  dplyr::filter(
    
    protected_habitat_area_km2 >
      habitat_area_km2 +
      numerical_tolerance
  )



if (nrow(invalid_protection) > 0) {
  
  stop(
    paste0(
      "\nProtected habitat area exceeds total habitat area for:\n\n",
      paste(
        paste0(
          invalid_protection$indicator,
          " — ",
          invalid_protection$sovereign_state
        ),
        collapse = "\n"
      )
    )
  )
}



habitat_country <-
  habitat_country |>
  dplyr::mutate(
    
    protected_habitat_area_km2 =
      pmin(
        protected_habitat_area_km2,
        habitat_area_km2
      )
  ) |>
  dplyr::select(
    -numerical_tolerance
  )



# ============================================================
# 22. WIO HABITAT TOTALS
# ============================================================

habitat_totals <-
  habitat_country |>
  dplyr::group_by(
    indicator
  ) |>
  dplyr::summarise(
    
    wio_habitat_area_km2 =
      sum(
        habitat_area_km2,
        na.rm = TRUE
      ),
    
    wio_protected_habitat_area_km2 =
      sum(
        protected_habitat_area_km2,
        na.rm = TRUE
      ),
    
    .groups =
      "drop"
  ) |>
  dplyr::mutate(
    
    wio_percent_protected =
      100 *
      wio_protected_habitat_area_km2 /
      wio_habitat_area_km2
  )



# ============================================================
# 23. BUILD PLOTTING DATA
# ============================================================

plot_data <-
  habitat_country |>
  dplyr::left_join(
    habitat_totals,
    by = "indicator"
  ) |>
  dplyr::mutate(
    
    
    habitat_share_percent =
      100 *
      habitat_area_km2 /
      wio_habitat_area_km2,
    
    
    protected_contribution_percent =
      100 *
      protected_habitat_area_km2 /
      wio_habitat_area_km2,
    
    
    habitat =
      unname(
        ELEMENT2_HABITAT_MAP[
          indicator
        ]
      ),
    
    
    habitat =
      factor(
        habitat,
        levels =
          unname(
            ELEMENT2_HABITAT_MAP
          )
      )
  )



# ============================================================
# 24. COUNTRY ORDER / COLOURS / LEGEND
# ============================================================

observed_countries <-
  unique(
    as.character(
      plot_data$sovereign_state
    )
  )



country_levels <-
  c(
    
    intersect(
      names(
        ELEMENT2_COUNTRY_COLOURS_USER
      ),
      observed_countries
    ),
    
    sort(
      setdiff(
        observed_countries,
        names(
          ELEMENT2_COUNTRY_COLOURS_USER
        )
      )
    )
  )



country_colours <-
  complete_element2_country_colours(
    country_levels
  )



country_legend_labels <-
  vapply(
    
    country_levels,
    
    function(country) {
      
      if (
        country %in%
        names(
          ELEMENT2_COUNTRY_CODES
        )
      ) {
        
        return(
          ELEMENT2_COUNTRY_CODES[[country]]
        )
      }
      
      
      country
    },
    
    character(1)
  )



names(
  country_legend_labels
) <-
  country_levels



plot_data <-
  plot_data |>
  dplyr::mutate(
    
    sovereign_state =
      factor(
        as.character(
          sovereign_state
        ),
        levels =
          country_levels
      )
  )



if (
  any(
    is.na(
      plot_data$sovereign_state
    )
  )
) {
  
  stop(
    "At least one sovereign state became NA after factor conversion."
  )
}



# ============================================================
# 25. QA — PLOT 1
# ============================================================

plot1_qa <-
  plot_data |>
  dplyr::group_by(
    indicator,
    habitat
  ) |>
  dplyr::summarise(
    
    total_percent =
      sum(
        habitat_share_percent,
        na.rm = FALSE
      ),
    
    .groups =
      "drop"
  )



print(
  plot1_qa,
  n = Inf
)



if (
  any(
    !is.finite(
      plot1_qa$total_percent
    ) |
    abs(
      plot1_qa$total_percent -
      100
    ) >
    1e-6
  )
) {
  
  stop(
    "At least one Plot 1 habitat does not sum to 100%."
  )
}



# ============================================================
# 26. QA — PLOT 2
# ============================================================

plot2_qa <-
  plot_data |>
  dplyr::group_by(
    indicator,
    habitat
  ) |>
  dplyr::summarise(
    
    stack_height_percent =
      sum(
        protected_contribution_percent,
        na.rm = FALSE
      ),
    
    expected_wio_percent_protected =
      dplyr::first(
        wio_percent_protected
      ),
    
    difference =
      stack_height_percent -
      expected_wio_percent_protected,
    
    .groups =
      "drop"
  )



print(
  plot2_qa,
  n = Inf
)



# ============================================================
# 27. SAVE QA DATA
# ============================================================

readr::write_csv(
  
  plot1_qa,
  
  file.path(
    ELEMENT2_PLOT_DIR,
    "element2_plot1_QA.csv"
  )
)



readr::write_csv(
  
  plot2_qa,
  
  file.path(
    ELEMENT2_PLOT_DIR,
    "element2_plot2_QA.csv"
  )
)



readr::write_csv(
  
  plot_data |>
    dplyr::select(
      indicator,
      habitat,
      sovereign_state,
      habitat_area_km2,
      protected_habitat_area_km2,
      wio_habitat_area_km2,
      habitat_share_percent,
      protected_contribution_percent,
      wio_percent_protected
    ),
  
  file.path(
    ELEMENT2_PLOT_DIR,
    "element2_stacked_barplot_data.csv"
  )
)



# ============================================================
# 28. COMMON PLOT THEME
# ============================================================

element2_common_theme <-
  ggplot2::theme_minimal(
    base_size = 10
  ) +
  
  
  ggplot2::theme(
    
    
    # --------------------------------------------------------
    # GRID
    # --------------------------------------------------------
    
    panel.grid.major.x =
      ggplot2::element_blank(),
    
    
    panel.grid.minor =
      ggplot2::element_blank(),
    
    
    
    # --------------------------------------------------------
    # X AXIS CATEGORY LABELS
    #
    # Mangroves / Coral / Seagrass / Seamounts
    # --------------------------------------------------------
    
    axis.text.x =
      ggplot2::element_text(
        
        size =
          ELEMENT2_X_AXIS_TEXT_SIZE,
        
        face =
          "bold",
        
        colour =
          "grey20",
        
        margin =
          ggplot2::margin(
            t = 3
          )
      ),
    
    
    
    # --------------------------------------------------------
    # Y AXIS TICK LABELS
    # --------------------------------------------------------
    
    axis.text.y =
      ggplot2::element_text(
        
        size =
          ELEMENT2_Y_AXIS_TEXT_SIZE,
        
        colour =
          "grey20"
      ),
    
    
    
    # --------------------------------------------------------
    # Y AXIS TITLE
    # --------------------------------------------------------
    
    axis.title.y =
      ggplot2::element_text(
        
        size =
          ELEMENT2_Y_AXIS_TITLE_SIZE,
        
        margin =
          ggplot2::margin(
            r = 6
          )
      ),
    
    
    
    # --------------------------------------------------------
    # LEGEND
    # --------------------------------------------------------
    
    legend.position =
      "bottom",
    
    
    legend.justification =
      "center",
    
    
    legend.box.just =
      "center",
    
    
    legend.direction =
      "horizontal",
    
    
    
    # Gap between plots and legend.
    
    legend.box.spacing =
      grid::unit(
        ELEMENT2_LEGEND_TOP_GAP_PT,
        "pt"
      ),
    
    
    
    legend.title =
      ggplot2::element_text(
        
        face =
          "bold",
        
        size =
          ELEMENT2_LEGEND_TITLE_SIZE
      ),
    
    
    
    legend.text =
      ggplot2::element_text(
        
        size =
          ELEMENT2_LEGEND_TEXT_SIZE
      ),
    
    
    
    legend.key.width =
      grid::unit(
        ELEMENT2_LEGEND_KEY_WIDTH_CM,
        "cm"
      ),
    
    
    
    legend.key.height =
      grid::unit(
        ELEMENT2_LEGEND_KEY_HEIGHT_CM,
        "cm"
      ),
    
    
    
    legend.spacing.x =
      grid::unit(
        ELEMENT2_LEGEND_ITEM_SPACING_CM,
        "cm"
      ),
    
    
    
    # --------------------------------------------------------
    # PLOT MARGINS
    # --------------------------------------------------------
    
    plot.margin =
      ggplot2::margin(
        
        t =
          ELEMENT2_PLOT_MARGIN_TOP_PT,
        
        r =
          ELEMENT2_PLOT_MARGIN_RIGHT_PT,
        
        b =
          ELEMENT2_PLOT_MARGIN_BOTTOM_PT,
        
        l =
          ELEMENT2_PLOT_MARGIN_LEFT_PT,
        
        unit =
          "pt"
      )
  )



# ============================================================
# 29. PLOT 1
# DISTRIBUTION OF WIO HABITAT
# ============================================================

plot_habitat_distribution <-
  ggplot2::ggplot(
    
    plot_data,
    
    ggplot2::aes(
      
      x =
        habitat,
      
      y =
        habitat_area_km2,
      
      fill =
        sovereign_state
    )
  ) +
  
  
  ggplot2::geom_col(
    
    position =
      "fill",
    
    width =
      ELEMENT2_BAR_WIDTH,
    
    colour =
      ELEMENT2_BAR_BORDER_COLOUR,
    
    linewidth =
      ELEMENT2_BAR_BORDER_WIDTH
  ) +
  
  
  ggplot2::scale_x_discrete(
    
    expand =
      ggplot2::expansion(
        
        add =
          ELEMENT2_X_SIDE_PADDING
      )
  ) +
  
  
  ggplot2::scale_fill_manual(
    
    values =
      country_colours,
    
    breaks =
      country_levels,
    
    labels =
      country_legend_labels,
    
    drop =
      FALSE,
    
    name =
      ELEMENT2_LEGEND_TITLE,
    
    guide =
      ggplot2::guide_legend(
        
        nrow =
          ELEMENT2_LEGEND_NROW,
        
        byrow =
          TRUE,
        
        
        # ----------------------------------------------------
        # LEGEND TITLE TO LEFT OF COUNTRY KEYS
        # ----------------------------------------------------
        
        title.position =
          "left",
        
        title.hjust =
          0.5
      )
  ) +
  
  
  ggplot2::scale_y_continuous(
    
    breaks =
      ELEMENT2_PLOT1_Y_BREAKS,
    
    labels =
      scales::label_percent(
        accuracy = 1
      ),
    
    expand =
      ggplot2::expansion(
        mult =
          c(
            0,
            0
          )
      )
  ) +
  
  
  ggplot2::coord_cartesian(
    
    ylim =
      c(
        0,
        1
      ),
    
    clip =
      "off"
  ) +
  
  
  ggplot2::labs(
    
    x =
      NULL,
    
    y =
      "Proportion of habitat"
  ) +
  
  
  element2_common_theme



# ============================================================
# 30. PLOT 2
# PROTECTED HABITAT
# ============================================================

plot_habitat_protected <-
  ggplot2::ggplot(
    
    plot_data,
    
    ggplot2::aes(
      
      x =
        habitat,
      
      y =
        protected_contribution_percent,
      
      fill =
        sovereign_state
    )
  ) +
  
  
  ggplot2::geom_col(
    
    position =
      "stack",
    
    width =
      ELEMENT2_BAR_WIDTH,
    
    colour =
      ELEMENT2_BAR_BORDER_COLOUR,
    
    linewidth =
      ELEMENT2_BAR_BORDER_WIDTH
  ) +
  
  
  ggplot2::scale_x_discrete(
    
    expand =
      ggplot2::expansion(
        
        add =
          ELEMENT2_X_SIDE_PADDING
      )
  ) +
  
  
  # ----------------------------------------------------------
# SOLID WIO-WIDE COVERAGE LINE
# ----------------------------------------------------------
# 
# ggplot2::geom_hline(
#   
#   yintercept =
#     wio_total_protected_percent,
#   
#   linetype =
#     "solid",
#   
#   colour =
#     WIO_REFERENCE_LINE_COLOUR,
#   
#   linewidth =
#     WIO_REFERENCE_LINE_WIDTH,
#   
#   show.legend =
#     FALSE
# ) +
#   
  
  # ----------------------------------------------------------
# DASHED 30% GLOBAL TARGET
# ----------------------------------------------------------

# ggplot2::geom_hline(
#   
#   yintercept =
#     GLOBAL_PROTECTION_TARGET_PERCENT,
#   
#   linetype =
#     "dashed",
#   
#   colour =
#     GLOBAL_TARGET_LINE_COLOUR,
#   
#   linewidth =
#     GLOBAL_TARGET_LINE_WIDTH,
#   
#   show.legend =
#     FALSE
# ) +
  
  
  ggplot2::scale_fill_manual(
    
    values =
      country_colours,
    
    breaks =
      country_levels,
    
    labels =
      country_legend_labels,
    
    drop =
      FALSE,
    
    name =
      ELEMENT2_LEGEND_TITLE,
    
    guide =
      ggplot2::guide_legend(
        
        nrow =
          ELEMENT2_LEGEND_NROW,
        
        byrow =
          TRUE,
        
        
        # ----------------------------------------------------
        # LEGEND TITLE TO LEFT OF COUNTRY KEYS
        # ----------------------------------------------------
        
        title.position =
          "left",
        
        title.hjust =
          0.5
      )
  ) +
  
  
  ggplot2::scale_y_continuous(
    
    breaks =
      ELEMENT2_PLOT2_Y_BREAKS,
    
    labels =
      function(x) {
        
        paste0(
          x,
          "%"
        )
      },
    
    expand =
      ggplot2::expansion(
        mult =
          c(
            0,
            0.02
          )
      )
  ) +
  
  
  ggplot2::coord_cartesian(
    
    ylim =
      c(
        0,
        ELEMENT2_PLOT2_Y_MAX
      ),
    
    clip =
      "off"
  ) +
  
  
  ggplot2::labs(
    
    x =
      NULL,
    
    y =
      "Proportion of protected habitat"
  ) +
  
  
  element2_common_theme




# ============================================================
# 31. DISPLAY INDIVIDUAL PLOTS
# ============================================================

print(
  plot_habitat_distribution
)


print(
  plot_habitat_protected
)



# ============================================================
# 32. SAVE INDIVIDUAL PLOTS
# ============================================================

ggplot2::ggsave(
  
  filename =
    file.path(
      ELEMENT2_PLOT_DIR,
      "element2_habitat_distribution_by_country_stacked_barplot.png"
    ),
  
  plot =
    plot_habitat_distribution,
  
  width =
    ELEMENT2_SINGLE_PLOT_WIDTH,
  
  height =
    ELEMENT2_SINGLE_PLOT_HEIGHT,
  
  dpi =
    ELEMENT2_PLOT_DPI,
  
  bg =
    "white"
)



ggplot2::ggsave(
  
  filename =
    file.path(
      ELEMENT2_PLOT_DIR,
      "element2_habitat_protected_by_country_stacked_barplot.png"
    ),
  
  plot =
    plot_habitat_protected,
  
  width =
    ELEMENT2_SINGLE_PLOT_WIDTH,
  
  height =
    ELEMENT2_SINGLE_PLOT_HEIGHT,
  
  dpi =
    ELEMENT2_PLOT_DPI,
  
  bg =
    "white"
)



# ============================================================
# 33. COMBINED FIGURE
#
# PLOT 1 | GAP | PLOT 2
# ============================================================
#
# Change:
#
# ELEMENT2_COMBINED_PANEL_GAP_REL
#
# near the top if you want more / less space in the middle.
# ============================================================

combined_plot <-
  
  (
    plot_habitat_distribution |
      
      patchwork::plot_spacer() |
      
      plot_habitat_protected
  ) +
  
  
  patchwork::plot_layout(
    
    widths =
      c(
        1,
        ELEMENT2_COMBINED_PANEL_GAP_REL,
        1
      ),
    
    guides =
      "collect"
  ) &
  
  
  ggplot2::theme(
    
    
    # Shared legend.
    
    legend.position =
      "bottom",
    
    
    # Centre entire legend beneath the two plots.
    
    legend.justification =
      "center",
    
    
    legend.box.just =
      "center",
    
    
    legend.direction =
      "horizontal",
    
    
    # Gap between plots and legend.
    
    legend.box.spacing =
      grid::unit(
        ELEMENT2_LEGEND_TOP_GAP_PT,
        "pt"
      )
  )



print(
  combined_plot
)



# ============================================================
# 34. SAVE COMBINED LANDSCAPE FIGURE
# ============================================================

ggplot2::ggsave(
  
  filename =
    file.path(
      ELEMENT2_PLOT_DIR,
      "element2_habitat_distribution_and_protection_stacked_barplots.png"
    ),
  
  plot =
    combined_plot,
  
  width =
    ELEMENT2_COMBINED_WIDTH,
  
  height =
    ELEMENT2_COMBINED_HEIGHT,
  
  dpi =
    ELEMENT2_PLOT_DPI,
  
  bg =
    "white"
)



# ============================================================
# 35. PRINT WIO HABITAT PROTECTION TOTALS
# ============================================================

wio_summary_for_print <-
  habitat_totals |>
  dplyr::mutate(
    
    habitat =
      unname(
        ELEMENT2_HABITAT_MAP[
          indicator
        ]
      ),
    
    habitat =
      factor(
        habitat,
        levels =
          unname(
            ELEMENT2_HABITAT_MAP
          )
      ),
    
    percent_protected =
      round(
        wio_percent_protected,
        2
      )
  ) |>
  dplyr::arrange(
    habitat
  ) |>
  dplyr::select(
    
    habitat,
    
    wio_habitat_area_km2,
    
    wio_protected_habitat_area_km2,
    
    percent_protected
  )



print(
  wio_summary_for_print,
  n = Inf
)



# ============================================================
# 36. COMPLETE
# ============================================================

message(
  "\n============================================================"
)


message(
  "ELEMENT 2 STACKED BAR PLOTS COMPLETE"
)


message(
  "============================================================"
)


message(
  "\nWIO total protected-area reference: ",
  round(
    wio_total_protected_percent,
    2
  ),
  "%"
)


message(
  "\nGlobal target reference: ",
  GLOBAL_PROTECTION_TARGET_PERCENT,
  "%"
)


message(
  "\nCombined figure layout: PLOT 1 | GAP | PLOT 2"
)


message(
  "\nOutput folder:\n",
  normalizePath(
    ELEMENT2_PLOT_DIR
  )
)


message(
  "\nDone."
)