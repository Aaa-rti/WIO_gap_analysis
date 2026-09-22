# ============================================================
# ELEMENT 5 — Larval sources and sinks represented in protected areas
# ============================================================
#
# Analytical rules:
#   - Top larval sources = NetflowC5 > country-specific 75th percentile
#   - Top larval sinks   = NetflowC5 < country-specific 25th percentile
#   - Country results therefore use within-country thresholds.
#   - Regional WIO results use WIO-wide q75 / q25 thresholds.
#   - Each connectivity feature is represented by a point and buffered
#     by 4 km (8 km diameter) before testing overlap with protected areas.
#
# Outputs:
#   1. Country + WIO source/sink protection summary CSV
#   2. Country + WIO Netflow quantile thresholds CSV
#   3. Classified larval-connectivity cell CSV
#   4. GeoPackage containing classified cells, footprints, sources and sinks
# ============================================================


# 1. Packages -------------------------------------------------------------

library(sf)
library(dplyr)
library(tidyr)
library(tibble)
library(stringr)
library(readr)

sf_use_s2(FALSE)


# 2. Settings -------------------------------------------------------------

# Connectivity data
CONNECTIVITY_SHP <- file.path(
  "indicators",
  "Connectivity",
  "Connectivity.shp"
)

NETFLOW_FIELD <- "NetflowC5"

CELL_ID_CANDIDATES <- c(
  "ID_2",
  "Reef_ID",
  "ID",
  "reef_id",
  "cell_id"
)

SOURCE_QUANTILE <- 0.75
SINK_QUANTILE <- 0.25

CONNECTIVITY_BUFFER_KM <- 4

# Existing protection database
PROTECTION_GPKG <- file.path(
  "outputs",
  "wio_protected_area_spatial_database.gpkg"
)

EEZ_LAYER <- "eez_by_country"
PROTECTED_LAYER <- "protected_unique_by_country"
MPA_LAYER <- "mpa_unique_by_country"
OECM_LAYER <- "oecm_unique_by_country"

EXCLUDED_SOVEREIGN_STATES <- "Disputed"

# Outputs
OUTPUT_DIR <- file.path(
  "outputs",
  "element5",
  "larval_sources_sinks"
)

dir.create(
  OUTPUT_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)

OUTPUT_GPKG <- file.path(
  OUTPUT_DIR,
  "element5_larval_sources_sinks.gpkg"
)

if (file.exists(OUTPUT_GPKG)) {
  unlink(OUTPUT_GPKG)
}


# 3. Helper functions -----------------------------------------------------

normalise_name <- function(x) {
  x |>
    as.character() |>
    str_squish() |>
    str_to_lower()
}

exclude_sovereign_states <- function(x) {
  excluded <- normalise_name(EXCLUDED_SOVEREIGN_STATES)
  keep <- !normalise_name(x$sovereign_state) %in% excluded

  x[keep, , drop = FALSE]
}

make_valid_polygonal <- function(x) {

  if (nrow(x) == 0) {
    return(x)
  }

  x <- suppressWarnings(st_make_valid(x))
  x <- x[!st_is_empty(x), , drop = FALSE]

  if (nrow(x) == 0) {
    return(x)
  }

  geometry_type <- as.character(
    st_geometry_type(x, by_geometry = TRUE)
  )

  if (any(geometry_type %in% c("GEOMETRY", "GEOMETRYCOLLECTION"))) {
    x <- suppressWarnings(
      st_collection_extract(
        x,
        "POLYGON",
        warn = FALSE
      )
    )
  }

  x <- x[!st_is_empty(x), , drop = FALSE]

  if (nrow(x) == 0) {
    return(x)
  }

  geometry_type <- as.character(
    st_geometry_type(x, by_geometry = TRUE)
  )

  x[
    geometry_type %in% c("POLYGON", "MULTIPOLYGON"),
    ,
    drop = FALSE
  ]
}

resolve_field <- function(x, preferred, alternatives = character(0)) {

  candidates <- unique(c(preferred, alternatives))
  field_names <- names(x)
  field_names_lower <- tolower(field_names)

  for (candidate in candidates) {
    idx <- match(
      tolower(candidate),
      field_names_lower
    )

    if (!is.na(idx)) {
      return(field_names[[idx]])
    }
  }

  NA_character_
}

safe_percent <- function(num, den) {
  ifelse(
    is.finite(den) & den > 0,
    100 * num / den,
    NA_real_
  )
}

safe_quantile <- function(x, prob) {

  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x) & !is.na(x)]

  if (length(x) == 0) {
    return(NA_real_)
  }

  as.numeric(
    quantile(
      x,
      probs = prob,
      na.rm = TRUE,
      names = FALSE,
      type = 7
    )
  )
}

write_gpkg_layer <- function(x, layer) {

  if (nrow(x) == 0) {
    return(invisible(NULL))
  }

  st_write(
    x,
    dsn = OUTPUT_GPKG,
    layer = layer,
    append = FALSE,
    delete_layer = TRUE,
    quiet = TRUE
  )
}


# 4. Load EEZ and protection layers ---------------------------------------

zone_eez <- st_read(
  PROTECTION_GPKG,
  layer = EEZ_LAYER,
  quiet = TRUE
)

ANALYSIS_CRS <- st_crs(zone_eez)

zone_eez <- zone_eez |>
  exclude_sovereign_states() |>
  make_valid_polygonal() |>
  select(sovereign_state)

zone_protected <- st_read(
  PROTECTION_GPKG,
  layer = PROTECTED_LAYER,
  quiet = TRUE
) |>
  st_transform(ANALYSIS_CRS) |>
  make_valid_polygonal()

zone_mpa <- st_read(
  PROTECTION_GPKG,
  layer = MPA_LAYER,
  quiet = TRUE
) |>
  st_transform(ANALYSIS_CRS) |>
  make_valid_polygonal()

zone_oecm <- st_read(
  PROTECTION_GPKG,
  layer = OECM_LAYER,
  quiet = TRUE
) |>
  st_transform(ANALYSIS_CRS) |>
  make_valid_polygonal()


# 5. Load and standardise connectivity data -------------------------------

connectivity_raw <- st_read(
  CONNECTIVITY_SHP,
  quiet = TRUE
)

netflow_field <- resolve_field(
  connectivity_raw,
  preferred = NETFLOW_FIELD
)

id_field <- resolve_field(
  connectivity_raw,
  preferred = CELL_ID_CANDIDATES[[1]],
  alternatives = CELL_ID_CANDIDATES[-1]
)

connectivity_raw$source_cell_id <- if (!is.na(id_field)) {
  as.character(connectivity_raw[[id_field]])
} else {
  NA_character_
}

connectivity_raw$cell_id <- sprintf(
  "CELL%06d",
  seq_len(nrow(connectivity_raw))
)

connectivity_raw$netflow <- suppressWarnings(
  as.numeric(
    connectivity_raw[[netflow_field]]
  )
)

connectivity_proj <- connectivity_raw |>
  st_transform(ANALYSIS_CRS)


# 6. Represent each connectivity feature by a point -----------------------

geometry_type <- as.character(
  st_geometry_type(
    connectivity_proj,
    by_geometry = TRUE
  )
)

if (all(geometry_type %in% c("POINT", "MULTIPOINT"))) {

  connectivity_points <- connectivity_proj

  if (any(geometry_type == "MULTIPOINT")) {
    connectivity_points <- suppressWarnings(
      st_point_on_surface(connectivity_proj)
    )
  }

} else {

  connectivity_points <- suppressWarnings(
    st_point_on_surface(connectivity_proj)
  )
}


# 7. Assign connectivity cells to sovereign EEZs --------------------------

country_hits <- st_intersects(
  connectivity_points,
  zone_eez,
  sparse = TRUE
)

country_assignment <- vapply(
  country_hits,
  function(idx) {

    if (length(idx) == 0) {
      return(NA_character_)
    }

    as.character(
      zone_eez$sovereign_state[[idx[[1]]]]
    )
  },
  character(1)
)

connectivity_points$sovereign_state <- country_assignment

connectivity_points <- connectivity_points |>
  filter(
    !is.na(sovereign_state),
    !is.na(netflow),
    is.finite(netflow)
  )


# 8. Create 4-km-radius connectivity footprints ---------------------------

connectivity_footprints <- st_buffer(
  connectivity_points,
  dist = CONNECTIVITY_BUFFER_KM * 1000
)


# 9. Classify protection status -------------------------------------------

protected_flag <- lengths(
  st_intersects(
    connectivity_footprints,
    zone_protected,
    sparse = TRUE
  )
) > 0

mpa_flag <- lengths(
  st_intersects(
    connectivity_footprints,
    zone_mpa,
    sparse = TRUE
  )
) > 0

oecm_flag <- lengths(
  st_intersects(
    connectivity_footprints,
    zone_oecm,
    sparse = TRUE
  )
) > 0

protection_class <- case_when(
  mpa_flag & oecm_flag ~ "MPA-OECM overlap",
  mpa_flag             ~ "MPA only",
  oecm_flag            ~ "OECM only",
  protected_flag       ~ "Protected - uncategorised",
  TRUE                 ~ "Unprotected"
)

connectivity_points <- connectivity_points |>
  mutate(
    protected = protected_flag,
    in_mpa = mpa_flag,
    in_oecm = oecm_flag,
    protection_class = protection_class
  )

connectivity_footprints <- connectivity_footprints |>
  mutate(
    protected = protected_flag,
    in_mpa = mpa_flag,
    in_oecm = oecm_flag,
    protection_class = protection_class
  )


# 10. Calculate country-specific q25 / q75 thresholds ---------------------
#   sinks   = NetflowC5 < q25
#   sources = NetflowC5 > q75

country_thresholds <- connectivity_points |>
  st_drop_geometry() |>
  group_by(
    sovereign_state
  ) |>
  summarise(
    n_cells = n(),
    q25_netflow = safe_quantile(
      netflow,
      SINK_QUANTILE
    ),
    q75_netflow = safe_quantile(
      netflow,
      SOURCE_QUANTILE
    ),
    .groups = "drop"
  )

connectivity_points <- connectivity_points |>
  left_join(
    country_thresholds,
    by = "sovereign_state"
  ) |>
  mutate(
    is_country_sink = netflow < q25_netflow,
    is_country_source = netflow > q75_netflow
  )


# 11. Calculate WIO-wide q25 / q75 thresholds -----------------------------

wio_q25 <- safe_quantile(
  connectivity_points$netflow,
  SINK_QUANTILE
)

wio_q75 <- safe_quantile(
  connectivity_points$netflow,
  SOURCE_QUANTILE
)

connectivity_points <- connectivity_points |>
  mutate(
    is_wio_sink = netflow < wio_q25,
    is_wio_source = netflow > wio_q75
  )

# Copy the point-level classification fields to the buffered footprints.
footprint_geometry <- st_geometry(
  connectivity_footprints
)

footprint_attributes <- connectivity_points |>
  st_drop_geometry()

connectivity_footprints <- st_sf(
  footprint_attributes,
  geometry = footprint_geometry,
  crs = ANALYSIS_CRS
)


# 12. Save classified spatial outputs -------------------------------------

write_gpkg_layer(
  connectivity_points,
  "larval_connectivity_cells"
)

write_gpkg_layer(
  connectivity_footprints,
  "larval_connectivity_4km_footprints"
)

write_gpkg_layer(
  connectivity_points |>
    filter(is_country_source),
  "country_q75_larval_sources"
)

write_gpkg_layer(
  connectivity_points |>
    filter(is_country_sink),
  "country_q25_larval_sinks"
)

write_gpkg_layer(
  connectivity_points |>
    filter(is_wio_source),
  "wio_q75_larval_sources"
)

write_gpkg_layer(
  connectivity_points |>
    filter(is_wio_sink),
  "wio_q25_larval_sinks"
)


# 13. Summarise protection of selected cells ------------------------------

summarise_selection <- function(
    dat,
    selected_col,
    indicator,
    sovereign_name) {

  selected <- dat[
    dat[[selected_col]] %in% TRUE,
    ,
    drop = FALSE
  ]

  n_selected <- nrow(selected)
  n_protected <- sum(selected$protected, na.rm = TRUE)
  n_mpa <- sum(selected$in_mpa, na.rm = TRUE)
  n_oecm <- sum(selected$in_oecm, na.rm = TRUE)
  n_overlap <- sum(
    selected$in_mpa & selected$in_oecm,
    na.rm = TRUE
  )

  tibble(
    sovereign_state = sovereign_name,
    indicator = indicator,
    n_selected_cells = n_selected,
    n_protected_cells = n_protected,
    n_mpa_cells = n_mpa,
    n_oecm_cells = n_oecm,
    n_mpa_oecm_overlap_cells = n_overlap,
    percent_protected_total = safe_percent(
      n_protected,
      n_selected
    ),
    percent_in_mpa = safe_percent(
      n_mpa,
      n_selected
    ),
    percent_in_oecm = safe_percent(
      n_oecm,
      n_selected
    ),
    percent_in_mpa_oecm_overlap = safe_percent(
      n_overlap,
      n_selected
    )
  )
}


# Country summaries use within-country source/sink classifications.
country_names <- sort(
  unique(
    connectivity_points$sovereign_state
  )
)

country_summary <- lapply(
  country_names,
  function(country) {

    country_data <- connectivity_points |>
      st_drop_geometry() |>
      filter(
        sovereign_state == country
      )

    bind_rows(
      summarise_selection(
        dat = country_data,
        selected_col = "is_country_source",
        indicator = "Top larval sources",
        sovereign_name = country
      ),
      summarise_selection(
        dat = country_data,
        selected_col = "is_country_sink",
        indicator = "Top larval sinks",
        sovereign_name = country
      )
    )
  }
) |>
  bind_rows()


# WIO summaries use the regional WIO thresholds.
wio_data <- connectivity_points |>
  st_drop_geometry()

wio_summary <- bind_rows(
  summarise_selection(
    dat = wio_data,
    selected_col = "is_wio_source",
    indicator = "Top larval sources",
    sovereign_name = "WIO"
  ),
  summarise_selection(
    dat = wio_data,
    selected_col = "is_wio_sink",
    indicator = "Top larval sinks",
    sovereign_name = "WIO"
  )
)

indicator_summary <- bind_rows(
  country_summary,
  wio_summary
) |>
  arrange(
    sovereign_state,
    indicator
  )


# 14. Save tabular outputs -------------------------------------------------

write_csv(
  indicator_summary,
  file.path(
    OUTPUT_DIR,
    "element5_larval_sources_sinks_protection_by_sovereign.csv"
  )
)

threshold_output <- bind_rows(
  country_thresholds |>
    mutate(
      threshold_scope = "country-specific"
    ),
  tibble(
    sovereign_state = "WIO",
    n_cells = nrow(connectivity_points),
    q25_netflow = wio_q25,
    q75_netflow = wio_q75,
    threshold_scope = "WIO-wide"
  )
)

write_csv(
  threshold_output,
  file.path(
    OUTPUT_DIR,
    "element5_netflow_quantile_thresholds.csv"
  )
)

write_csv(
  connectivity_points |>
    st_drop_geometry(),
  file.path(
    OUTPUT_DIR,
    "element5_larval_connectivity_cells_classified.csv"
  )
)


# 15. Complete -------------------------------------------------------------

message(
  "Element 5 analysis complete. Outputs written to: ",
  normalizePath(OUTPUT_DIR)
)
