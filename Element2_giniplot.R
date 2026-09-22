# ============================================================
# ELEMENT 2 — GINI COEFFICIENT BUBBLE PLOTS
#
# Produces TWO versions:
#
#   1. RAW Gini coefficient
#      - consistent with previous WIO gini.wtd() analysis
#
#   2. NORMALISED Gini coefficient
#      - finite-sample correction:
#            Gini_raw * n / (n - 1)
#
# Both plots use:
#   x     = habitat / MPA area
#   y     = sovereign state
#   fill  = Gini coefficient
#   size  = total number of MPAs
#
# Comoros labels are placed above the bubbles because the
# small number of MPAs produces very small circles.
# ============================================================


# ------------------------------------------------------------
# 1. PACKAGES
# ------------------------------------------------------------

library(readr)
library(dplyr)
library(ggplot2)
library(viridis)


# ------------------------------------------------------------
# 2. INPUT / OUTPUT
# ------------------------------------------------------------

gini_csv <-
  "outputs/element2/element2_gini_plot_data.csv"


plot_dir <-
  "outputs/element2/plots"


dir.create(
  plot_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


raw_plot_file <-
  file.path(
    plot_dir,
    "element2_gini_bubble_plot_raw.png"
  )


normalised_plot_file <-
  file.path(
    plot_dir,
    "element2_gini_bubble_plot_normalised.png"
  )


# ------------------------------------------------------------
# 3. LOAD GINI DATA
# ------------------------------------------------------------

gini <-
  readr::read_csv(
    gini_csv,
    show_col_types = FALSE
  )


print(gini)
str(gini)


# ------------------------------------------------------------
# 4. CHECK REQUIRED COLUMNS
# ------------------------------------------------------------

required_columns <-
  c(
    "sovereign_state",
    "indicator",
    "n_mpas_total",
    "gini_raw",
    "gini_normalised"
  )


missing_columns <-
  setdiff(
    required_columns,
    names(gini)
  )


if (length(missing_columns) > 0) {
  
  stop(
    "The following required columns are missing from the Gini CSV:\n",
    paste(
      missing_columns,
      collapse = ", "
    )
  )
}


# ------------------------------------------------------------
# 5. COUNTRY / INDICATOR ORDER
# ------------------------------------------------------------

country_order <-
  c(
    "Tanzania",
    "South Africa",
    "Seychelles",
    "Mozambique",
    "Mauritius",
    "Madagascar",
    "Kenya",
    "France",
    "Comoros"
  )


indicator_order <-
  c(
    "Area",
    "Mangrove",
    "Reef",
    "Seagrass",
    "Seamount"
  )


# ------------------------------------------------------------
# 6. PREPARE COMMON PLOT DATA
# ------------------------------------------------------------

gini_plot_data <-
  gini |>
  
  dplyr::select(
    sovereign_state,
    indicator,
    n_mpas_total,
    gini_raw,
    gini_normalised
  ) |>
  
  dplyr::mutate(
    
    # Standardise country name
    sovereign_state =
      dplyr::recode(
        sovereign_state,
        "Comoro Islands" = "Comoros"
      ),
    
    # Labels matching previous figure
    indicator =
      dplyr::recode(
        indicator,
        "MPA area"  = "Area",
        "Mangroves" = "Mangrove",
        "Coral"     = "Reef",
        "Seagrass"  = "Seagrass",
        "Seamounts" = "Seamount"
      ),
    
    # Country order
    sovereign_state =
      factor(
        sovereign_state,
        levels = country_order
      ),
    
    # Indicator order
    indicator =
      factor(
        indicator,
        levels = indicator_order
      )
  )


# ------------------------------------------------------------
# 7. CHECK FINAL DATA
# ------------------------------------------------------------

print(
  gini_plot_data |>
    dplyr::arrange(
      sovereign_state,
      indicator
    )
)


# ============================================================
# 8. PLOTTING FUNCTION
# ============================================================
#
# This function makes the two figures identical except for the
# Gini variable supplied:
#
#   gini_raw
#   gini_normalised
#
# Keeping everything else identical makes the comparison
# between the two formulations straightforward.
# ============================================================

make_gini_plot <- function(
    data,
    gini_variable,
    plot_title = NULL) {
  
  
  # ----------------------------------------------------------
  # Pull selected Gini column into a common plotting variable
  # ----------------------------------------------------------
  
  plot_data <-
    data |>
    dplyr::mutate(
      
      gini_value =
        .data[[gini_variable]],
      
      # Label to two decimal places
      gini_label =
        dplyr::if_else(
          is.na(gini_value),
          "",
          sprintf(
            "%.2f",
            gini_value
          )
        )
    )
  
  
  # ----------------------------------------------------------
  # Split labels into:
  #
  # 1. All countries except Comoros -> inside bubble
  # 2. Comoros -> above bubble
  # ----------------------------------------------------------
  
  label_inside <-
    plot_data |>
    dplyr::filter(
      sovereign_state !=
        "Comoros"
    )
  
  
  label_comoros <-
    plot_data |>
    dplyr::filter(
      sovereign_state ==
        "Comoros"
    )
  
  
  # ----------------------------------------------------------
  # Plot
  # ----------------------------------------------------------
  
  p <-
    ggplot2::ggplot(
      plot_data,
      ggplot2::aes(
        x = indicator,
        y = sovereign_state
      )
    ) +
    
    # --------------------------------------------------------
  # Bubbles
  # --------------------------------------------------------
  
  ggplot2::geom_point(
    ggplot2::aes(
      size = n_mpas_total,
      fill = gini_value
    ),
    shape = 21,
    colour = "grey85",
    stroke = 0.4
  ) +
    
    
    # --------------------------------------------------------
  # Labels INSIDE bubbles
  #
  # Slightly smaller than previous version.
  # --------------------------------------------------------
  
  ggplot2::geom_text(
    data =
      label_inside,
    
    ggplot2::aes(
      label = gini_label
    ),
    
    colour =
      "black",
    
    size =
      3.2
  ) +
    
    
    # --------------------------------------------------------
  # COMOROS labels
  #
  # Place just above each small bubble.
  # --------------------------------------------------------
  
  ggplot2::geom_text(
    data =
      label_comoros,
    
    ggplot2::aes(
      label = gini_label
    ),
    
    colour =
      "black",
    
    size =
      3.2,
    
    nudge_y =
      0.27,
    
    vjust =
      0
  ) +
    
    
    # --------------------------------------------------------
  # Bubble size
  # --------------------------------------------------------
  
  ggplot2::scale_size_area(
    max_size = 22
  ) +
    
    
    # --------------------------------------------------------
  # Gini fill
  #
  # Fixed 0–1 scale for BOTH plots so colours mean the
  # same thing in the raw and normalised versions.
  # --------------------------------------------------------
  
  ggplot2::scale_fill_viridis_c(
    option = "E",
    direction = 1,
    limits = c(
      0,
      1
    ),
    breaks = c(
      0,
      0.25,
      0.50,
      0.75,
      1
    ),
    labels = c(
      "0.00",
      "0.25",
      "0.50",
      "0.75",
      "1.00"
    ),
    na.value =
      "grey94"
  ) +
    
    
    # --------------------------------------------------------
  # Add some extra space above Comoros so its labels
  # don't get clipped.
  # --------------------------------------------------------
  
  ggplot2::scale_y_discrete(
    expand =
      ggplot2::expansion(
        add = c(
          0.4,
          0.8
        )
      )
  ) +
    
    
    # --------------------------------------------------------
  # Legends
  # --------------------------------------------------------
  
  ggplot2::guides(
    
    size =
      "none",
    
    fill =
      ggplot2::guide_colourbar(
        title = NULL,
        direction = "horizontal",
        label.position = "bottom",
        
        barwidth =
          grid::unit(
            13,
            "cm"
          ),
        
        barheight =
          grid::unit(
            0.55,
            "cm"
          ),
        
        ticks =
          TRUE
      )
  ) +
    
    
    # --------------------------------------------------------
  # Labels
  # --------------------------------------------------------
  
  ggplot2::labs(
    title = plot_title,
    x = NULL,
    y = NULL
  ) +
    
    
    # --------------------------------------------------------
  # Theme
  # --------------------------------------------------------
  
  ggplot2::theme_minimal(
    base_size = 16
  ) +
    
    ggplot2::theme(
      
      # ------------------------------------------------------
      # Legend
      # ------------------------------------------------------
      
      legend.position =
        "top",
      
      legend.justification =
        "center",
      
      legend.margin =
        ggplot2::margin(
          b = 15
        ),
      
      
      # ------------------------------------------------------
      # Grid
      # ------------------------------------------------------
      
      panel.grid.minor =
        ggplot2::element_blank(),
      
      panel.grid.major =
        ggplot2::element_line(
          colour = "grey90",
          linewidth = 0.8
        ),
      
      
      # ------------------------------------------------------
      # Countries
      # ------------------------------------------------------
      
      axis.text.y =
        ggplot2::element_text(
          colour = "grey30",
          size = 15,
          margin =
            ggplot2::margin(
              r = 8
            )
        ),
      
      
      # ------------------------------------------------------
      # Habitats
      # ------------------------------------------------------
      
      axis.text.x =
        ggplot2::element_text(
          colour = "grey30",
          size = 15,
          margin =
            ggplot2::margin(
              t = 8
            )
        ),
      
      
      axis.ticks =
        ggplot2::element_blank(),
      
      
      # ------------------------------------------------------
      # Optional title
      # ------------------------------------------------------
      
      plot.title =
        ggplot2::element_text(
          size = 16,
          face = "bold",
          hjust = 0.5
        ),
      
      
      # ------------------------------------------------------
      # Outer spacing
      # ------------------------------------------------------
      
      plot.margin =
        ggplot2::margin(
          t = 10,
          r = 20,
          b = 10,
          l = 10
        )
    )
  
  
  return(p)
}


# ============================================================
# 9. RAW GINI PLOT
# ============================================================

gini_plot_raw <-
  make_gini_plot(
    data =
      gini_plot_data,
    
    gini_variable =
      "gini_raw",
    
    plot_title =
      NULL
  )


print(
  gini_plot_raw
)


# ============================================================
# 10. NORMALISED GINI PLOT
# ============================================================

gini_plot_normalised <-
  make_gini_plot(
    data =
      gini_plot_data,
    
    gini_variable =
      "gini_normalised",
    
    plot_title =
      NULL
  )


print(
  gini_plot_normalised
)


# ============================================================
# 11. SAVE RAW VERSION
# ============================================================

ggplot2::ggsave(
  filename =
    raw_plot_file,
  
  plot =
    gini_plot_raw,
  
  width =
    11,
  
  height =
    8,
  
  dpi =
    300,
  
  bg =
    "white"
)


# ============================================================
# 12. SAVE NORMALISED VERSION
# ============================================================

ggplot2::ggsave(
  filename =
    normalised_plot_file,
  
  plot =
    gini_plot_normalised,
  
  width =
    11,
  
  height =
    8,
  
  dpi =
    300,
  
  bg =
    "white"
)


# ============================================================
# 13. FINISHED
# ============================================================

message(
  "\nSaved Gini plots:\n",
  raw_plot_file,
  "\n",
  normalised_plot_file
)