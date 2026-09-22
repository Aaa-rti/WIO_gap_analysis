# ============================================================
# ELEMENT 2 — WIO ecological representativeness plots
# ============================================================

# 1. Packages -------------------------------------------------------------

library(dplyr)
library(tibble)
library(ggplot2)
library(readr)
library(scales)
library(patchwork)


# 2. Input / output --------------------------------------------------------

ELEMENT2_CSV <- file.path(
  "outputs",
  "element2",
  "element2_habitat_protection_by_sovereign.csv"
)

OUTPUT_DIR <- file.path(
  "outputs",
  "publication_plots",
  "element2"
)

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)


# 3. Figure settings -------------------------------------------------------

HABITAT_MAP <- c(
  "Mangroves" = "Mangroves",
  "Coral"      = "Coral",
  "Seagrass"   = "Seagrass",
  "Seamounts"  = "Seamounts"
)

EXCLUDED_STATES <- c("WIO", "Disputed")

COUNTRY_COLOURS <- c(
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

COUNTRY_CODES <- c(
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

BAR_WIDTH <- 0.92
X_SIDE_PADDING <- 0.6

LEGEND_TITLE <- "WIO Countries"
LEGEND_NROW <- 2
LEGEND_TOP_GAP_PT <- 30

PLOT1_Y_BREAKS <- seq(0, 1, by = 0.2)
PLOT2_Y_MAX <- 100
PLOT2_Y_BREAKS <- seq(0, PLOT2_Y_MAX, by = 20)

SINGLE_PLOT_WIDTH <- 8
SINGLE_PLOT_HEIGHT <- 6
COMBINED_WIDTH <- 14
COMBINED_HEIGHT <- 5
COMBINED_PANEL_GAP_REL <- 0.07
PLOT_DPI <- 400


# 4. Read and prepare data -------------------------------------------------

element2 <- read_csv(ELEMENT2_CSV, show_col_types = FALSE)

habitat_country <- element2 |>
  filter(
    !sovereign_state %in% EXCLUDED_STATES,
    measure_type == "area",
    indicator %in% names(HABITAT_MAP),
    !is.na(sovereign_state),
    !is.na(indicator_area_km2),
    indicator_area_km2 > 0
  ) |>
  group_by(indicator, sovereign_state) |>
  summarise(
    habitat_area_km2 = sum(indicator_area_km2, na.rm = TRUE),
    protected_habitat_area_km2 = sum(protected_indicator_area_km2, na.rm = TRUE),
    .groups = "drop"
  )

habitat_totals <- habitat_country |>
  group_by(indicator) |>
  summarise(
    wio_habitat_area_km2 = sum(habitat_area_km2, na.rm = TRUE),
    wio_protected_habitat_area_km2 =
      sum(protected_habitat_area_km2, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    wio_percent_protected =
      100 * wio_protected_habitat_area_km2 / wio_habitat_area_km2
  )

plot_data <- habitat_country |>
  left_join(habitat_totals, by = "indicator") |>
  mutate(
    habitat_share_percent =
      100 * habitat_area_km2 / wio_habitat_area_km2,
    protected_contribution_percent =
      100 * protected_habitat_area_km2 / wio_habitat_area_km2,
    habitat = factor(
      unname(HABITAT_MAP[indicator]),
      levels = unname(HABITAT_MAP)
    )
  )


# 5. Country ordering and legend ------------------------------------------

observed_countries <- unique(as.character(plot_data$sovereign_state))

country_levels <- c(
  intersect(names(COUNTRY_COLOURS), observed_countries),
  sort(setdiff(observed_countries, names(COUNTRY_COLOURS)))
)

# Generate fallback colours only if additional sovereign states occur.
missing_colours <- setdiff(country_levels, names(COUNTRY_COLOURS))

if (length(missing_colours) > 0) {
  COUNTRY_COLOURS <- c(
    COUNTRY_COLOURS,
    setNames(
      grDevices::hcl.colors(length(missing_colours), palette = "Dark 3"),
      missing_colours
    )
  )
}

country_colours <- COUNTRY_COLOURS[country_levels]

country_legend_labels <- setNames(
  ifelse(
    country_levels %in% names(COUNTRY_CODES),
    COUNTRY_CODES[country_levels],
    country_levels
  ),
  country_levels
)

plot_data <- plot_data |>
  mutate(
    sovereign_state = factor(
      sovereign_state,
      levels = country_levels
    )
  )


# 6. Save plotting data ----------------------------------------------------

write_csv(
  plot_data |>
    select(
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
    OUTPUT_DIR,
    "element2_stacked_barplot_data.csv"
  )
)

wio_summary <- habitat_totals |>
  mutate(
    habitat = factor(
      unname(HABITAT_MAP[indicator]),
      levels = unname(HABITAT_MAP)
    ),
    percent_protected = round(wio_percent_protected, 2)
  ) |>
  arrange(habitat) |>
  select(
    habitat,
    wio_habitat_area_km2,
    wio_protected_habitat_area_km2,
    percent_protected
  )

write_csv(
  wio_summary,
  file.path(
    OUTPUT_DIR,
    "element2_WIO_habitat_protection_summary.csv"
  )
)


# 7. Common plot theme -----------------------------------------------------

common_theme <- theme_minimal(base_size = 10) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),

    axis.text.x = element_text(
      size = 10,
      face = "bold",
      colour = "grey20",
      margin = margin(t = 3)
    ),

    axis.text.y = element_text(
      size = 10,
      colour = "grey20"
    ),

    axis.title.y = element_text(
      size = 13,
      margin = margin(r = 6)
    ),

    legend.position = "bottom",
    legend.justification = "center",
    legend.box.just = "center",
    legend.direction = "horizontal",
    legend.box.spacing = grid::unit(LEGEND_TOP_GAP_PT, "pt"),

    legend.title = element_text(
      face = "bold",
      size = 13
    ),

    legend.text = element_text(size = 10),
    legend.key.width = grid::unit(0.45, "cm"),
    legend.key.height = grid::unit(0.35, "cm"),
    legend.spacing.x = grid::unit(0.20, "cm"),

    plot.margin = margin(5, 5, 5, 5, unit = "pt")
  )

country_fill_scale <- scale_fill_manual(
  values = country_colours,
  breaks = country_levels,
  labels = country_legend_labels,
  drop = FALSE,
  name = LEGEND_TITLE,
  guide = guide_legend(
    nrow = LEGEND_NROW,
    byrow = TRUE,
    title.position = "left",
    title.hjust = 0.5
  )
)


# 8. Distribution of WIO habitat ------------------------------------------

plot_habitat_distribution <- ggplot(
  plot_data,
  aes(
    x = habitat,
    y = habitat_area_km2,
    fill = sovereign_state
  )
) +
  geom_col(
    position = "fill",
    width = BAR_WIDTH
  ) +
  scale_x_discrete(
    expand = expansion(add = X_SIDE_PADDING)
  ) +
  country_fill_scale +
  scale_y_continuous(
    breaks = PLOT1_Y_BREAKS,
    labels = label_percent(accuracy = 1),
    expand = expansion(mult = c(0, 0))
  ) +
  coord_cartesian(
    ylim = c(0, 1),
    clip = "off"
  ) +
  labs(
    x = NULL,
    y = "Proportion of habitat"
  ) +
  common_theme


# 9. Protected habitat -----------------------------------------------------

plot_habitat_protected <- ggplot(
  plot_data,
  aes(
    x = habitat,
    y = protected_contribution_percent,
    fill = sovereign_state
  )
) +
  geom_col(
    width = BAR_WIDTH
  ) +
  scale_x_discrete(
    expand = expansion(add = X_SIDE_PADDING)
  ) +
  country_fill_scale +
  scale_y_continuous(
    breaks = PLOT2_Y_BREAKS,
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0, 0.02))
  ) +
  coord_cartesian(
    ylim = c(0, PLOT2_Y_MAX),
    clip = "off"
  ) +
  labs(
    x = NULL,
    y = "Proportion of protected habitat"
  ) +
  common_theme


# 10. Save individual plots ------------------------------------------------

ggsave(
  file.path(
    OUTPUT_DIR,
    "element2_habitat_distribution_by_country_stacked_barplot.png"
  ),
  plot_habitat_distribution,
  width = SINGLE_PLOT_WIDTH,
  height = SINGLE_PLOT_HEIGHT,
  dpi = PLOT_DPI,
  bg = "white"
)

ggsave(
  file.path(
    OUTPUT_DIR,
    "element2_habitat_protected_by_country_stacked_barplot.png"
  ),
  plot_habitat_protected,
  width = SINGLE_PLOT_WIDTH,
  height = SINGLE_PLOT_HEIGHT,
  dpi = PLOT_DPI,
  bg = "white"
)


# 11. Combined figure ------------------------------------------------------

combined_plot <- (
  plot_habitat_distribution |
    plot_spacer() |
    plot_habitat_protected
) +
  plot_layout(
    widths = c(1, COMBINED_PANEL_GAP_REL, 1),
    guides = "collect"
  ) &
  theme(
    legend.position = "bottom",
    legend.justification = "center",
    legend.box.just = "center",
    legend.direction = "horizontal",
    legend.box.spacing = grid::unit(LEGEND_TOP_GAP_PT, "pt")
  )

ggsave(
  file.path(
    OUTPUT_DIR,
    "element2_habitat_distribution_and_protection_stacked_barplots.png"
  ),
  combined_plot,
  width = COMBINED_WIDTH,
  height = COMBINED_HEIGHT,
  dpi = PLOT_DPI,
  bg = "white"
)

print(combined_plot)
print(wio_summary)
