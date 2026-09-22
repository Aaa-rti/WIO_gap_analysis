# ============================================================
# ELEMENT 5
# LARVAL SOURCES AND SINKS REPRESENTED IN PROTECTED AREAS
#
# Historical method reproduced from the previous WIO workflow:
#
#   Top larval sources = NetflowC5 > country-specific 75th percentile
#   Top larval sinks   = NetflowC5 < country-specific 25th percentile
#
# Country results therefore use WITHIN-COUNTRY thresholds.
# Regional WIO results use WIO-wide q75 / q25 thresholds, matching
# the old code.
#
# Protection is assessed using the existing WIO protection GeoPackage.
# To reproduce the historical reef-cell treatment, each connectivity
# feature is represented by a point and buffered by 4 km (8 km diameter)
# before testing intersection with protected areas.
#
# Outputs:
#   1. Country + WIO summary CSV
#   2. Country + WIO quantile thresholds CSV
#   3. GeoPackage of classified larval-connectivity cells / footprints
#   4. Standalone circular country plot
#   5. Combined figure:
#        top-left    = WIO overall % protected bar plot
#        bottom-left = indicator legend
#        right       = circular country plot
# ============================================================

rm(list = ls())


# ============================================================
# 1. PACKAGES
# ============================================================

pkgs <- c(
  "sf",
  "dplyr",
  "tidyr",
  "tibble",
  "stringr",
  "ggplot2",
  "readr",
  "patchwork"
)

missing_pkgs <- pkgs[
  !vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)
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

sf::sf_use_s2(FALSE)


# ============================================================
# 2. USER SETTINGS
# ============================================================

# ------------------------------------------------------------
# 2a. Connectivity shapefile
# ------------------------------------------------------------
# EDIT THIS PATH if your Connectivity.shp is stored elsewhere.

CONNECTIVITY_SHP <- file.path(
  "indicators",
  "Connectivity",
  "Connectivity.shp"
)

# Historical connectivity metric used to classify sources / sinks.
NETFLOW_FIELD <- "NetflowC5"

# Candidate ID fields. The first one found is retained as source_cell_id.
CELL_ID_CANDIDATES <- c(
  "ID_2",
  "Reef_ID",
  "ID",
  "reef_id",
  "cell_id"
)

# Historical source / sink thresholds.
SOURCE_QUANTILE <- 0.75
SINK_QUANTILE   <- 0.25

# Historical reef-cell footprint: 4-km radius = ~8-km diameter.
CONNECTIVITY_BUFFER_KM <- 4


# ------------------------------------------------------------
# 2b. Existing protection GeoPackage
# ------------------------------------------------------------

PROTECTION_GPKG <- file.path(
  "outputs",
  "wio_protected_area_spatial_database.gpkg"
)

EEZ_LAYER       <- "eez_by_country"
PROTECTED_LAYER <- "protected_unique_by_country"
MPA_LAYER       <- "mpa_unique_by_country"
OECM_LAYER      <- "oecm_unique_by_country"

EXCLUDED_SOVEREIGN_STATES <- c(
  "Disputed"
)


# ------------------------------------------------------------
# 2c. Output folders
# ------------------------------------------------------------

OUTPUT_DIR <- file.path(
  "outputs",
  "element5",
  "larval_sources_sinks"
)

PLOT_DIR <- file.path(
  OUTPUT_DIR,
  "plots"
)

dir.create(
  OUTPUT_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  PLOT_DIR,
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


# ============================================================
# 3. PLOTTING SETTINGS
# ============================================================

# Countries are appended automatically if present in the data but not
# explicitly listed here.
COUNTRY_ORDER <- c(
  "Comoro Islands",
  "Comoros",
  "France",
  "Kenya",
  "Madagascar",
  "Mauritius",
  "Mozambique",
  "Seychelles",
  "Somalia",
  "South Africa",
  "Tanzania"
)

COUNTRY_CODES <- c(
  "Comoro Islands" = "COM",
  "Comoros"        = "COM",
  "France"         = "FRA",
  "Kenya"          = "KEN",
  "Madagascar"     = "MDG",
  "Mauritius"      = "MUS",
  "Mozambique"     = "MOZ",
  "Seychelles"     = "SYC",
  "Somalia"        = "SOM",
  "South Africa"   = "ZAF",
  "Tanzania"       = "TZA"
)

# Set this to countries you want excluded from plots only.
# Their analytical results remain in the CSV.
PLOT_DROP_COUNTRIES <- character(0)

INDICATOR_ORDER <- c(
  "Top larval sources",
  "Top larval sinks"
)

INDICATOR_LABELS <- c(
  "Top larval sources" = "Top larval sources",
  "Top larval sinks"   = "Top larval sinks"
)

INDICATOR_COLOURS_USER <- c(
  "Top larval sources" = "#4388AE",
  "Top larval sinks"   = "#50BEAE"
)

# Circular plot spacing.
EMPTY_BARS <- 3
BAR_WIDTH  <- 0.78

POLAR_START_DEG <- 0
POLAR_DIRECTION <- 1

RADIAL_BREAKS <- c(
  20,
  40,
  60,
  80,
  100
)

RING_COLOURS <- c(
  "#D5D8D9",
  "#DEE0E1",
  "#D5D8D9",
  "#DEE0E1",
  "#ECEDED"
)

INNER_YMIN <- -52
INNER_YMAX <- 0
INNER_FILL <- "#E7E7E7"

COUNTRY_ARC_YMIN   <- -4.4
COUNTRY_ARC_YMAX   <- -3.1
COUNTRY_ARC_COLOUR <- "#303030"

COUNTRY_LABEL_Y      <- -14
COUNTRY_LABEL_SIZE   <- 4.1
COUNTRY_LABEL_COLOUR <- "#333333"

SCALE_LABEL_SIZE     <- 3.2
SCALE_LABEL_X_NUDGE  <- 0
SCALE_LABEL_COLOUR   <- "#111111"

LEGEND_TITLE <- "Element 5 indicators"

CIRCULAR_FIGURE_WIDTH  <- 11
CIRCULAR_FIGURE_HEIGHT <- 11

# WIO summary plot.
WIO_SUMMARY_TITLE <- "Total % protected in WIO"
WIO_X_MAX         <- 100
WIO_X_BREAKS      <- seq(0, 100, by = 20)

# Keep the WIO summary bars visually consistent with the other
# Element plots that contain five indicators.
#
# The bar width itself stays fixed at 0.72. When fewer than five
# indicators are present, the WIO plot uses a five-slot vertical
# layout so BOTH bar thickness and spacing remain consistent.
WIO_REFERENCE_N_INDICATORS <- 5
WIO_BAR_WIDTH               <- 0.72

# Combined figure dimensions / layout.
COMBINED_LEFT_RIGHT_WIDTHS <- c(1, 1)
COMBINED_TOP_BOTTOM_HEIGHTS <- c(1.20, 0.80)

COMBINED_FIGURE_WIDTH  <- 16
COMBINED_FIGURE_HEIGHT <- 10

COMBINED_LEGEND_TITLE_SIZE <- 14
COMBINED_LEGEND_TEXT_SIZE  <- 4.8
COMBINED_LEGEND_KEY_SIZE   <- 9
COMBINED_LEGEND_KEY_X      <- 0.035
COMBINED_LEGEND_TEXT_X     <- 0.095


# ============================================================
# 4. HELPERS
# ============================================================

append_unlisted_levels <- function(preferred, observed) {
  c(
    intersect(preferred, observed),
    setdiff(observed, preferred)
  )
}


country_code <- function(country) {
  code <- unname(COUNTRY_CODES[country])
  
  missing_code <- is.na(code) | !nzchar(code)
  
  if (any(missing_code)) {
    code[missing_code] <- stringr::str_to_upper(
      stringr::str_sub(
        country[missing_code],
        1,
        3
      )
    )
  }
  
  code
}


complete_indicator_colours <- function(indicators) {
  indicators <- unique(as.character(indicators))
  
  supplied <- INDICATOR_COLOURS_USER[
    intersect(
      indicators,
      names(INDICATOR_COLOURS_USER)
    )
  ]
  
  missing_indicators <- setdiff(
    indicators,
    names(supplied)
  )
  
  if (length(missing_indicators) > 0) {
    fallback <- stats::setNames(
      grDevices::hcl.colors(
        n = length(missing_indicators),
        palette = "Dark 3"
      ),
      missing_indicators
    )
    
    supplied <- c(
      supplied,
      fallback
    )
  }
  
  supplied[indicators]
}


complete_indicator_labels <- function(indicators) {
  indicators <- unique(as.character(indicators))
  
  labels <- unname(
    INDICATOR_LABELS[indicators]
  )
  
  missing_labels <- is.na(labels) | !nzchar(labels)
  labels[missing_labels] <- indicators[missing_labels]
  
  stats::setNames(
    labels,
    indicators
  )
}


normalise_name <- function(x) {
  x |>
    as.character() |>
    stringr::str_squish() |>
    stringr::str_to_lower()
}


exclude_sovereign_states <- function(x) {
  if (!("sovereign_state" %in% names(x))) {
    stop(
      "Expected a 'sovereign_state' column but it was not found."
    )
  }
  
  excluded_norm <- normalise_name(
    EXCLUDED_SOVEREIGN_STATES
  )
  
  keep <- !normalise_name(
    x$sovereign_state
  ) %in% excluded_norm
  
  x[keep, , drop = FALSE]
}


read_required_gpkg_layer <- function(gpkg, layer) {
  if (!file.exists(gpkg)) {
    stop(
      "Protection GeoPackage not found:\n",
      gpkg
    )
  }
  
  available_layers <- sf::st_layers(gpkg)$name
  
  if (!(layer %in% available_layers)) {
    stop(
      "Required layer not found: ",
      layer,
      "\nAvailable layers:\n",
      paste(available_layers, collapse = "\n")
    )
  }
  
  sf::st_read(
    gpkg,
    layer = layer,
    quiet = FALSE
  )
}


make_valid_polygonal <- function(x) {
  if (nrow(x) == 0) {
    return(x)
  }
  
  x <- suppressWarnings(
    sf::st_make_valid(x)
  )
  
  x <- x[
    !sf::st_is_empty(x),
    ,
    drop = FALSE
  ]
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  geom_types <- as.character(
    sf::st_geometry_type(
      x,
      by_geometry = TRUE
    )
  )
  
  if (any(geom_types %in% c("GEOMETRY", "GEOMETRYCOLLECTION"))) {
    x <- suppressWarnings(
      sf::st_collection_extract(
        x,
        "POLYGON",
        warn = FALSE
      )
    )
  }
  
  x <- x[
    !sf::st_is_empty(x),
    ,
    drop = FALSE
  ]
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  geom_types <- as.character(
    sf::st_geometry_type(
      x,
      by_geometry = TRUE
    )
  )
  
  x[
    geom_types %in% c("POLYGON", "MULTIPOLYGON"),
    ,
    drop = FALSE
  ]
}


resolve_field <- function(x, preferred, alternatives = character(0)) {
  candidates <- unique(
    c(
      preferred,
      alternatives
    )
  )
  
  nm <- names(x)
  nm_lower <- tolower(nm)
  
  for (candidate in candidates) {
    idx <- match(
      tolower(candidate),
      nm_lower
    )
    
    if (!is.na(idx)) {
      return(nm[[idx]])
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
  x <- suppressWarnings(
    as.numeric(x)
  )
  
  x <- x[
    is.finite(x) & !is.na(x)
  ]
  
  if (length(x) == 0) {
    return(NA_real_)
  }
  
  as.numeric(
    stats::quantile(
      x,
      probs = prob,
      na.rm = TRUE,
      names = FALSE,
      type = 7
    )
  )
}


write_gpkg_layer <- function(x, dsn, layer) {
  if (nrow(x) == 0) {
    warning(
      "Skipping empty GeoPackage layer: ",
      layer
    )
    return(invisible(NULL))
  }
  
  sf::st_write(
    x,
    dsn = dsn,
    layer = layer,
    append = FALSE,
    delete_layer = TRUE,
    quiet = TRUE
  )
}


# ============================================================
# 5. LOAD PREVIOUS EEZ / PROTECTION LAYERS
# ============================================================

zone_eez <- read_required_gpkg_layer(
  PROTECTION_GPKG,
  EEZ_LAYER
)

if (!("sovereign_state" %in% names(zone_eez))) {
  stop(
    "The EEZ layer must contain a 'sovereign_state' field."
  )
}

if (is.na(sf::st_crs(zone_eez))) {
  stop(
    "The EEZ layer has no CRS."
  )
}

ANALYSIS_CRS <- sf::st_crs(zone_eez)

zone_eez <- zone_eez |>
  exclude_sovereign_states() |>
  make_valid_polygonal() |>
  dplyr::select(
    sovereign_state
  )

zone_protected <- read_required_gpkg_layer(
  PROTECTION_GPKG,
  PROTECTED_LAYER
) |>
  sf::st_transform(ANALYSIS_CRS) |>
  make_valid_polygonal()

zone_mpa <- read_required_gpkg_layer(
  PROTECTION_GPKG,
  MPA_LAYER
) |>
  sf::st_transform(ANALYSIS_CRS) |>
  make_valid_polygonal()

zone_oecm <- read_required_gpkg_layer(
  PROTECTION_GPKG,
  OECM_LAYER
) |>
  sf::st_transform(ANALYSIS_CRS) |>
  make_valid_polygonal()


# ============================================================
# 6. LOAD CONNECTIVITY SHAPEFILE
# ============================================================

if (!file.exists(CONNECTIVITY_SHP)) {
  stop(
    "Connectivity shapefile not found:\n",
    CONNECTIVITY_SHP,
    "\n\nEdit CONNECTIVITY_SHP in Section 2a."
  )
}

connectivity_raw <- sf::st_read(
  CONNECTIVITY_SHP,
  quiet = FALSE
)

if (is.na(sf::st_crs(connectivity_raw))) {
  stop(
    "Connectivity.shp has no CRS. Assign the correct CRS before running this workflow."
  )
}

netflow_field_resolved <- resolve_field(
  connectivity_raw,
  preferred = NETFLOW_FIELD
)

if (is.na(netflow_field_resolved)) {
  stop(
    "Could not find the Netflow field '",
    NETFLOW_FIELD,
    "' in Connectivity.shp.\nAvailable fields:\n",
    paste(names(connectivity_raw), collapse = "\n")
  )
}

id_field_resolved <- resolve_field(
  connectivity_raw,
  preferred = CELL_ID_CANDIDATES[[1]],
  alternatives = CELL_ID_CANDIDATES[-1]
)

connectivity_raw$source_cell_id <- if (!is.na(id_field_resolved)) {
  as.character(
    connectivity_raw[[id_field_resolved]]
  )
} else {
  NA_character_
}

connectivity_raw$cell_id <- sprintf(
  "CELL%06d",
  seq_len(nrow(connectivity_raw))
)

connectivity_raw$netflow <- suppressWarnings(
  as.numeric(
    connectivity_raw[[netflow_field_resolved]]
  )
)

n_missing_netflow <- sum(
  is.na(connectivity_raw$netflow)
)

message(
  "\nConnectivity features read: ",
  nrow(connectivity_raw)
)

message(
  "Netflow field used: ",
  netflow_field_resolved
)

message(
  "Connectivity features with missing NetflowC5: ",
  n_missing_netflow
)

connectivity_proj <- connectivity_raw |>
  sf::st_transform(ANALYSIS_CRS)


# ============================================================
# 7. REPRESENT EACH CONNECTIVITY FEATURE BY A POINT
# ============================================================
#
# Country assignment is based on the feature location itself.
# Protection is tested on a 4-km-radius footprint around this point,
# reproducing the historical ~8-km reef-cell treatment.
# ============================================================

geom_types <- as.character(
  sf::st_geometry_type(
    connectivity_proj,
    by_geometry = TRUE
  )
)

if (all(geom_types %in% c("POINT", "MULTIPOINT"))) {
  connectivity_points <- connectivity_proj
  
  if (any(geom_types == "MULTIPOINT")) {
    connectivity_points <- suppressWarnings(
      sf::st_point_on_surface(connectivity_proj)
    )
  }
  
} else {
  connectivity_points <- suppressWarnings(
    sf::st_point_on_surface(connectivity_proj)
  )
}


# ============================================================
# 8. ASSIGN EACH CONNECTIVITY CELL TO A SOVEREIGN EEZ
# ============================================================

country_hits <- sf::st_intersects(
  connectivity_points,
  zone_eez,
  sparse = TRUE
)

n_country_hits <- lengths(country_hits)

if (any(n_country_hits > 1)) {
  warning(
    sum(n_country_hits > 1),
    " connectivity feature(s) intersect more than one sovereign EEZ at the representative point. ",
    "The first matching EEZ is used; inspect these boundary cases if needed."
  )
}

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

n_outside_eez <- sum(
  is.na(connectivity_points$sovereign_state)
)

if (n_outside_eez > 0) {
  message(
    "Connectivity features outside retained WIO sovereign EEZs and removed: ",
    n_outside_eez
  )
}

connectivity_points <- connectivity_points |>
  dplyr::filter(
    !is.na(sovereign_state),
    !is.na(netflow),
    is.finite(netflow)
  )

if (nrow(connectivity_points) == 0) {
  stop(
    "No connectivity features remain after EEZ assignment and removal of missing NetflowC5 values."
  )
}


# ============================================================
# 9. CREATE 4-km-RADIUS REEF-CELL FOOTPRINTS
# ============================================================

connectivity_footprints <- sf::st_buffer(
  connectivity_points,
  dist = CONNECTIVITY_BUFFER_KM * 1000
)


# ============================================================
# 10. CLASSIFY PROTECTION STATUS
# ============================================================
#
# Faithful to the old count-based workflow:
# a reef cell is considered protected if its 4-km-radius footprint
# intersects the protected-area layer at all.
#
# This is an ANY-OVERLAP rule, not an area-weighted calculation.
# ============================================================

protected_flag <- lengths(
  sf::st_intersects(
    connectivity_footprints,
    zone_protected,
    sparse = TRUE
  )
) > 0

mpa_flag <- lengths(
  sf::st_intersects(
    connectivity_footprints,
    zone_mpa,
    sparse = TRUE
  )
) > 0

oecm_flag <- lengths(
  sf::st_intersects(
    connectivity_footprints,
    zone_oecm,
    sparse = TRUE
  )
) > 0

protection_union_flag <- mpa_flag | oecm_flag

if (any(protected_flag != protection_union_flag)) {
  warning(
    sum(protected_flag != protection_union_flag),
    " reef-cell footprint(s) differ between protected_unique_by_country and the union of MPA/OECM flags. ",
    "The main protected result uses protected_unique_by_country."
  )
}

protection_class <- dplyr::case_when(
  mpa_flag & oecm_flag ~ "MPA-OECM overlap",
  mpa_flag             ~ "MPA only",
  oecm_flag            ~ "OECM only",
  protected_flag       ~ "Protected - uncategorised",
  TRUE                 ~ "Unprotected"
)

connectivity_points$protected <- protected_flag
connectivity_points$in_mpa    <- mpa_flag
connectivity_points$in_oecm   <- oecm_flag
connectivity_points$protection_class <- protection_class

connectivity_footprints$protected <- protected_flag
connectivity_footprints$in_mpa    <- mpa_flag
connectivity_footprints$in_oecm   <- oecm_flag
connectivity_footprints$protection_class <- protection_class


# ============================================================
# 11. COUNTRY-SPECIFIC q25 / q75 THRESHOLDS
# ============================================================
#
# IMPORTANT: strict inequalities reproduce the old code:
#
#   sinks   = NetflowC5 < q25
#   sources = NetflowC5 > q75
#
# NOT <= and >=.
# ============================================================

country_thresholds <- connectivity_points |>
  sf::st_drop_geometry() |>
  dplyr::group_by(
    sovereign_state
  ) |>
  dplyr::summarise(
    n_cells = dplyr::n(),
    q25_netflow = safe_quantile(netflow, SINK_QUANTILE),
    q75_netflow = safe_quantile(netflow, SOURCE_QUANTILE),
    .groups = "drop"
  )

connectivity_points <- connectivity_points |>
  dplyr::left_join(
    country_thresholds,
    by = "sovereign_state"
  ) |>
  dplyr::mutate(
    is_country_sink = netflow < q25_netflow,
    is_country_source = netflow > q75_netflow
  )


# ============================================================
# 12. WIO-WIDE q25 / q75 THRESHOLDS
# ============================================================
#
# These are used ONLY for the regional WIO bars, matching the old code.
# ============================================================

wio_q25 <- safe_quantile(
  connectivity_points$netflow,
  SINK_QUANTILE
)

wio_q75 <- safe_quantile(
  connectivity_points$netflow,
  SOURCE_QUANTILE
)

connectivity_points$is_wio_sink <- connectivity_points$netflow < wio_q25
connectivity_points$is_wio_source <- connectivity_points$netflow > wio_q75

# Attach all classification fields to footprints in the same row order.
# Rebuild the sf object explicitly rather than relying on bind_cols()
# to preserve the active geometry column/class.
footprint_geometry <- sf::st_geometry(
  connectivity_footprints
)

footprint_attributes <- connectivity_points |>
  sf::st_drop_geometry()

connectivity_footprints <- sf::st_sf(
  footprint_attributes,
  geometry = footprint_geometry,
  crs = ANALYSIS_CRS
)


# ============================================================
# 13. SAVE CLASSIFIED SPATIAL PRODUCTS
# ============================================================

write_gpkg_layer(
  connectivity_points,
  OUTPUT_GPKG,
  "larval_connectivity_cells"
)

write_gpkg_layer(
  connectivity_footprints,
  OUTPUT_GPKG,
  "larval_connectivity_4km_footprints"
)

write_gpkg_layer(
  connectivity_points |>
    dplyr::filter(is_country_source),
  OUTPUT_GPKG,
  "country_q75_larval_sources"
)

write_gpkg_layer(
  connectivity_points |>
    dplyr::filter(is_country_sink),
  OUTPUT_GPKG,
  "country_q25_larval_sinks"
)

write_gpkg_layer(
  connectivity_points |>
    dplyr::filter(is_wio_source),
  OUTPUT_GPKG,
  "wio_q75_larval_sources"
)

write_gpkg_layer(
  connectivity_points |>
    dplyr::filter(is_wio_sink),
  OUTPUT_GPKG,
  "wio_q25_larval_sinks"
)


# ============================================================
# 14. SUMMARISE PROTECTION OF SELECTED CELLS
# ============================================================

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
  
  tibble::tibble(
    sovereign_state = sovereign_name,
    indicator = indicator,
    n_selected_cells = n_selected,
    n_protected_cells = n_protected,
    n_mpa_cells = n_mpa,
    n_oecm_cells = n_oecm,
    n_mpa_oecm_overlap_cells = n_overlap,
    percent_protected_total = safe_percent(n_protected, n_selected),
    percent_in_mpa = safe_percent(n_mpa, n_selected),
    percent_in_oecm = safe_percent(n_oecm, n_selected),
    percent_in_mpa_oecm_overlap = safe_percent(n_overlap, n_selected)
  )
}


country_names <- sort(
  unique(
    connectivity_points$sovereign_state
  )
)

country_summary_list <- vector(
  "list",
  length(country_names) * 2
)

k <- 1

for (country in country_names) {
  country_dat <- connectivity_points |>
    sf::st_drop_geometry() |>
    dplyr::filter(
      sovereign_state == country
    )
  
  country_summary_list[[k]] <- summarise_selection(
    dat = country_dat,
    selected_col = "is_country_source",
    indicator = "Top larval sources",
    sovereign_name = country
  )
  
  k <- k + 1
  
  country_summary_list[[k]] <- summarise_selection(
    dat = country_dat,
    selected_col = "is_country_sink",
    indicator = "Top larval sinks",
    sovereign_name = country
  )
  
  k <- k + 1
}

country_summary <- dplyr::bind_rows(
  country_summary_list
)

wio_dat <- connectivity_points |>
  sf::st_drop_geometry()

wio_summary <- dplyr::bind_rows(
  summarise_selection(
    dat = wio_dat,
    selected_col = "is_wio_source",
    indicator = "Top larval sources",
    sovereign_name = "WIO"
  ),
  summarise_selection(
    dat = wio_dat,
    selected_col = "is_wio_sink",
    indicator = "Top larval sinks",
    sovereign_name = "WIO"
  )
)

indicator_summary <- dplyr::bind_rows(
  country_summary,
  wio_summary
) |>
  dplyr::arrange(
    sovereign_state,
    indicator
  )


# ============================================================
# 15. SAVE SUMMARY / THRESHOLD CSVs
# ============================================================

readr::write_csv(
  indicator_summary,
  file.path(
    OUTPUT_DIR,
    "element5_larval_sources_sinks_protection_by_sovereign.csv"
  )
)

threshold_output <- dplyr::bind_rows(
  country_thresholds |>
    dplyr::mutate(
      threshold_scope = "country-specific"
    ),
  tibble::tibble(
    sovereign_state = "WIO",
    n_cells = nrow(connectivity_points),
    q25_netflow = wio_q25,
    q75_netflow = wio_q75,
    threshold_scope = "WIO-wide"
  )
)

readr::write_csv(
  threshold_output,
  file.path(
    OUTPUT_DIR,
    "element5_netflow_quantile_thresholds.csv"
  )
)

readr::write_csv(
  connectivity_points |>
    sf::st_drop_geometry(),
  file.path(
    OUTPUT_DIR,
    "element5_larval_connectivity_cells_classified.csv"
  )
)


# ============================================================
# 16. QA MESSAGES
# ============================================================

message(
  "\nCountry-specific source/sink thresholds:"
)

print(
  country_thresholds,
  n = Inf
)

message(
  "\nWIO-wide NetflowC5 q25: ",
  signif(wio_q25, 6)
)

message(
  "WIO-wide NetflowC5 q75: ",
  signif(wio_q75, 6)
)

message(
  "\nWIO protection results:"
)


print(
  wio_summary,
  n = Inf
)


# ============================================================
# 17. PREPARE PLOTTING DATA
# ============================================================

observed_indicators <- unique(
  indicator_summary$indicator[
    !is.na(indicator_summary$indicator)
  ]
)

preferred_indicator_levels <- append_unlisted_levels(
  preferred = INDICATOR_ORDER,
  observed = observed_indicators
)

# Same behaviour as the earlier circular plot:
# order indicators from least -> most protected at the WIO level.
wio_indicator_rank <- indicator_summary |>
  dplyr::filter(
    sovereign_state == "WIO",
    indicator %in% observed_indicators
  ) |>
  dplyr::mutate(
    value = suppressWarnings(
      as.numeric(percent_protected_total)
    ),
    preferred_rank = match(
      indicator,
      preferred_indicator_levels
    )
  ) |>
  dplyr::filter(
    !is.na(value)
  ) |>
  dplyr::arrange(
    value,
    preferred_rank
  )

if (nrow(wio_indicator_rank) > 0) {
  ranked_indicators <- wio_indicator_rank$indicator
  
  indicator_levels <- c(
    ranked_indicators,
    setdiff(
      preferred_indicator_levels,
      ranked_indicators
    )
  )
} else {
  indicator_levels <- preferred_indicator_levels
}

message(
  "\nIndicator order from LEAST to MOST protected in WIO:\n",
  paste(indicator_levels, collapse = " -> ")
)

country_data <- indicator_summary |>
  dplyr::filter(
    !sovereign_state %in% c(
      "WIO",
      "Disputed",
      PLOT_DROP_COUNTRIES
    )
  ) |>
  dplyr::mutate(
    value = suppressWarnings(
      as.numeric(percent_protected_total)
    )
  ) |>
  dplyr::filter(
    !is.na(value)
  ) |>
  dplyr::mutate(
    value = pmin(
      pmax(value, 0),
      100
    )
  ) |>
  dplyr::group_by(
    sovereign_state,
    indicator
  ) |>
  dplyr::summarise(
    value = dplyr::first(value),
    .groups = "drop"
  )

if (nrow(country_data) == 0) {
  stop(
    "No country-level Element 5 values remain for plotting."
  )
}

observed_countries <- unique(
  country_data$sovereign_state
)

country_levels <- append_unlisted_levels(
  preferred = COUNTRY_ORDER,
  observed = observed_countries
)


# ============================================================
# 18. CONSTRUCT CIRCULAR BAR LAYOUT
# ============================================================

layout_parts <- vector(
  "list",
  length(country_levels)
)

for (i in seq_along(country_levels)) {
  this_country <- country_levels[[i]]
  
  actual_slots <- tibble::tibble(
    sovereign_state = this_country,
    indicator = indicator_levels,
    is_empty = FALSE
  )
  
  empty_slots <- tibble::tibble(
    sovereign_state = this_country,
    indicator = rep(
      NA_character_,
      EMPTY_BARS
    ),
    is_empty = TRUE
  )
  
  layout_parts[[i]] <- dplyr::bind_rows(
    actual_slots,
    empty_slots
  )
}

bar_layout <- dplyr::bind_rows(
  layout_parts
) |>
  dplyr::mutate(
    bar_id = dplyr::row_number()
  )

plot_data <- bar_layout |>
  dplyr::filter(
    !is_empty
  ) |>
  dplyr::left_join(
    country_data,
    by = c(
      "sovereign_state",
      "indicator"
    )
  )


# ============================================================
# 19. COUNTRY GROUP EXTENTS / LABELS
# ============================================================

country_groups <- bar_layout |>
  dplyr::group_by(
    sovereign_state
  ) |>
  dplyr::summarise(
    start = min(
      bar_id[!is_empty]
    ) - 0.40,
    end = max(
      bar_id[!is_empty]
    ) + 0.40,
    title = mean(
      c(
        min(bar_id[!is_empty]),
        max(bar_id[!is_empty])
      )
    ),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    country_code = country_code(
      sovereign_state
    )
  )


# ============================================================
# 20. BACKGROUND RINGS / RADIAL LABELS
# ============================================================

n_bars <- nrow(
  bar_layout
)

ring_data <- tibble::tibble(
  xmin = 0.5,
  xmax = n_bars + 0.5,
  ymin = c(0, 20, 40, 60, 80),
  ymax = c(20, 40, 60, 80, 100),
  ring_fill = RING_COLOURS
)

inner_ring_data <- tibble::tibble(
  xmin = 0.5,
  xmax = n_bars + 0.5,
  ymin = INNER_YMIN,
  ymax = INNER_YMAX
)

last_gap_ids <- tail(
  bar_layout$bar_id[
    bar_layout$is_empty
  ],
  EMPTY_BARS
)

scale_label_x <- mean(
  last_gap_ids
) + SCALE_LABEL_X_NUDGE

scale_label_data <- tibble::tibble(
  x = scale_label_x,
  y = RADIAL_BREAKS,
  label = paste0(
    RADIAL_BREAKS,
    "%"
  )
)

indicator_colours <- complete_indicator_colours(
  indicator_levels
)

indicator_labels <- complete_indicator_labels(
  indicator_levels
)


# ============================================================
# 21. MAIN CIRCULAR PLOT
# ============================================================

element5_circular_plot <- ggplot2::ggplot() +
  
  ggplot2::geom_rect(
    data = ring_data,
    ggplot2::aes(
      xmin = xmin,
      xmax = xmax,
      ymin = ymin,
      ymax = ymax
    ),
    fill = ring_data$ring_fill,
    colour = NA
  ) +
  
  ggplot2::geom_rect(
    data = inner_ring_data,
    ggplot2::aes(
      xmin = xmin,
      xmax = xmax,
      ymin = ymin,
      ymax = ymax
    ),
    fill = INNER_FILL,
    colour = NA
  ) +
  
  ggplot2::geom_col(
    data = plot_data,
    ggplot2::aes(
      x = bar_id,
      y = value,
      fill = indicator
    ),
    width = BAR_WIDTH,
    colour = NA,
    na.rm = TRUE
  ) +
  
  ggplot2::geom_rect(
    data = country_groups,
    ggplot2::aes(
      xmin = start,
      xmax = end,
      ymin = COUNTRY_ARC_YMIN,
      ymax = COUNTRY_ARC_YMAX
    ),
    inherit.aes = FALSE,
    fill = COUNTRY_ARC_COLOUR,
    colour = NA
  ) +
  
  ggplot2::geom_text(
    data = country_groups,
    ggplot2::aes(
      x = title,
      y = COUNTRY_LABEL_Y,
      label = country_code
    ),
    inherit.aes = FALSE,
    colour = COUNTRY_LABEL_COLOUR,
    fontface = "bold",
    size = COUNTRY_LABEL_SIZE
  ) +
  
  ggplot2::geom_text(
    data = scale_label_data,
    ggplot2::aes(
      x = x,
      y = y,
      label = label
    ),
    inherit.aes = FALSE,
    colour = SCALE_LABEL_COLOUR,
    fontface = "bold",
    size = SCALE_LABEL_SIZE,
    hjust = 0.5
  ) +
  
  ggplot2::scale_fill_manual(
    values = indicator_colours,
    breaks = indicator_levels,
    labels = indicator_labels,
    drop = FALSE,
    name = LEGEND_TITLE
  ) +
  
  ggplot2::scale_x_continuous(
    limits = c(
      0.5,
      n_bars + 0.5
    ),
    expand = c(0, 0)
  ) +
  
  ggplot2::scale_y_continuous(
    limits = c(
      INNER_YMIN,
      104
    ),
    expand = c(0, 0)
  ) +
  
  ggplot2::coord_polar(
    theta = "x",
    start = POLAR_START_DEG * pi / 180,
    direction = POLAR_DIRECTION,
    clip = "off"
  ) +
  
  ggplot2::theme_void() +
  
  ggplot2::theme(
    legend.position = "left",
    legend.title = ggplot2::element_text(
      face = "bold",
      size = 11
    ),
    legend.text = ggplot2::element_text(
      size = 10
    ),
    plot.margin = ggplot2::margin(
      5,
      10,
      5,
      10
    )
  )

print(
  element5_circular_plot
)

ggplot2::ggsave(
  filename = file.path(
    PLOT_DIR,
    "element5_larval_sources_sinks_circular.png"
  ),
  plot = element5_circular_plot,
  width = CIRCULAR_FIGURE_WIDTH,
  height = CIRCULAR_FIGURE_HEIGHT,
  dpi = 400,
  bg = "white"
)


# ============================================================
# 22. WIO SUMMARY BAR PLOT
# ============================================================

wio_plot_data <- indicator_summary |>
  dplyr::filter(
    sovereign_state == "WIO",
    indicator %in% indicator_levels
  ) |>
  dplyr::mutate(
    value = suppressWarnings(
      as.numeric(percent_protected_total)
    )
  ) |>
  dplyr::filter(
    !is.na(value),
    is.finite(value)
  )

if (nrow(wio_plot_data) == 0) {
  stop(
    "No WIO source/sink summary values are available for plotting."
  )
}


# ------------------------------------------------------------
# FIXED FIVE-SLOT WIO BAR LAYOUT
# ------------------------------------------------------------
#
# Goal:
#   - keep the same physical bar thickness as plots containing
#     five indicators;
#   - keep the same gap between adjacent bars;
#   - avoid creating dummy/NA rows;
#   - automatically accommodate additional indicators later.
#
# The bars are therefore placed on a DISCRETE slot axis with a
# minimum of five slots. If only two indicators exist, they occupy
# two adjacent slots at the top of a five-slot panel. This behaves
# exactly like a five-category ggplot bar chart, but the unused
# slots remain blank.
#
# Using discrete slots is important: the previous numeric-y approach
# made geom_col() unable to infer the horizontal orientation reliably,
# which could cause rows to be dropped as outside the scale range.
# ------------------------------------------------------------

n_wio_indicators <- nrow(wio_plot_data)

WIO_DISPLAY_SLOTS <- max(
  WIO_REFERENCE_N_INDICATORS,
  n_wio_indicators
)

# Order the WIO indicators using the same least -> most protected
# ordering used elsewhere in the figure.
wio_plot_data <- wio_plot_data |>
  dplyr::mutate(
    wio_indicator_order = match(
      as.character(indicator),
      indicator_levels
    )
  ) |>
  dplyr::arrange(
    wio_indicator_order
  ) |>
  dplyr::mutate(
    # Put the first indicator in the highest slot, then place the
    # remaining indicators immediately below it.
    wio_slot_index =
      WIO_DISPLAY_SLOTS - dplyr::row_number() + 1,
    wio_slot = factor(
      paste0("slot_", wio_slot_index),
      levels = paste0(
        "slot_",
        seq_len(WIO_DISPLAY_SLOTS)
      )
    ),
    indicator = factor(
      as.character(indicator),
      levels = indicator_levels
    )
  )

message(
  "WIO summary layout: ",
  n_wio_indicators,
  " indicator(s) shown in ",
  WIO_DISPLAY_SLOTS,
  " discrete vertical slot(s); bar width = ",
  WIO_BAR_WIDTH
)


wio_summary_plot <- ggplot2::ggplot(
  wio_plot_data,
  ggplot2::aes(
    x = value,
    y = wio_slot,
    fill = indicator
  )
) +
  
  ggplot2::geom_col(
    width = WIO_BAR_WIDTH,
    colour = NA,
    orientation = "y"
  ) +
  
  ggplot2::scale_fill_manual(
    values = indicator_colours,
    breaks = indicator_levels,
    drop = FALSE,
    guide = "none"
  ) +
  
  ggplot2::scale_x_continuous(
    position = "top",
    breaks = WIO_X_BREAKS,
    labels = function(x) {
      paste0(x, "%")
    },
    expand = c(0, 0)
  ) +
  
  # Keep all five reference slots even when only two indicators exist.
  # The two real bars remain adjacent, so both bar thickness and bar
  # spacing match the five-indicator figures.
  ggplot2::scale_y_discrete(
    drop = FALSE,
    labels = NULL,
    expand = ggplot2::expansion(
      add = 0.25
    )
  ) +
  
  ggplot2::coord_cartesian(
    xlim = c(0, WIO_X_MAX),
    clip = "on"
  ) +
  
  ggplot2::labs(
    title = WIO_SUMMARY_TITLE,
    x = NULL,
    y = "Indicator"
  ) +
  
  ggplot2::theme_minimal(
    base_size = 11
  ) +
  
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    axis.text.y = ggplot2::element_blank(),
    axis.ticks.y = ggplot2::element_blank(),
    axis.title.y = ggplot2::element_text(
      face = "bold",
      size = 13,
      margin = ggplot2::margin(
        r = 8
      )
    ),
    axis.text.x = ggplot2::element_text(
      size = 10,
      face = "bold",
      colour = "#444444"
    ),
    axis.ticks.x = ggplot2::element_line(
      colour = "#444444"
    ),
    plot.title = ggplot2::element_text(
      face = "bold",
      hjust = 0.5,
      size = 14,
      margin = ggplot2::margin(
        b = 8
      )
    ),
    plot.margin = ggplot2::margin(
      t = 8,
      r = 10,
      b = 2,
      l = 5
    )
  )


# ============================================================
# 23. CUSTOM BOTTOM-LEFT LEGEND PANEL
# ============================================================

legend_panel_data <- tibble::tibble(
  indicator = indicator_levels,
  label = unname(
    indicator_labels[indicator_levels]
  ),
  legend_y = rev(
    seq_along(indicator_levels)
  )
) |>
  dplyr::mutate(
    indicator = factor(
      indicator,
      levels = indicator_levels
    )
  ) |>
  dplyr::filter(
    !is.na(indicator),
    !is.na(label),
    is.finite(legend_y)
  )

legend_panel <- ggplot2::ggplot(
  legend_panel_data
) +
  
  ggplot2::geom_point(
    ggplot2::aes(
      x = COMBINED_LEGEND_KEY_X,
      y = legend_y,
      fill = indicator
    ),
    shape = 22,
    size = COMBINED_LEGEND_KEY_SIZE,
    stroke = 0,
    colour = NA,
    na.rm = TRUE
  ) +
  
  ggplot2::geom_text(
    ggplot2::aes(
      x = COMBINED_LEGEND_TEXT_X,
      y = legend_y,
      label = label
    ),
    hjust = 0,
    vjust = 0.5,
    size = COMBINED_LEGEND_TEXT_SIZE,
    colour = "#111111",
    na.rm = TRUE
  ) +
  
  ggplot2::scale_fill_manual(
    values = indicator_colours,
    breaks = indicator_levels,
    drop = FALSE,
    guide = "none"
  ) +
  
  # Do not use hard scale limits here because ggplot removes rows that
  # fall outside scale limits before drawing. coord_cartesian() crops the
  # view without dropping the legend data.
  ggplot2::scale_x_continuous(
    expand = c(0, 0)
  ) +
  
  ggplot2::scale_y_continuous(
    expand = c(0, 0)
  ) +
  
  ggplot2::coord_cartesian(
    xlim = c(0, 1),
    ylim = c(
      0.3,
      length(indicator_levels) + 0.8
    ),
    clip = "off"
  ) +
  
  ggplot2::labs(
    title = LEGEND_TITLE
  ) +
  
  ggplot2::theme_void() +
  
  ggplot2::theme(
    plot.title = ggplot2::element_text(
      face = "bold",
      hjust = 0,
      size = COMBINED_LEGEND_TITLE_SIZE,
      margin = ggplot2::margin(
        b = 6
      )
    ),
    plot.margin = ggplot2::margin(
      t = 2,
      r = 5,
      b = 5,
      l = 20
    )
  )


# ============================================================
# 24. COMBINED WIO + CIRCULAR FIGURE
# ============================================================

circle_for_combined <- element5_circular_plot +
  ggplot2::theme(
    legend.position = "none",
    plot.margin = ggplot2::margin(
      0,
      0,
      0,
      0
    )
  )

left_column <- (
  wio_summary_plot /
    legend_panel
) +
  patchwork::plot_layout(
    heights = COMBINED_TOP_BOTTOM_HEIGHTS
  )

combined_plot <- (
  left_column |
    circle_for_combined
) +
  patchwork::plot_layout(
    widths = COMBINED_LEFT_RIGHT_WIDTHS
  )

print(
  combined_plot
)

ggplot2::ggsave(
  filename = file.path(
    PLOT_DIR,
    "element5_larval_sources_sinks_WIO_summary_and_circular.png"
  ),
  plot = combined_plot,
  width = COMBINED_FIGURE_WIDTH,
  height = COMBINED_FIGURE_HEIGHT,
  dpi = 400,
  bg = "white"
)


# ============================================================
# 25. SAVE PLOTTING DATA
# ============================================================

readr::write_csv(
  plot_data |>
    dplyr::select(
      sovereign_state,
      indicator,
      value,
      bar_id
    ),
  file.path(
    OUTPUT_DIR,
    "element5_circular_plot_data.csv"
  )
)

readr::write_csv(
  wio_indicator_rank |>
    dplyr::select(
      indicator,
      value
    ) |>
    dplyr::rename(
      wio_percent_protected = value
    ),
  file.path(
    OUTPUT_DIR,
    "element5_WIO_indicator_order_least_to_most.csv"
  )
)


# ============================================================
# 26. FINISH
# ============================================================

message(
  "\n============================================================"
)
message(
  "ELEMENT 5 LARVAL SOURCE / SINK ANALYSIS COMPLETE"
)
message(
  "============================================================"
)

message(
  "\nHistorical rules reproduced:"
)
message(
  "  Country sources: NetflowC5 > country q75"
)
message(
  "  Country sinks:   NetflowC5 < country q25"
)
message(
  "  WIO sources:     NetflowC5 > WIO q75"
)
message(
  "  WIO sinks:       NetflowC5 < WIO q25"
)
message(
  "  Protection:      any overlap of 4-km-radius reef-cell footprint with protected area"
)

message(
  "\nOutput folder:\n",
  normalizePath(OUTPUT_DIR)
)

message(
  "\nMain summary CSV:\n",
  normalizePath(
    file.path(
      OUTPUT_DIR,
      "element5_larval_sources_sinks_protection_by_sovereign.csv"
    )
  )
)

message(
  "\nCombined figure:\n",
  normalizePath(
    file.path(
      PLOT_DIR,
      "element5_larval_sources_sinks_WIO_summary_and_circular.png"
    )
  )
)

message(
  "\nDone."
)