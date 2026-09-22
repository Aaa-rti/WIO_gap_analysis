# ============================================================
# ELEMENT 3
# WIO AREAS OF PARTICULAR IMPORTANCE FOR BIODIVERSITY
# AND ECOSYSTEM FUNCTIONS / SERVICES
#
# FILTERED MPA + OECM VERSION
# AREA + POINT VERSION
#
# Current indicators:
#   1. KBAs                              polygons -> area
#   2. IBAs                              polygons -> area
#   3. Turtle nesting sites              points   -> counts
#   4. EBSAs                             polygons -> area
#   5. Fish larval dispersal corridors   points   -> counts
#
# Protection is partitioned into THREE MUTUALLY EXCLUSIVE classes:
#
#   - MPA only
#   - OECM only
#   - MPA-OECM overlap

# LARVAL DISPERSAL CORRIDORS
# --------------------------
#
# Connectivity points are FIRST assigned to sovereign EEZs.
#
# STEP 1 — define dispersal corridors:
#
#   OutflowP5 > 0
#   InflowP5  > 0
#
# STEP 2 — identify highly connected / key corridors:
#
#   Within EACH sovereign state's corridor subset, calculate:
#
#     q75 = 75th percentile of InflowP5
#
#   Then retain corridor reefs where:
#
#     InflowP5 > country-specific corridor q75
#
# GRID-CELL FOOTPRINT:
#
#   Connectivity points are centroids of ~8 km grid cells.
#   A 4 km-radius buffer is therefore created around EVERY
#   connectivity centroid immediately after the layer is read.
#
#   The centroid remains the ownership geometry used to assign
#   each grid cell to one sovereign EEZ.
#
#   The PRE-CREATED 4 km buffer is carried through the corridor
#   and q75 selections and is the geometry tested against the
#   filtered MPA and OECM footprints.
#
#
# IMPORTANT:
# The WIO regional row is the sum of the country-selected key
# corridor points. A new WIO-wide q75 is NOT calculated.
# ============================================================


rm(list = ls())


# ------------------------------------------------------------
# 1. Packages
# ------------------------------------------------------------

pkgs <- c(
  "sf",
  "dplyr",
  "tidyr",
  "tibble",
  "purrr",
  "stringr",
  "ggplot2",
  "readr",
  "rlang",
  "digest"
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


if (
  length(
    missing_pkgs
  ) > 0
) {
  
  install.packages(
    missing_pkgs
  )
}


invisible(
  lapply(
    pkgs,
    library,
    character.only = TRUE
  )
)


# Equal-area / planar geometry workflow.
sf::sf_use_s2(FALSE)



# ============================================================
# 2. USER SETTINGS
# ============================================================


# ------------------------------------------------------------
# 2a. Filtered Element 1 protection database
# ------------------------------------------------------------

PROTECTION_GPKG <-
  "outputs/wio_protected_area_spatial_database.gpkg"


EEZ_LAYER <-
  "eez_by_country"


PROTECTED_LAYER <-
  "protected_unique_by_country"


MPA_LAYER <-
  "mpa_unique_by_country"


OECM_LAYER <-
  "oecm_unique_by_country"



# ------------------------------------------------------------
# 2b. Sovereign states excluded from Element 2 onward
# ------------------------------------------------------------

EXCLUDED_SOVEREIGN_STATES <-
  c(
    "Disputed"
  )



# ------------------------------------------------------------
# 2c. Indicator inputs
# ------------------------------------------------------------
#
# enabled:
#
#   TRUE  = process this indicator
#   FALSE = retain as a ready placeholder but do not run
#
#
# filter_mode:
#
#   "none"
#       No special country-dependent filtering.
#
#   "larval_country_q75"
#       Assign points to EEZ first, then calculate the country's
#       InflowP5 q75 and apply the larval-corridor rule.
#
#
# filter_expr:
#
#   Optional ordinary dplyr filter applied BEFORE the spatial
#   analysis.
#
#   Leave NA for the current datasets unless another source-data
#   criterion is required.
#
# ------------------------------------------------------------

indicator_inputs <-
  tibble::tribble(
    
    ~path,
    ~layer,
    ~indicator,
    ~data_type,
    ~measure_type,
    ~filter_mode,
    ~filter_expr,
    ~enabled,
    
    
    # --------------------------------------------------------
    # KEY BIODIVERSITY AREAS
    # --------------------------------------------------------
    
    "indicators/KBA_wio/KBA_wio.shp",
    NA_character_,
    "KBAs",
    "vector",
    "area",
    "none",
    NA_character_,
    TRUE,
    
    
    # --------------------------------------------------------
    # IMPORTANT BIRD AREAS
    # --------------------------------------------------------
    
    "indicators/IBA_wio/IBA_wio.shp",
    NA_character_,
    "IBAs",
    "vector",
    "area",
    "none",
    NA_character_,
    TRUE,
    
    
    # --------------------------------------------------------
    # TURTLE NESTING SITES
    # --------------------------------------------------------
    
    "indicators/obis_seamap_swot_6a79375d314f6_20260809_223819_site_locations_shapefile_99283/obis_seamap_swot_6a79375d314f6_20260809_223819_site_locations_shapefile.shp",
    NA_character_,
    "Turtle Nesting Sites",
    "vector",
    "points",
    "none",
    NA_character_,
    TRUE,
    
    
    # --------------------------------------------------------
    # ECOLOGICALLY OR BIOLOGICALLY SIGNIFICANT MARINE AREAS
    # --------------------------------------------------------
    
    "indicators/EBSA_combined.gpkg",
    NA_character_,
    "EBSAs",
    "vector",
    "area",
    "none",
    NA_character_,
    TRUE,
    
    
    # --------------------------------------------------------
    # FISH LARVAL DISPERSAL CORRIDORS
    # --------------------------------------------------------
    
    "indicators/Connectivity/Connectivity.shp",
    NA_character_,
    "Fish Larval Dispersal Corridors",
    "vector",
    "points",
    "larval_country_q75",
    NA_character_,
    TRUE,
    

# Assign ONLY if an indicator genuinely has missing CRS metadata.
SOURCE_INDICATOR_CRS_IF_MISSING <-
  NA_character_



# ------------------------------------------------------------
# 2d. Larval corridor settings
# ------------------------------------------------------------

LARVAL_INFLOW_FIELD <-
  "InflowP5"


LARVAL_OUTFLOW_FIELD <-
  "OutflowP5"


LARVAL_ID_FIELD <-
  "ID_2"


LARVAL_INFLOW_QUANTILE <-
  0.75


LARVAL_QUANTILE_INCLUSIVE <-
  FALSE


LARVAL_REQUIRE_POSITIVE_INFLOW <-
  TRUE


LARVAL_REQUIRE_POSITIVE_OUTFLOW <-
  TRUE


# ------------------------------------------------------------
# 2e. Larval grid-cell protection buffer
# ------------------------------------------------------------
#
# The connectivity point is the centroid of an ~8 km grid cell.
# Default radius = half the cell width = 4 km.
# ------------------------------------------------------------

LARVAL_GRID_CELL_WIDTH_KM <-
  8


LARVAL_PROTECTION_BUFFER_KM <-
  4



# ------------------------------------------------------------
# 2f. Polygon memory settings
# ------------------------------------------------------------

VECTOR_BATCH_SIZE <-
  1000



# ------------------------------------------------------------
# 2g. Output folders
# ------------------------------------------------------------

out_dir <-
  file.path(
    "outputs",
    "element3"
  )


dir.create(
  out_dir,
  showWarnings = FALSE,
  recursive = TRUE
)


cache_dir <-
  file.path(
    out_dir,
    "cache"
  )


dir.create(
  cache_dir,
  showWarnings = FALSE,
  recursive = TRUE
)


spatial_cache_dir <-
  file.path(
    out_dir,
    "spatial_cache"
  )


dir.create(
  spatial_cache_dir,
  showWarnings = FALSE,
  recursive = TRUE
)


plot_dir <-
  file.path(
    out_dir,
    "plots"
  )


dir.create(
  plot_dir,
  showWarnings = FALSE,
  recursive = TRUE
)


exclusive_gpkg <-
  file.path(
    out_dir,
    "element3_protection_exclusive_zones.gpkg"
  )


larval_threshold_csv <-
  file.path(
    out_dir,
    "element3_larval_country_thresholds.csv"
  )



# ------------------------------------------------------------
# 2h. Cache controls
# ------------------------------------------------------------

FORCE_RERUN <-
  FALSE


CACHE_VERSION <-
  "element3_filtered_mpa_oecm_larval_buffer_first_4km_v4"



# ------------------------------------------------------------
# 2i. Plot order
# ------------------------------------------------------------

COUNTRY_ORDER <-
  c(
    "Tanzania",
    "South Africa",
    "Seychelles",
    "Mozambique",
    "Mauritius",
    "Madagascar",
    "Kenya",
    "France",
    "Comoro Islands",
    "Comoros"
  )



# ============================================================
# 3. BASIC HELPERS
# ============================================================


timer <- function(label,
                  expr) {
  
  message(
    "\n--- ",
    label,
    " ---"
  )
  
  
  t <-
    system.time(
      out <- force(
        expr
      )
    )
  
  
  message(
    label,
    " elapsed seconds: ",
    round(
      t[["elapsed"]],
      2
    )
  )
  
  
  out
}



clean_filename <- function(x) {
  
  x |>
    stringr::str_to_lower() |>
    stringr::str_replace_all(
      "[^a-z0-9]+",
      "_"
    ) |>
    stringr::str_replace_all(
      "^_|_$",
      ""
    )
}



safe_divide <- function(num,
                        den) {
  
  ifelse(
    !is.na(
      den
    ) &
      den >
      0,
    num /
      den,
    NA_real_
  )
}



sum_or_na <- function(x) {
  
  if (
    all(
      is.na(
        x
      )
    )
  ) {
    
    return(
      NA_real_
    )
  }
  
  
  sum(
    x,
    na.rm = TRUE
  )
}



sum_int_or_na <- function(x) {
  
  if (
    all(
      is.na(
        x
      )
    )
  ) {
    
    return(
      NA_integer_
    )
  }
  
  
  as.integer(
    sum(
      x,
      na.rm = TRUE
    )
  )
}



normalise_sovereign_name <- function(x) {
  
  x |>
    as.character() |>
    stringr::str_squish() |>
    stringr::str_to_lower()
}



exclude_sovereign_states <- function(
    x,
    sovereign_col = "sovereign_state") {
  
  if (
    !(
      sovereign_col %in%
      names(
        x
      )
    )
  ) {
    
    stop(
      "Cannot exclude sovereign states because column is missing: ",
      sovereign_col
    )
  }
  
  
  excluded_norm <-
    normalise_sovereign_name(
      EXCLUDED_SOVEREIGN_STATES
    )
  
  
  state_norm <-
    normalise_sovereign_name(
      x[[sovereign_col]]
    )
  
  
  keep <-
    !state_norm %in%
    excluded_norm
  
  
  n_removed <-
    sum(
      !keep,
      na.rm = TRUE
    )
  
  
  if (
    n_removed >
    0
  ) {
    
    message(
      "Excluded ",
      n_removed,
      " row(s) for: ",
      paste(
        EXCLUDED_SOVEREIGN_STATES,
        collapse = ", "
      )
    )
  }
  
  
  x[
    keep,
    ,
    drop = FALSE
  ]
}



read_sf_any <- function(path,
                        layer = NA_character_) {
  
  layer_missing <-
    is.null(
      layer
    ) ||
    length(
      layer
    ) ==
    0 ||
    is.na(
      layer
    ) ||
    !nzchar(
      layer
    )
  
  
  if (
    !file.exists(
      path
    )
  ) {
    
    stop(
      "File not found: ",
      path
    )
  }
  
  
  if (
    layer_missing
  ) {
    
    sf::st_read(
      path,
      quiet = FALSE
    )
    
  } else {
    
    sf::st_read(
      path,
      layer = layer,
      quiet = FALSE
    )
  }
}



read_required_gpkg_layer <- function(gpkg,
                                     layer) {
  
  available_layers <-
    sf::st_layers(
      gpkg
    )$name
  
  
  if (
    !(
      layer %in%
      available_layers
    )
  ) {
    
    stop(
      "Required layer not found in:\n",
      gpkg,
      "\n\nMissing layer: ",
      layer,
      "\n\nAvailable layers:\n",
      paste(
        available_layers,
        collapse = "\n"
      )
    )
  }
  
  
  sf::st_read(
    gpkg,
    layer = layer,
    quiet = FALSE
  )
}



make_valid_polygonal <- function(x) {
  
  if (
    !inherits(
      x,
      "sf"
    )
  ) {
    
    stop(
      "make_valid_polygonal() expects an sf object."
    )
  }
  
  
  if (
    nrow(
      x
    ) ==
    0
  ) {
    
    return(
      x
    )
  }
  
  
  x <-
    suppressWarnings(
      sf::st_make_valid(
        x
      )
    )
  
  
  x <-
    x[
      !sf::st_is_empty(
        x
      ),
      ,
      drop = FALSE
    ]
  
  
  if (
    nrow(
      x
    ) ==
    0
  ) {
    
    return(
      x
    )
  }
  
  
  geom_types <-
    as.character(
      sf::st_geometry_type(
        x,
        by_geometry = TRUE
      )
    )
  
  
  if (
    any(
      geom_types %in%
      c(
        "GEOMETRY",
        "GEOMETRYCOLLECTION"
      )
    )
  ) {
    
    x <-
      suppressWarnings(
        sf::st_collection_extract(
          x,
          "POLYGON",
          warn = FALSE
        )
      )
  }
  
  
  x <-
    x[
      !sf::st_is_empty(
        x
      ),
      ,
      drop = FALSE
    ]
  
  
  if (
    nrow(
      x
    ) ==
    0
  ) {
    
    return(
      x
    )
  }
  
  
  geom_types <-
    as.character(
      sf::st_geometry_type(
        x,
        by_geometry = TRUE
      )
    )
  
  
  x <-
    x[
      geom_types %in%
        c(
          "POLYGON",
          "MULTIPOLYGON"
        ),
      ,
      drop = FALSE
    ]
  
  
  x
}



make_point_sf <- function(x) {
  
  if (
    !inherits(
      x,
      "sf"
    )
  ) {
    
    stop(
      "make_point_sf() expects an sf object."
    )
  }
  
  
  if (
    nrow(
      x
    ) ==
    0
  ) {
    
    return(
      x
    )
  }
  
  
  geom_types <-
    unique(
      as.character(
        sf::st_geometry_type(
          x,
          by_geometry = TRUE
        )
      )
    )
  
  
  if (
    any(
      geom_types ==
      "GEOMETRYCOLLECTION"
    )
  ) {
    
    x <-
      suppressWarnings(
        sf::st_collection_extract(
          x,
          "POINT",
          warn = FALSE
        )
      )
  }
  
  
  geom_types <-
    unique(
      as.character(
        sf::st_geometry_type(
          x,
          by_geometry = TRUE
        )
      )
    )
  
  
  if (
    any(
      geom_types ==
      "MULTIPOINT"
    )
  ) {
    
    x <-
      suppressWarnings(
        sf::st_cast(
          x,
          "POINT",
          warn = FALSE
        )
      )
  }
  
  
  geom_types <-
    unique(
      as.character(
        sf::st_geometry_type(
          x,
          by_geometry = TRUE
        )
      )
    )
  
  
  if (
    !all(
      geom_types ==
      "POINT"
    )
  ) {
    
    stop(
      "Point indicator contains non-point geometry after cleaning: ",
      paste(
        geom_types,
        collapse = ", "
      )
    )
  }
  
  
  x[
    !sf::st_is_empty(
      x
    ),
    ,
    drop = FALSE
  ]
}



apply_optional_filter <- function(
    x,
    filter_expr,
    indicator) {
  
  no_filter <-
    is.null(
      filter_expr
    ) ||
    length(
      filter_expr
    ) ==
    0 ||
    is.na(
      filter_expr
    ) ||
    !nzchar(
      stringr::str_squish(
        filter_expr
      )
    )
  
  
  if (
    no_filter
  ) {
    
    return(
      x
    )
  }
  
  
  n_before <-
    nrow(
      x
    )
  
  
  message(
    "Applying source-data filter for ",
    indicator,
    ": ",
    filter_expr
  )
  
  
  expr <-
    tryCatch(
      
      rlang::parse_expr(
        filter_expr
      ),
      
      error = function(e) {
        
        stop(
          "Could not parse filter_expr for ",
          indicator,
          ":\n",
          filter_expr,
          "\n\n",
          conditionMessage(
            e
          )
        )
      }
    )
  
  
  out <-
    tryCatch(
      
      dplyr::filter(
        x,
        !!expr
      ),
      
      error = function(e) {
        
        stop(
          "Could not apply filter_expr for ",
          indicator,
          ".\n\nAvailable fields:\n",
          paste(
            names(
              x
            ),
            collapse = ", "
          ),
          "\n\n",
          conditionMessage(
            e
          )
        )
      }
    )
  
  
  message(
    "Filter kept ",
    nrow(
      out
    ),
    " of ",
    n_before,
    " features."
  )
  
  
  out
}



infer_measure_type_from_sf <- function(x) {
  
  geom_types <-
    unique(
      as.character(
        sf::st_geometry_type(
          x,
          by_geometry = TRUE
        )
      )
    )
  
  
  if (
    all(
      geom_types %in%
      c(
        "POINT",
        "MULTIPOINT"
      )
    )
  ) {
    
    return(
      "points"
    )
  }
  
  
  if (
    any(
      geom_types %in%
      c(
        "POLYGON",
        "MULTIPOLYGON"
      )
    )
  ) {
    
    return(
      "area"
    )
  }
  
  
  stop(
    "Could not infer measure type from geometry: ",
    paste(
      geom_types,
      collapse = ", "
    )
  )
}



safe_quantile <- function(
    x,
    prob) {
  
  x <-
    suppressWarnings(
      as.numeric(
        x
      )
    )
  
  
  x <-
    x[
      is.finite(
        x
      ) &
        !is.na(
          x
        )
    ]
  
  
  if (
    length(
      x
    ) ==
    0
  ) {
    
    return(
      NA_real_
    )
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



# ============================================================
# 4. INPUT CHECKS
# ============================================================


if (
  !file.exists(
    PROTECTION_GPKG
  )
) {
  
  stop(
    "Filtered Element 1 protection GeoPackage not found:\n",
    PROTECTION_GPKG
  )
}



available_protection_layers <-
  sf::st_layers(
    PROTECTION_GPKG
  )$name


required_protection_layers <-
  c(
    EEZ_LAYER,
    PROTECTED_LAYER,
    MPA_LAYER,
    OECM_LAYER
  )


missing_protection_layers <-
  setdiff(
    required_protection_layers,
    available_protection_layers
  )


if (
  length(
    missing_protection_layers
  ) >
  0
) {
  
  stop(
    "Element 1 GeoPackage is missing required layers:\n",
    paste(
      missing_protection_layers,
      collapse = "\n"
    ),
    "\n\nAvailable layers:\n",
    paste(
      available_protection_layers,
      collapse = "\n"
    )
  )
}



indicator_inputs <-
  indicator_inputs |>
  dplyr::filter(
    enabled
  )


if (
  nrow(
    indicator_inputs
  ) ==
  0
) {
  
  stop(
    "No Element 3 indicators are enabled."
  )
}



missing_indicator_files <-
  indicator_inputs |>
  dplyr::filter(
    is.na(
      path
    ) |
      !file.exists(
        path
      )
  )


if (
  nrow(
    missing_indicator_files
  ) >
  0
) {
  
  stop(
    "The following ENABLED indicator files do not exist:\n",
    paste(
      missing_indicator_files$path,
      collapse = "\n"
    ),
    "\n\nEither correct the path or set enabled = FALSE."
  )
}



message(
  "\nIndicators enabled for Element 3:"
)


print(
  indicator_inputs
)



# ============================================================
# 5. LOAD FILTERED ELEMENT 1 PROTECTION LAYERS
# ============================================================


zone_eez <-
  timer(
    
    "Load EEZ by country",
    
    read_required_gpkg_layer(
      PROTECTION_GPKG,
      EEZ_LAYER
    )
  ) |>
  exclude_sovereign_states()



if (
  !(
    "sovereign_state" %in%
    names(
      zone_eez
    )
  )
) {
  
  stop(
    "eez_by_country is missing sovereign_state."
  )
}



ANALYSIS_CRS <-
  sf::st_crs(
    zone_eez
  )


if (
  is.na(
    ANALYSIS_CRS
  )
) {
  
  stop(
    "eez_by_country has no CRS."
  )
}



if (
  !(
    "eez_area_km2" %in%
    names(
      zone_eez
    )
  )
) {
  
  zone_eez$eez_area_km2 <-
    as.numeric(
      sf::st_area(
        zone_eez
      )
    ) /
    1e6
}



zone_eez <-
  zone_eez |>
  dplyr::select(
    sovereign_state,
    eez_area_km2
  )



zone_protected <-
  timer(
    
    "Load unique combined MPA + OECM footprint",
    
    read_required_gpkg_layer(
      PROTECTION_GPKG,
      PROTECTED_LAYER
    ) |>
      sf::st_transform(
        ANALYSIS_CRS
      ) |>
      dplyr::select(
        sovereign_state
      )
  ) |>
  exclude_sovereign_states()



zone_mpa <-
  timer(
    
    "Load unique MPA footprint",
    
    read_required_gpkg_layer(
      PROTECTION_GPKG,
      MPA_LAYER
    ) |>
      sf::st_transform(
        ANALYSIS_CRS
      ) |>
      dplyr::select(
        sovereign_state
      )
  ) |>
  exclude_sovereign_states()



zone_oecm <-
  timer(
    
    "Load unique OECM footprint",
    
    read_required_gpkg_layer(
      PROTECTION_GPKG,
      OECM_LAYER
    ) |>
      sf::st_transform(
        ANALYSIS_CRS
      ) |>
      dplyr::select(
        sovereign_state
      )
  ) |>
  exclude_sovereign_states()



eez_table <-
  zone_eez |>
  sf::st_drop_geometry() |>
  dplyr::select(
    sovereign_state,
    eez_area_km2
  )



message(
  "\nAnalysis zones after exclusions:"
)


message(
  "  EEZ countries:       ",
  nrow(
    zone_eez
  )
)



message(
  "  MPA country zones:   ",
  nrow(
    zone_mpa
  )
)


message(
  "  OECM country zones:  ",
  nrow(
    zone_oecm
  )
)



# ============================================================
# 6. CREATE MUTUALLY EXCLUSIVE PROTECTION ZONES
# ============================================================


create_exclusive_protection_zones <- function(
    eez_sf,
    mpa_sf,
    oecm_sf) {
  
  
  results <-
    list()
  
  
  k <-
    1
  
  
  countries <-
    eez_sf$sovereign_state
  
  
  for (
    country in
    countries
  ) {
    
    message(
      "Building MPA/OECM partition: ",
      country
    )
    
    
    mpa_country <-
      mpa_sf |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    oecm_country <-
      oecm_sf |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    has_mpa <-
      nrow(
        mpa_country
      ) >
      0
    
    
    has_oecm <-
      nrow(
        oecm_country
      ) >
      0
    
    
    if (
      !has_mpa &&
      !has_oecm
    ) {
      
      next
    }
    
    
    if (
      has_mpa
    ) {
      
      mpa_geom <-
        sf::st_union(
          sf::st_geometry(
            mpa_country
          )
        )
    }
    
    
    if (
      has_oecm
    ) {
      
      oecm_geom <-
        sf::st_union(
          sf::st_geometry(
            oecm_country
          )
        )
    }
    
    
    if (
      has_mpa &&
      has_oecm
    ) {
      
      pieces <-
        list(
          
          "MPA only" =
            suppressWarnings(
              sf::st_difference(
                mpa_geom,
                oecm_geom
              )
            ),
          
          "OECM only" =
            suppressWarnings(
              sf::st_difference(
                oecm_geom,
                mpa_geom
              )
            ),
          
          "MPA-OECM overlap" =
            suppressWarnings(
              sf::st_intersection(
                mpa_geom,
                oecm_geom
              )
            )
        )
      
      
    } else if (
      has_mpa
    ) {
      
      pieces <-
        list(
          "MPA only" =
            mpa_geom
        )
      
      
    } else {
      
      pieces <-
        list(
          "OECM only" =
            oecm_geom
        )
    }
    
    
    for (
      category in
      names(
        pieces
      )
    ) {
      
      g <-
        pieces[[category]]
      
      
      if (
        length(
          g
        ) ==
        0 ||
        all(
          sf::st_is_empty(
            g
          )
        )
      ) {
        
        next
      }
      
      
      temp <-
        sf::st_sf(
          
          sovereign_state =
            country,
          
          protection_category =
            category,
          
          geometry =
            g
        ) |>
        make_valid_polygonal()
      
      
      if (
        nrow(
          temp
        ) ==
        0
      ) {
        
        next
      }
      
      
      temp <-
        temp |>
        dplyr::group_by(
          sovereign_state,
          protection_category
        ) |>
        dplyr::summarise(
          .groups = "drop"
        ) |>
        make_valid_polygonal()
      
      
      results[[k]] <-
        temp
      
      
      k <-
        k +
        1
    }
  }
  
  
  if (
    length(
      results
    ) ==
    0
  ) {
    
    stop(
      "No MPA/OECM exclusive zones could be created."
    )
  }
  
  
  dplyr::bind_rows(
    results
  )
}



protection_exclusive <-
  timer(
    
    "Create MPA-only / OECM-only / overlap zones",
    
    create_exclusive_protection_zones(
      eez_sf =
        zone_eez,
      mpa_sf =
        zone_mpa,
      oecm_sf =
        zone_oecm
    )
  )



protection_exclusive$area_km2 <-
  as.numeric(
    sf::st_area(
      protection_exclusive
    )
  ) /
  1e6



if (
  file.exists(
    exclusive_gpkg
  )
) {
  
  unlink(
    exclusive_gpkg
  )
}



sf::st_write(
  protection_exclusive,
  dsn =
    exclusive_gpkg,
  layer =
    "protection_exclusive_by_country",
  quiet =
    TRUE
)



# ------------------------------------------------------------
# QA: exclusive partition should reproduce Element 1 combined
# protection footprint.
# ------------------------------------------------------------

exclusive_qa <-
  protection_exclusive |>
  sf::st_drop_geometry() |>
  dplyr::group_by(
    sovereign_state
  ) |>
  dplyr::summarise(
    exclusive_area_km2 =
      sum(
        area_km2,
        na.rm = TRUE
      ),
    .groups = "drop"
  )



protected_qa <-
  zone_protected |>
  dplyr::mutate(
    protected_area_km2 =
      as.numeric(
        sf::st_area(
          zone_protected
        )
      ) /
      1e6
  ) |>
  sf::st_drop_geometry() |>
  dplyr::select(
    sovereign_state,
    protected_area_km2
  )



exclusive_qa <-
  eez_table |>
  dplyr::select(
    sovereign_state
  ) |>
  dplyr::left_join(
    exclusive_qa,
    by = "sovereign_state"
  ) |>
  dplyr::left_join(
    protected_qa,
    by = "sovereign_state"
  ) |>
  dplyr::mutate(
    exclusive_area_km2 =
      tidyr::replace_na(
        exclusive_area_km2,
        0
      ),
    protected_area_km2 =
      tidyr::replace_na(
        protected_area_km2,
        0
      ),
    difference_km2 =
      exclusive_area_km2 -
      protected_area_km2
  )



if (
  any(
    abs(
      exclusive_qa$difference_km2
    ) >
    0.01,
    na.rm = TRUE
  )
) {
  
  warning(
    "Exclusive MPA/OECM zones differ from protected_unique_by_country by >0.01 km2 for at least one country."
  )
  
  
  print(
    exclusive_qa |>
      dplyr::filter(
        abs(
          difference_km2
        ) >
          0.01
      )
  )
}



# ============================================================
# 7. READ VECTOR INDICATOR
# ============================================================


read_vector_indicator <- function(
    path,
    layer,
    indicator,
    filter_expr) {
  
  
  x <-
    read_sf_any(
      path,
      layer
    )
  
  
  if (
    is.na(
      sf::st_crs(
        x
      )
    )
  ) {
    
    if (
      is.na(
        SOURCE_INDICATOR_CRS_IF_MISSING
      )
    ) {
      
      stop(
        "Indicator has missing CRS and no fallback was supplied:\n",
        path
      )
    }
    
    
    sf::st_crs(
      x
    ) <-
      SOURCE_INDICATOR_CRS_IF_MISSING
  }
  
  
  x <-
    x |>
    apply_optional_filter(
      filter_expr =
        filter_expr,
      indicator =
        indicator
    ) |>
    sf::st_transform(
      ANALYSIS_CRS
    )
  
  
  x
}



# ============================================================
# 8. POLYGON INDICATOR: DISSOLVE TO ONE FOOTPRINT PER COUNTRY
# ============================================================


dissolve_indicator_by_country <- function(
    indicator_sf,
    indicator,
    batch_size =
      VECTOR_BATCH_SIZE) {
  
  
  indicator_geom <-
    sf::st_sf(
      geometry =
        sf::st_geometry(
          indicator_sf
        )
    ) |>
    make_valid_polygonal()
  
  
  country_results <-
    vector(
      "list",
      nrow(
        zone_eez
      )
    )
  
  
  for (
    i in
    seq_len(
      nrow(
        zone_eez
      )
    )
  ) {
    
    country_zone <-
      zone_eez[
        i,
        ,
        drop = FALSE
      ]
    
    
    country <-
      country_zone$sovereign_state[[1]]
    
    
    message(
      "\n",
      indicator,
      ": dissolve within ",
      country
    )
    
    
    hits <-
      sf::st_intersects(
        indicator_geom,
        country_zone,
        sparse = TRUE
      )
    
    
    idx <-
      which(
        lengths(
          hits
        ) >
          0
      )
    
    
    if (
      length(
        idx
      ) ==
      0
    ) {
      
      next
    }
    
    
    starts <-
      seq(
        1,
        length(
          idx
        ),
        by =
          batch_size
      )
    
    
    batch_unions <-
      vector(
        "list",
        length(
          starts
        )
      )
    
    
    for (
      b in
      seq_along(
        starts
      )
    ) {
      
      start_pos <-
        starts[[b]]
      
      
      end_pos <-
        min(
          start_pos +
            batch_size -
            1,
          length(
            idx
          )
        )
      
      
      batch_idx <-
        idx[
          start_pos:end_pos
        ]
      
      
      message(
        "  batch ",
        b,
        "/",
        length(
          starts
        ),
        " (",
        length(
          batch_idx
        ),
        " features)"
      )
      
      
      batch <-
        indicator_geom[
          batch_idx,
          ,
          drop = FALSE
        ]
      
      
      clipped <-
        suppressWarnings(
          sf::st_intersection(
            batch,
            country_zone |>
              dplyr::select(
                sovereign_state
              )
          )
        ) |>
        make_valid_polygonal()
      
      
      if (
        nrow(
          clipped
        ) ==
        0
      ) {
        
        rm(
          batch,
          clipped
        )
        
        gc(
          verbose = FALSE
        )
        
        next
      }
      
      
      one_batch <-
        sf::st_sf(
          geometry =
            sf::st_union(
              sf::st_geometry(
                clipped
              )
            )
        ) |>
        make_valid_polygonal()
      
      
      if (
        nrow(
          one_batch
        ) >
        0
      ) {
        
        batch_unions[[b]] <-
          one_batch
      }
      
      
      rm(
        batch,
        clipped,
        one_batch
      )
      
      
      gc(
        verbose = FALSE
      )
    }
    
    
    batch_unions <-
      purrr::compact(
        batch_unions
      )
    
    
    if (
      length(
        batch_unions
      ) ==
      0
    ) {
      
      next
    }
    
    
    combined <-
      dplyr::bind_rows(
        batch_unions
      )
    
    
    country_result <-
      sf::st_sf(
        sovereign_state =
          country,
        geometry =
          sf::st_union(
            sf::st_geometry(
              combined
            )
          )
      ) |>
      make_valid_polygonal()
    
    
    if (
      nrow(
        country_result
      ) >
      0
    ) {
      
      country_result <-
        country_result |>
        dplyr::group_by(
          sovereign_state
        ) |>
        dplyr::summarise(
          .groups = "drop"
        ) |>
        make_valid_polygonal()
      
      
      country_results[[i]] <-
        country_result
    }
    
    
    rm(
      batch_unions,
      combined,
      country_result
    )
    
    
    gc(
      verbose = FALSE
    )
  }
  
  
  country_results <-
    purrr::compact(
      country_results
    )
  
  
  if (
    length(
      country_results
    ) ==
    0
  ) {
    
    stop(
      "No ",
      indicator,
      " polygons intersected the retained WIO EEZs."
    )
  }
  
  
  dplyr::bind_rows(
    country_results
  )
}



# ============================================================
# 9. POLYGON INDICATOR: PROTECTION COMPOSITION
# ============================================================


area_composition_from_country_indicator <- function(
    indicator_by_country) {
  
  
  results <-
    list()
  
  
  k <-
    1
  
  
  for (
    country in
    eez_table$sovereign_state
  ) {
    
    indicator_country <-
      indicator_by_country |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    total_area <-
      if (
        nrow(
          indicator_country
        ) ==
        0
      ) {
        
        0
        
      } else {
        
        sum(
          as.numeric(
            sf::st_area(
              indicator_country
            )
          ) /
            1e6,
          na.rm = TRUE
        )
      }
    
    
    results[[k]] <-
      tibble::tibble(
        sovereign_state =
          country,
        protection_category =
          "TOTAL_INDICATOR",
        amount =
          total_area
      )
    
    
    k <-
      k +
      1
    
    
    zones_country <-
      protection_exclusive |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    if (
      nrow(
        indicator_country
      ) ==
      0 ||
      nrow(
        zones_country
      ) ==
      0
    ) {
      
      next
    }
    
    
    for (
      z in
      seq_len(
        nrow(
          zones_country
        )
      )
    ) {
      
      this_zone <-
        zones_country[
          z,
          ,
          drop = FALSE
        ]
      
      
      category <-
        this_zone$protection_category[[1]]
      
      
      inter <-
        suppressWarnings(
          sf::st_intersection(
            indicator_country |>
              dplyr::select(
                sovereign_state
              ),
            this_zone |>
              dplyr::select(
                protection_category
              )
          )
        ) |>
        make_valid_polygonal()
      
      
      area_km2 <-
        if (
          nrow(
            inter
          ) ==
          0
        ) {
          
          0
          
        } else {
          
          sum(
            as.numeric(
              sf::st_area(
                inter
              )
            ) /
              1e6,
            na.rm = TRUE
          )
        }
      
      
      results[[k]] <-
        tibble::tibble(
          sovereign_state =
            country,
          protection_category =
            category,
          amount =
            area_km2
        )
      
      
      k <-
        k +
        1
    }
  }
  
  
  dplyr::bind_rows(
    results
  )
}



# ============================================================
# 10. LARVAL GRID-CELL PREPARATION
# ============================================================

prepare_larval_grid_cells <- function(
    point_sf) {
  
  
  point_sf <-
    make_point_sf(
      point_sf
    )
  
  
  if (
    ".point_id" %in%
    names(
      point_sf
    )
  ) {
    
    names(
      point_sf
    )[
      names(
        point_sf
      ) ==
        ".point_id"
    ] <-
      "source_point_id"
  }
  
  
  centroids <-
    point_sf |>
    dplyr::mutate(
      .point_id =
        dplyr::row_number()
    )
  
  
  buffers <-
    centroids
  
  
  sf::st_geometry(
    buffers
  ) <-
    suppressWarnings(
      sf::st_buffer(
        sf::st_geometry(
          centroids
        ),
        dist =
          LARVAL_PROTECTION_BUFFER_KM *
          1000
      )
    )
  
  
  list(
    centroids =
      centroids,
    buffers =
      buffers
  )
}



# ============================================================
# 11. POINT INDICATOR: ASSIGN CENTROIDS TO EEZ
# ============================================================


assign_points_to_eez <- function(
    point_sf) {
  
  
  point_sf <-
    make_point_sf(
      point_sf
    )
  
  
  if (
    "sovereign_state" %in%
    names(
      point_sf
    )
  ) {
    
    names(
      point_sf
    )[
      names(
        point_sf
      ) ==
        "sovereign_state"
    ] <-
      "source_sovereign_state"
  }
  
  
  if (
    !(
      ".point_id" %in%
      names(
        point_sf
      )
    )
  ) {
    
    point_sf <-
      point_sf |>
      dplyr::mutate(
        .point_id =
          dplyr::row_number()
      )
  }
  
  
  joined <-
    suppressWarnings(
      sf::st_join(
        point_sf,
        zone_eez |>
          dplyr::select(
            sovereign_state
          ),
        join =
          sf::st_intersects,
        left =
          FALSE
      )
    )
  
  
  joined |>
    dplyr::distinct(
      .point_id,
      sovereign_state,
      .keep_all = TRUE
    )
}



attach_centroid_eez_to_buffers <- function(
    buffer_sf,
    centroids_by_country) {
  
  
  ownership <-
    centroids_by_country |>
    sf::st_drop_geometry() |>
    dplyr::distinct(
      .point_id,
      sovereign_state
    )
  
  
  buffer_sf |>
    dplyr::inner_join(
      ownership,
      by =
        ".point_id"
    )
}


# ============================================================
# 12. SPECIAL FILTER: COUNTRY-SPECIFIC LARVAL q75
# ============================================================


apply_larval_country_q75 <- function(
    points_by_country,
    indicator) {
  
  
  required_fields <-
    c(
      LARVAL_INFLOW_FIELD,
      LARVAL_OUTFLOW_FIELD
    )
  
  
  missing_fields <-
    setdiff(
      required_fields,
      names(
        points_by_country
      )
    )
  
  
  if (
    length(
      missing_fields
    ) >
    0
  ) {
    
    stop(
      "Larval corridor fields are missing:\n",
      paste(
        missing_fields,
        collapse = "\n"
      ),
      "\n\nAvailable fields:\n",
      paste(
        names(
          points_by_country
        ),
        collapse = ", "
      ),
      "\n\nUpdate LARVAL_INFLOW_FIELD / LARVAL_OUTFLOW_FIELD if required."
    )
  }
  
  
  # ----------------------------------------------------------
  # Prepare numeric connectivity fields
  # ----------------------------------------------------------
  
  x <-
    points_by_country |>
    dplyr::mutate(
      
      .larval_inflow =
        suppressWarnings(
          as.numeric(
            .data[[LARVAL_INFLOW_FIELD]]
          )
        ),
      
      .larval_outflow =
        suppressWarnings(
          as.numeric(
            .data[[LARVAL_OUTFLOW_FIELD]]
          )
        )
    )
  
  
  # ----------------------------------------------------------
  # STEP 1: define ANY dispersal corridor
  # ----------------------------------------------------------
  
  corridor_points <-
    x |>
    dplyr::filter(
      !is.na(
        .larval_inflow
      ),
      !is.na(
        .larval_outflow
      ),
      .larval_inflow >
        0,
      .larval_outflow >
        0
    )
  
  all_country_counts <-
    x |>
    sf::st_drop_geometry() |>
    dplyr::group_by(
      sovereign_state
    ) |>
    dplyr::summarise(
      
      n_connectivity_points_in_eez =
        dplyr::n(),
      
      n_valid_inflow =
        sum(
          is.finite(
            .larval_inflow
          ) &
            !is.na(
              .larval_inflow
            )
        ),
      
      n_valid_outflow =
        sum(
          is.finite(
            .larval_outflow
          ) &
            !is.na(
              .larval_outflow
            )
        ),
      
      .groups =
        "drop"
    )
  
  
  # ----------------------------------------------------------
  # STEP 2: q75 from corridor reefs only, separately by country
  # ----------------------------------------------------------
  
  corridor_thresholds <-
    corridor_points |>
    sf::st_drop_geometry() |>
    dplyr::group_by(
      sovereign_state
    ) |>
    dplyr::summarise(
      
      inflow_q75_corridors =
        safe_quantile(
          .larval_inflow,
          LARVAL_INFLOW_QUANTILE
        ),
      
      n_dispersal_corridors =
        dplyr::n(),
      
      n_unique_corridor_ids =
        if (
          LARVAL_ID_FIELD %in%
          names(
            corridor_points
          )
        ) {
          
          dplyr::n_distinct(
            .data[[LARVAL_ID_FIELD]],
            na.rm = TRUE
          )
          
        } else {
          
          NA_integer_
        },
      
      .groups =
        "drop"
    )
  
  
  thresholds <-
    all_country_counts |>
    dplyr::left_join(
      corridor_thresholds,
      by =
        "sovereign_state"
    ) |>
    dplyr::mutate(
      
      n_dispersal_corridors =
        tidyr::replace_na(
          n_dispersal_corridors,
          0L
        )
    )
  
  
  corridor_points <-
    corridor_points |>
    dplyr::left_join(
      thresholds |>
        dplyr::select(
          sovereign_state,
          inflow_q75_corridors
        ),
      by =
        "sovereign_state"
    )
  
  
  if (
    LARVAL_QUANTILE_INCLUSIVE
  ) {
    
    corridor_points$.larval_key_corridor <-
      !is.na(
        corridor_points$inflow_q75_corridors
      ) &
      corridor_points$.larval_inflow >=
      corridor_points$inflow_q75_corridors
    
  } else {
    
    corridor_points$.larval_key_corridor <-
      !is.na(
        corridor_points$inflow_q75_corridors
      ) &
      corridor_points$.larval_inflow >
      corridor_points$inflow_q75_corridors
  }
  
  
  key_corridors <-
    corridor_points |>
    dplyr::filter(
      .larval_key_corridor
    )
  
  
  key_counts <-
    key_corridors |>
    sf::st_drop_geometry() |>
    dplyr::group_by(
      sovereign_state
    ) |>
    dplyr::summarise(
      
      n_key_corridor_points =
        dplyr::n(),
      
      n_unique_key_corridor_ids =
        if (
          LARVAL_ID_FIELD %in%
          names(
            key_corridors
          )
        ) {
          
          dplyr::n_distinct(
            .data[[LARVAL_ID_FIELD]],
            na.rm = TRUE
          )
          
        } else {
          
          NA_integer_
        },
      
      .groups =
        "drop"
    )
  
  
  thresholds <-
    thresholds |>
    dplyr::left_join(
      key_counts,
      by =
        "sovereign_state"
    ) |>
    dplyr::mutate(
      
      n_key_corridor_points =
        tidyr::replace_na(
          n_key_corridor_points,
          0L
        ),
      
      quantile_probability =
        LARVAL_INFLOW_QUANTILE,
      
      quantile_population =
        "dispersal corridors only: InflowP5 > 0 and OutflowP5 > 0",
      
      quantile_rule =
        if (
          LARVAL_QUANTILE_INCLUSIVE
        ) {
          ">="
        } else {
          ">"
        },
      
      inflow_field =
        LARVAL_INFLOW_FIELD,
      
      outflow_field =
        LARVAL_OUTFLOW_FIELD,
      
      source_id_field =
        LARVAL_ID_FIELD,
      
      grid_cell_width_km =
        LARVAL_GRID_CELL_WIDTH_KM,
      
      protection_buffer_km =
        LARVAL_PROTECTION_BUFFER_KM
    )
  
  
  readr::write_csv(
    thresholds,
    larval_threshold_csv
  )
  
  
  message(
    "\nLarval corridor country thresholds:"
  )
  
  
  print(
    thresholds,
    n = Inf
  )
  
  
  list(
    
    # Final denominator for Element 3:
    # highly connected / key dispersal corridors.
    points =
      key_corridors,
    
    # Positive-inflow / positive-outflow corridor population used
    # to calculate the country q75.
    corridor_points =
      corridor_points,
    
    thresholds =
      thresholds
  )
}


# ============================================================
# 13. POINT INDICATOR: CLASSIFY PROTECTION
# ============================================================

classify_points_protection <- function(
    points_by_country,
    protection_test_sf = NULL) {
  
  if (
    is.null(
      protection_test_sf
    )
  ) {
    
    protection_test_sf <-
      points_by_country
  }
  
  
  required_cols <-
    c(
      ".point_id",
      "sovereign_state"
    )
  
  
  if (
    !all(
      required_cols %in%
      names(
        points_by_country
      )
    )
  ) {
    
    stop(
      "points_by_country must contain .point_id and sovereign_state."
    )
  }
  
  
  if (
    !all(
      required_cols %in%
      names(
        protection_test_sf
      )
    )
  ) {
    
    stop(
      "protection_test_sf must contain .point_id and sovereign_state."
    )
  }
  
  
  countries <-
    unique(
      points_by_country$sovereign_state
    )
  
  
  results <-
    vector(
      "list",
      length(
        countries
      )
    )
  
  
  for (
    c_idx in
    seq_along(
      countries
    )
  ) {
    
    country <-
      countries[[c_idx]]
    
    
    denominator_country <-
      points_by_country |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    test_country <-
      protection_test_sf |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    test_country <-
      test_country |>
      dplyr::semi_join(
        denominator_country |>
          sf::st_drop_geometry() |>
          dplyr::select(
            .point_id
          ),
        by =
          ".point_id"
      )
    
    
    if (
      nrow(
        denominator_country
      ) ==
      0
    ) {
      
      next
    }
    
    
    if (
      nrow(
        test_country
      ) !=
      nrow(
        denominator_country
      )
    ) {
      
      stop(
        "Protection-test geometry count does not match denominator point count for ",
        country,
        ".\nExpected ",
        nrow(
          denominator_country
        ),
        " but found ",
        nrow(
          test_country
        ),
        "."
      )
    }
    

    test_country <-
      test_country[
        match(
          denominator_country$.point_id,
          test_country$.point_id
        ),
        ,
        drop = FALSE
      ]
    
    
    mpa_country <-
      zone_mpa |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    oecm_country <-
      zone_oecm |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    in_mpa <-
      if (
        nrow(
          mpa_country
        ) ==
        0
      ) {
        
        rep(
          FALSE,
          nrow(
            test_country
          )
        )
        
      } else {
        
        lengths(
          sf::st_intersects(
            test_country,
            mpa_country,
            sparse = TRUE
          )
        ) >
          0
      }
    
    
    in_oecm <-
      if (
        nrow(
          oecm_country
        ) ==
        0
      ) {
        
        rep(
          FALSE,
          nrow(
            test_country
          )
        )
        
      } else {
        
        lengths(
          sf::st_intersects(
            test_country,
            oecm_country,
            sparse = TRUE
          )
        ) >
          0
      }
    
    
    protection_category <-
      dplyr::case_when(
        
        in_mpa &
          in_oecm ~
          "MPA-OECM overlap",
        
        in_mpa &
          !in_oecm ~
          "MPA only",
        
        !in_mpa &
          in_oecm ~
          "OECM only",
        
        TRUE ~
          "Unprotected"
      )
    
    
    results[[c_idx]] <-
      tibble::tibble(
        
        .point_id =
          denominator_country$.point_id,
        
        sovereign_state =
          country,
        
        intersects_mpa =
          in_mpa,
        
        intersects_oecm =
          in_oecm,
        
        protection_category =
          protection_category
      )
  }
  
  
  dplyr::bind_rows(
    results
  )
}


# ============================================================
# 14. STANDARD AREA OUTPUT
# ============================================================


build_area_output <- function(
    composition_tbl,
    indicator,
    data_type,
    filter_mode,
    filter_expr) {
  
  
  total_tbl <-
    composition_tbl |>
    dplyr::filter(
      protection_category ==
        "TOTAL_INDICATOR"
    ) |>
    dplyr::transmute(
      sovereign_state,
      indicator_area_km2 =
        amount
    )
  
  
  exclusive_wide <-
    composition_tbl |>
    dplyr::filter(
      protection_category !=
        "TOTAL_INDICATOR"
    ) |>
    tidyr::complete(
      
      sovereign_state =
        eez_table$sovereign_state,
      
      protection_category =
        c(
          "MPA only",
          "OECM only",
          "MPA-OECM overlap"
        ),
      
      fill =
        list(
          amount = 0
        )
    ) |>
    tidyr::pivot_wider(
      names_from =
        protection_category,
      values_from =
        amount,
      values_fill =
        0
    ) |>
    dplyr::rename(
      
      mpa_only_indicator_area_km2 =
        `MPA only`,
      
      oecm_only_indicator_area_km2 =
        `OECM only`,
      
      overlap_indicator_area_km2 =
        `MPA-OECM overlap`
    )
  
  
  out <-
    eez_table |>
    dplyr::left_join(
      total_tbl,
      by =
        "sovereign_state"
    ) |>
    dplyr::left_join(
      exclusive_wide,
      by =
        "sovereign_state"
    ) |>
    dplyr::mutate(
      
      dplyr::across(
        c(
          indicator_area_km2,
          mpa_only_indicator_area_km2,
          oecm_only_indicator_area_km2,
          overlap_indicator_area_km2
        ),
        ~ tidyr::replace_na(
          .x,
          0
        )
      ),
      
      
      protected_indicator_area_km2 =
        mpa_only_indicator_area_km2 +
        oecm_only_indicator_area_km2 +
        overlap_indicator_area_km2,
      
      
      mpa_indicator_area_km2 =
        mpa_only_indicator_area_km2 +
        overlap_indicator_area_km2,
      
      
      oecm_indicator_area_km2 =
        oecm_only_indicator_area_km2 +
        overlap_indicator_area_km2,
      
      
      indicator_point_count =
        NA_integer_,
      
      
      protected_indicator_point_count =
        NA_integer_,
      
      
      mpa_indicator_point_count =
        NA_integer_,
      
      
      oecm_indicator_point_count =
        NA_integer_,
      
      
      mpa_only_indicator_point_count =
        NA_integer_,
      
      
      oecm_only_indicator_point_count =
        NA_integer_,
      
      
      overlap_indicator_point_count =
        NA_integer_
    )
  
  
  regional_total <-
    sum(
      out$indicator_area_km2,
      na.rm = TRUE
    )
  
  
  out |>
    dplyr::mutate(
      
      indicator =
        indicator,
      
      data_type =
        data_type,
      
      measure_type =
        "area",
      
      filter_mode =
        filter_mode,
      
      filter_expr_applied =
        if (
          is.na(
            filter_expr
          )
        ) {
          NA_character_
        } else {
          filter_expr
        },
      
      
      indicator_total_in_all_eezs_km2 =
        regional_total,
      
      
      indicator_total_points_in_all_eezs =
        NA_integer_,
      
      
      percent_eez_covered_by_indicator =
        100 *
        safe_divide(
          indicator_area_km2,
          eez_area_km2
        ),
      
      
      percent_of_indicator_in_all_eezs =
        100 *
        safe_divide(
          indicator_area_km2,
          regional_total
        ),
      
      
      percent_indicator_protected_total =
        100 *
        safe_divide(
          protected_indicator_area_km2,
          indicator_area_km2
        ),
      
      
      percent_indicator_protected_mpa =
        100 *
        safe_divide(
          mpa_indicator_area_km2,
          indicator_area_km2
        ),
      
      
      percent_indicator_protected_oecm =
        100 *
        safe_divide(
          oecm_indicator_area_km2,
          indicator_area_km2
        ),
      
      
      percent_indicator_protected_mpa_only =
        100 *
        safe_divide(
          mpa_only_indicator_area_km2,
          indicator_area_km2
        ),
      
      
      percent_indicator_protected_oecm_only =
        100 *
        safe_divide(
          oecm_only_indicator_area_km2,
          indicator_area_km2
        ),
      
      
      percent_indicator_protected_overlap =
        100 *
        safe_divide(
          overlap_indicator_area_km2,
          indicator_area_km2
        )
    )
}



# ============================================================
# 15. STANDARD POINT OUTPUT
# ============================================================


build_point_output <- function(
    points_by_country,
    indicator,
    data_type,
    filter_mode,
    filter_expr,
    protection_test_sf = NULL) {
  
  
  classification <-
    classify_points_protection(
      points_by_country =
        points_by_country,
      protection_test_sf =
        protection_test_sf
    )
  
  
  total_tbl <-
    classification |>
    dplyr::distinct(
      .point_id,
      sovereign_state
    ) |>
    dplyr::count(
      sovereign_state,
      name =
        "indicator_point_count"
    )
  
  
  protection_long <-
    classification |>
    dplyr::filter(
      protection_category !=
        "Unprotected"
    ) |>
    dplyr::count(
      sovereign_state,
      protection_category,
      name =
        "amount"
    )
  
  
  protection_wide <-
    protection_long |>
    tidyr::complete(
      
      sovereign_state =
        eez_table$sovereign_state,
      
      protection_category =
        c(
          "MPA only",
          "OECM only",
          "MPA-OECM overlap"
        ),
      
      fill =
        list(
          amount = 0L
        )
    ) |>
    tidyr::pivot_wider(
      names_from =
        protection_category,
      values_from =
        amount,
      values_fill =
        0L
    ) |>
    dplyr::rename(
      
      mpa_only_indicator_point_count =
        `MPA only`,
      
      oecm_only_indicator_point_count =
        `OECM only`,
      
      overlap_indicator_point_count =
        `MPA-OECM overlap`
    )
  
  
  out <-
    eez_table |>
    dplyr::left_join(
      total_tbl,
      by =
        "sovereign_state"
    ) |>
    dplyr::left_join(
      protection_wide,
      by =
        "sovereign_state"
    ) |>
    dplyr::mutate(
      
      dplyr::across(
        c(
          indicator_point_count,
          mpa_only_indicator_point_count,
          oecm_only_indicator_point_count,
          overlap_indicator_point_count
        ),
        ~ tidyr::replace_na(
          .x,
          0L
        )
      ),
      
      
      protected_indicator_point_count =
        mpa_only_indicator_point_count +
        oecm_only_indicator_point_count +
        overlap_indicator_point_count,
      
      
      mpa_indicator_point_count =
        mpa_only_indicator_point_count +
        overlap_indicator_point_count,
      
      
      oecm_indicator_point_count =
        oecm_only_indicator_point_count +
        overlap_indicator_point_count,
      
      
      indicator_area_km2 =
        NA_real_,
      
      
      protected_indicator_area_km2 =
        NA_real_,
      
      
      mpa_indicator_area_km2 =
        NA_real_,
      
      
      oecm_indicator_area_km2 =
        NA_real_,
      
      
      mpa_only_indicator_area_km2 =
        NA_real_,
      
      
      oecm_only_indicator_area_km2 =
        NA_real_,
      
      
      overlap_indicator_area_km2 =
        NA_real_
    )
  
  
  regional_total <-
    sum(
      out$indicator_point_count,
      na.rm = TRUE
    )
  
  
  out |>
    dplyr::mutate(
      
      indicator =
        indicator,
      
      data_type =
        data_type,
      
      measure_type =
        "points",
      
      filter_mode =
        filter_mode,
      
      filter_expr_applied =
        if (
          is.na(
            filter_expr
          )
        ) {
          NA_character_
        } else {
          filter_expr
        },
      
      
      indicator_total_in_all_eezs_km2 =
        NA_real_,
      
      
      indicator_total_points_in_all_eezs =
        regional_total,
      
      
      percent_eez_covered_by_indicator =
        NA_real_,
      
      
      percent_of_indicator_in_all_eezs =
        100 *
        safe_divide(
          indicator_point_count,
          regional_total
        ),
      
      
      percent_indicator_protected_total =
        100 *
        safe_divide(
          protected_indicator_point_count,
          indicator_point_count
        ),
      
      
      percent_indicator_protected_mpa =
        100 *
        safe_divide(
          mpa_indicator_point_count,
          indicator_point_count
        ),
      
      
      percent_indicator_protected_oecm =
        100 *
        safe_divide(
          oecm_indicator_point_count,
          indicator_point_count
        ),
      
      
      percent_indicator_protected_mpa_only =
        100 *
        safe_divide(
          mpa_only_indicator_point_count,
          indicator_point_count
        ),
      
      
      percent_indicator_protected_oecm_only =
        100 *
        safe_divide(
          oecm_only_indicator_point_count,
          indicator_point_count
        ),
      
      
      percent_indicator_protected_overlap =
        100 *
        safe_divide(
          overlap_indicator_point_count,
          indicator_point_count
        )
    )
}



# ============================================================
# 16. CACHE KEY
# ============================================================


cache_key_for_indicator <- function(
    path,
    layer,
    indicator,
    data_type,
    measure_type,
    filter_mode,
    filter_expr) {
  
  
  indicator_info <-
    file.info(
      path
    ) |>
    tibble::rownames_to_column(
      "path"
    ) |>
    dplyr::select(
      path,
      size,
      mtime
    )
  
  
  protection_info <-
    file.info(
      PROTECTION_GPKG
    ) |>
    tibble::rownames_to_column(
      "path"
    ) |>
    dplyr::select(
      path,
      size,
      mtime
    )
  
  
  digest::digest(
    list(
      
      indicator_info =
        indicator_info,
      
      protection_info =
        protection_info,
      
      layer =
        layer,
      
      indicator =
        indicator,
      
      data_type =
        data_type,
      
      measure_type =
        measure_type,
      
      filter_mode =
        filter_mode,
      
      filter_expr =
        filter_expr,
      
      excluded_sovereign_states =
        EXCLUDED_SOVEREIGN_STATES,
      
      vector_batch_size =
        VECTOR_BATCH_SIZE,
      
      larval_inflow_field =
        LARVAL_INFLOW_FIELD,
      
      larval_outflow_field =
        LARVAL_OUTFLOW_FIELD,
      
      larval_id_field =
        LARVAL_ID_FIELD,
      
      larval_grid_cell_width_km =
        LARVAL_GRID_CELL_WIDTH_KM,
      
      larval_protection_buffer_km =
        LARVAL_PROTECTION_BUFFER_KM,
      
      larval_quantile =
        LARVAL_INFLOW_QUANTILE,
      
      larval_quantile_inclusive =
        LARVAL_QUANTILE_INCLUSIVE,
      
      larval_positive_inflow =
        LARVAL_REQUIRE_POSITIVE_INFLOW,
      
      larval_positive_outflow =
        LARVAL_REQUIRE_POSITIVE_OUTFLOW,
      
      cache_version =
        CACHE_VERSION
    )
  )
}



# ============================================================
# 17. PROCESS ONE INDICATOR
# ============================================================


process_one_indicator <- function(j) {
  
  
  path <-
    indicator_inputs$path[[j]]
  
  
  layer <-
    indicator_inputs$layer[[j]]
  
  
  indicator <-
    indicator_inputs$indicator[[j]]
  
  
  data_type <-
    indicator_inputs$data_type[[j]]
  
  
  requested_measure_type <-
    indicator_inputs$measure_type[[j]]
  
  
  filter_mode <-
    indicator_inputs$filter_mode[[j]]
  
  
  filter_expr <-
    indicator_inputs$filter_expr[[j]]
  
  
  
  key <-
    cache_key_for_indicator(
      path =
        path,
      layer =
        layer,
      indicator =
        indicator,
      data_type =
        data_type,
      measure_type =
        requested_measure_type,
      filter_mode =
        filter_mode,
      filter_expr =
        filter_expr
    )
  
  
  key_short <-
    substr(
      key,
      1,
      12
    )
  
  
  cache_file <-
    file.path(
      cache_dir,
      paste0(
        clean_filename(
          indicator
        ),
        "_",
        key_short,
        ".csv"
      )
    )
  
  
  spatial_cache_gpkg <-
    file.path(
      spatial_cache_dir,
      paste0(
        clean_filename(
          indicator
        ),
        "_",
        key_short,
        ".gpkg"
      )
    )
  
  
  
  if (
    file.exists(
      cache_file
    ) &&
    !FORCE_RERUN
  ) {
    
    message(
      "\nUsing cached Element 3 result for: ",
      indicator
    )
    
    
    return(
      readr::read_csv(
        cache_file,
        show_col_types = FALSE
      )
    )
  }
  
  
  
  message(
    "\n============================================================"
  )
  
  
  message(
    "Processing Element 3 indicator: ",
    indicator
  )
  
  
  message(
    "============================================================"
  )
  
  
  
  indicator_raw <-
    timer(
      
      paste0(
        indicator,
        ": read source"
      ),
      
      read_vector_indicator(
        path =
          path,
        layer =
          layer,
        indicator =
          indicator,
        filter_expr =
          filter_expr
      )
    )
  
  
  
  if (
    nrow(
      indicator_raw
    ) ==
    0
  ) {
    
    stop(
      "No source features remain for ",
      indicator,
      "."
    )
  }
  
  
  
  final_measure_type <-
    if (
      requested_measure_type ==
      "auto"
    ) {
      
      infer_measure_type_from_sf(
        indicator_raw
      )
      
    } else {
      
      requested_measure_type
    }
  
  
  
  message(
    "Measure type used: ",
    final_measure_type
  )
  
  
  
  # ----------------------------------------------------------
  # AREA / POLYGON INDICATOR
  # ----------------------------------------------------------
  
  if (
    final_measure_type ==
    "area"
  ) {
    
    
    if (
      filter_mode !=
      "none"
    ) {
      
      stop(
        "Special filter_mode '",
        filter_mode,
        "' is currently implemented for point indicators only."
      )
    }
    
    
    if (
      file.exists(
        spatial_cache_gpkg
      ) &&
      !FORCE_RERUN
    ) {
      
      message(
        "Loading cached dissolved country geometry for ",
        indicator
      )
      
      
      indicator_by_country <-
        sf::st_read(
          spatial_cache_gpkg,
          layer =
            "indicator_by_country",
          quiet =
            TRUE
        )
      
      
    } else {
      
      
      indicator_by_country <-
        timer(
          
          paste0(
            indicator,
            ": dissolve to unique country footprints"
          ),
          
          dissolve_indicator_by_country(
            indicator_sf =
              indicator_raw,
            indicator =
              indicator,
            batch_size =
              VECTOR_BATCH_SIZE
          )
        )
      
      
      if (
        file.exists(
          spatial_cache_gpkg
        )
      ) {
        
        unlink(
          spatial_cache_gpkg
        )
      }
      
      
      sf::st_write(
        indicator_by_country,
        dsn =
          spatial_cache_gpkg,
        layer =
          "indicator_by_country",
        quiet =
          TRUE
      )
    }
    
    
    
    composition <-
      timer(
        
        paste0(
          indicator,
          ": protection composition"
        ),
        
        area_composition_from_country_indicator(
          indicator_by_country
        )
      )
    
    
    
    out <-
      build_area_output(
        composition_tbl =
          composition,
        indicator =
          indicator,
        data_type =
          data_type,
        filter_mode =
          filter_mode,
        filter_expr =
          filter_expr
      )
    
    
    
    rm(
      indicator_by_country,
      composition
    )
    
    
    gc(
      verbose = FALSE
    )
    
    
    
    # ----------------------------------------------------------
    # POINT INDICATOR
    # ----------------------------------------------------------
    
  } else if (
    final_measure_type ==
    "points"
  ) {
    
    
    # --------------------------------------------------------
    # LARVAL CONNECTIVITY:
    # create 4 km grid-cell buffers FIRST
    # --------------------------------------------------------
    
    if (
      filter_mode ==
      "larval_country_q75"
    ) {
      
      
      larval_grid <-
        timer(
          
          paste0(
            indicator,
            ": create 4 km grid-cell buffers"
          ),
          
          prepare_larval_grid_cells(
            indicator_raw
          )
        )
      
      
      source_centroids <-
        larval_grid$centroids
      
      
      source_buffers <-
        larval_grid$buffers
      
      
      if (
        file.exists(
          spatial_cache_gpkg
        )
      ) {
        
        unlink(
          spatial_cache_gpkg
        )
      }
      
      
      sf::st_write(
        source_buffers,
        dsn =
          spatial_cache_gpkg,
        layer =
          "connectivity_grid_buffers_4km_all",
        quiet =
          TRUE
      )
      
      
      points_by_country <-
        timer(
          
          paste0(
            indicator,
            ": assign centroid ownership to sovereign EEZ"
          ),
          
          assign_points_to_eez(
            source_centroids
          )
        )
      
      
      buffers_by_country <-
        attach_centroid_eez_to_buffers(
          buffer_sf =
            source_buffers,
          centroids_by_country =
            points_by_country
        )
      
      
      sf::st_write(
        points_by_country,
        dsn =
          spatial_cache_gpkg,
        layer =
          "connectivity_centroids_by_country",
        append =
          FALSE,
        delete_layer =
          TRUE,
        quiet =
          TRUE
      )
      
      
      sf::st_write(
        buffers_by_country,
        dsn =
          spatial_cache_gpkg,
        layer =
          "connectivity_grid_buffers_4km_by_country",
        append =
          FALSE,
        delete_layer =
          TRUE,
        quiet =
          TRUE
      )
      
      
      # ------------------------------------------------------
      # Corridor -> country q75 -> key corridors
      # ------------------------------------------------------
      
      larval_result <-
        apply_larval_country_q75(
          points_by_country =
            points_by_country,
          indicator =
            indicator
        )
      
      
      analysis_points <-
        larval_result$points
      
      
      corridor_points <-
        larval_result$corridor_points
      
      
      corridor_buffers <-
        buffers_by_country |>
        dplyr::semi_join(
          corridor_points |>
            sf::st_drop_geometry() |>
            dplyr::select(
              .point_id,
              sovereign_state
            ),
          by =
            c(
              ".point_id",
              "sovereign_state"
            )
        )
      
      
      analysis_buffers <-
        buffers_by_country |>
        dplyr::semi_join(
          analysis_points |>
            sf::st_drop_geometry() |>
            dplyr::select(
              .point_id,
              sovereign_state
            ),
          by =
            c(
              ".point_id",
              "sovereign_state"
            )
        )
      
      
      sf::st_write(
        corridor_points,
        dsn =
          spatial_cache_gpkg,
        layer =
          "dispersal_corridor_centroids_all",
        append =
          FALSE,
        delete_layer =
          TRUE,
        quiet =
          TRUE
      )
      
      
      sf::st_write(
        corridor_buffers,
        dsn =
          spatial_cache_gpkg,
        layer =
          "dispersal_corridor_buffers_4km_all",
        append =
          FALSE,
        delete_layer =
          TRUE,
        quiet =
          TRUE
      )
      
      
      sf::st_write(
        analysis_points,
        dsn =
          spatial_cache_gpkg,
        layer =
          "key_dispersal_corridor_centroids_q75",
        append =
          FALSE,
        delete_layer =
          TRUE,
        quiet =
          TRUE
      )
      
      
      sf::st_write(
        analysis_buffers,
        dsn =
          spatial_cache_gpkg,
        layer =
          "key_dispersal_corridor_buffers_4km_q75",
        append =
          FALSE,
        delete_layer =
          TRUE,
        quiet =
          TRUE
      )
      
      
      out <-
        build_point_output(
          points_by_country =
            analysis_points,
          indicator =
            indicator,
          data_type =
            data_type,
          filter_mode =
            filter_mode,
          filter_expr =
            filter_expr,
          protection_test_sf =
            analysis_buffers
        )
      
      
      rm(
        larval_grid,
        source_centroids,
        source_buffers,
        points_by_country,
        buffers_by_country,
        corridor_points,
        corridor_buffers,
        analysis_points,
        analysis_buffers
      )
      
      
      
    } else if (
      filter_mode ==
      "none"
    ) {
      
      
      points_by_country <-
        timer(
          
          paste0(
            indicator,
            ": assign points to sovereign EEZ"
          ),
          
          assign_points_to_eez(
            indicator_raw
          )
        )
      
      
      if (
        nrow(
          points_by_country
        ) ==
        0
      ) {
        
        stop(
          "No ",
          indicator,
          " points fall inside the retained sovereign EEZs."
        )
      }
      
      
      if (
        file.exists(
          spatial_cache_gpkg
        )
      ) {
        
        unlink(
          spatial_cache_gpkg
        )
      }
      
      
      sf::st_write(
        points_by_country,
        dsn =
          spatial_cache_gpkg,
        layer =
          "points_by_country",
        quiet =
          TRUE
      )
      
      
      out <-
        build_point_output(
          points_by_country =
            points_by_country,
          indicator =
            indicator,
          data_type =
            data_type,
          filter_mode =
            filter_mode,
          filter_expr =
            filter_expr,
          protection_test_sf =
            NULL
        )
      
      
      rm(
        points_by_country
      )
      
      
    } else {
      
      
      stop(
        "Unknown point filter_mode: ",
        filter_mode
      )
    }
    
    
    gc(
      verbose = FALSE
    )
    
    
  } else {
    
    
    stop(
      "Unsupported measure_type: ",
      final_measure_type,
      "\nMarine migration corridors may require a new measure type if supplied as lines."
    )
  }
  
  
  
  # ----------------------------------------------------------
  # Standard column order
  # ----------------------------------------------------------
  
  out <-
    out |>
    dplyr::select(
      
      sovereign_state,
      
      indicator,
      
      data_type,
      
      measure_type,
      
      filter_mode,
      
      filter_expr_applied,
      
      eez_area_km2,
      
      
      # Total indicator
      indicator_area_km2,
      
      indicator_point_count,
      
      
      # Total unique protection
      protected_indicator_area_km2,
      
      protected_indicator_point_count,
      
      
      # Inclusive MPA / OECM totals
      mpa_indicator_area_km2,
      
      oecm_indicator_area_km2,
      
      mpa_indicator_point_count,
      
      oecm_indicator_point_count,
      
      
      # Mutually exclusive components
      mpa_only_indicator_area_km2,
      
      oecm_only_indicator_area_km2,
      
      overlap_indicator_area_km2,
      
      mpa_only_indicator_point_count,
      
      oecm_only_indicator_point_count,
      
      overlap_indicator_point_count,
      
      
      # Regional totals
      indicator_total_in_all_eezs_km2,
      
      indicator_total_points_in_all_eezs,
      
      
      # Percentages
      percent_eez_covered_by_indicator,
      
      percent_of_indicator_in_all_eezs,
      
      percent_indicator_protected_total,
      
      percent_indicator_protected_mpa,
      
      percent_indicator_protected_oecm,
      
      percent_indicator_protected_mpa_only,
      
      percent_indicator_protected_oecm_only,
      
      percent_indicator_protected_overlap
    )
  
  
  
  readr::write_csv(
    out,
    cache_file
  )
  
  
  
  message(
    "Completed and cached: ",
    indicator
  )
  
  
  
  if (
    exists(
      "indicator_raw",
      inherits = FALSE
    )
  ) {
    
    rm(
      indicator_raw
    )
  }
  
  
  gc(
    verbose = FALSE
  )
  
  
  out
}



# ============================================================
# 18. RUN INDICATORS SEQUENTIALLY
# ============================================================


indicator_results <-
  vector(
    "list",
    nrow(
      indicator_inputs
    )
  )



for (
  j in
  seq_len(
    nrow(
      indicator_inputs
    )
  )
) {
  
  
  indicator_results[[j]] <-
    list(
      process_one_indicator(
        j
      )
    )
  
  
  gc(
    verbose = FALSE
  )
}



# ============================================================
# 19. COMBINE COUNTRY RESULTS
# ============================================================


country_summary <-
  dplyr::bind_rows(
    indicator_results
  ) |>
  dplyr::arrange(
    indicator,
    sovereign_state
  )



# ============================================================
# 20. ADD WIO REGIONAL ROW
# ============================================================


wio_rows <-
  country_summary |>
  dplyr::group_by(
    indicator,
    data_type,
    measure_type,
    filter_mode,
    filter_expr_applied
  ) |>
  dplyr::summarise(
    
    sovereign_state =
      "WIO",
    
    
    eez_area_km2 =
      sum_or_na(
        eez_area_km2
      ),
    
    
    indicator_area_km2 =
      sum_or_na(
        indicator_area_km2
      ),
    
    
    indicator_point_count =
      sum_int_or_na(
        indicator_point_count
      ),
    
    
    protected_indicator_area_km2 =
      sum_or_na(
        protected_indicator_area_km2
      ),
    
    
    protected_indicator_point_count =
      sum_int_or_na(
        protected_indicator_point_count
      ),
    
    
    mpa_indicator_area_km2 =
      sum_or_na(
        mpa_indicator_area_km2
      ),
    
    
    oecm_indicator_area_km2 =
      sum_or_na(
        oecm_indicator_area_km2
      ),
    
    
    mpa_indicator_point_count =
      sum_int_or_na(
        mpa_indicator_point_count
      ),
    
    
    oecm_indicator_point_count =
      sum_int_or_na(
        oecm_indicator_point_count
      ),
    
    
    mpa_only_indicator_area_km2 =
      sum_or_na(
        mpa_only_indicator_area_km2
      ),
    
    
    oecm_only_indicator_area_km2 =
      sum_or_na(
        oecm_only_indicator_area_km2
      ),
    
    
    overlap_indicator_area_km2 =
      sum_or_na(
        overlap_indicator_area_km2
      ),
    
    
    mpa_only_indicator_point_count =
      sum_int_or_na(
        mpa_only_indicator_point_count
      ),
    
    
    oecm_only_indicator_point_count =
      sum_int_or_na(
        oecm_only_indicator_point_count
      ),
    
    
    overlap_indicator_point_count =
      sum_int_or_na(
        overlap_indicator_point_count
      ),
    
    
    indicator_total_in_all_eezs_km2 =
      dplyr::first(
        indicator_total_in_all_eezs_km2
      ),
    
    
    indicator_total_points_in_all_eezs =
      dplyr::first(
        indicator_total_points_in_all_eezs
      ),
    
    
    .groups =
      "drop"
  ) |>
  dplyr::mutate(
    
    
    percent_eez_covered_by_indicator =
      dplyr::if_else(
        measure_type ==
          "area",
        100 *
          safe_divide(
            indicator_area_km2,
            eez_area_km2
          ),
        NA_real_
      ),
    
    
    percent_of_indicator_in_all_eezs =
      dplyr::case_when(
        
        measure_type ==
          "area" ~
          100 *
          safe_divide(
            indicator_area_km2,
            indicator_total_in_all_eezs_km2
          ),
        
        measure_type ==
          "points" ~
          100 *
          safe_divide(
            indicator_point_count,
            indicator_total_points_in_all_eezs
          ),
        
        TRUE ~
          NA_real_
      ),
    
    
    percent_indicator_protected_total =
      dplyr::case_when(
        
        measure_type ==
          "area" ~
          100 *
          safe_divide(
            protected_indicator_area_km2,
            indicator_area_km2
          ),
        
        measure_type ==
          "points" ~
          100 *
          safe_divide(
            protected_indicator_point_count,
            indicator_point_count
          ),
        
        TRUE ~
          NA_real_
      ),
    
    
    percent_indicator_protected_mpa =
      dplyr::case_when(
        
        measure_type ==
          "area" ~
          100 *
          safe_divide(
            mpa_indicator_area_km2,
            indicator_area_km2
          ),
        
        measure_type ==
          "points" ~
          100 *
          safe_divide(
            mpa_indicator_point_count,
            indicator_point_count
          ),
        
        TRUE ~
          NA_real_
      ),
    
    
    percent_indicator_protected_oecm =
      dplyr::case_when(
        
        measure_type ==
          "area" ~
          100 *
          safe_divide(
            oecm_indicator_area_km2,
            indicator_area_km2
          ),
        
        measure_type ==
          "points" ~
          100 *
          safe_divide(
            oecm_indicator_point_count,
            indicator_point_count
          ),
        
        TRUE ~
          NA_real_
      ),
    
    
    percent_indicator_protected_mpa_only =
      dplyr::case_when(
        
        measure_type ==
          "area" ~
          100 *
          safe_divide(
            mpa_only_indicator_area_km2,
            indicator_area_km2
          ),
        
        measure_type ==
          "points" ~
          100 *
          safe_divide(
            mpa_only_indicator_point_count,
            indicator_point_count
          ),
        
        TRUE ~
          NA_real_
      ),
    
    
    percent_indicator_protected_oecm_only =
      dplyr::case_when(
        
        measure_type ==
          "area" ~
          100 *
          safe_divide(
            oecm_only_indicator_area_km2,
            indicator_area_km2
          ),
        
        measure_type ==
          "points" ~
          100 *
          safe_divide(
            oecm_only_indicator_point_count,
            indicator_point_count
          ),
        
        TRUE ~
          NA_real_
      ),
    
    
    percent_indicator_protected_overlap =
      dplyr::case_when(
        
        measure_type ==
          "area" ~
          100 *
          safe_divide(
            overlap_indicator_area_km2,
            indicator_area_km2
          ),
        
        measure_type ==
          "points" ~
          100 *
          safe_divide(
            overlap_indicator_point_count,
            indicator_point_count
          ),
        
        TRUE ~
          NA_real_
      )
  ) |>
  dplyr::select(
    names(
      country_summary
    )
  )



final_summary <-
  dplyr::bind_rows(
    country_summary,
    wio_rows
  ) |>
  dplyr::arrange(
    indicator,
    sovereign_state
  )



# ============================================================
# 21. STACKED-BAR DATA
# ============================================================


composition_long <-
  final_summary |>
  dplyr::select(
    
    sovereign_state,
    
    indicator,
    
    measure_type,
    
    percent_indicator_protected_mpa_only,
    
    percent_indicator_protected_oecm_only,
    
    percent_indicator_protected_overlap
  ) |>
  tidyr::pivot_longer(
    
    cols =
      c(
        percent_indicator_protected_mpa_only,
        percent_indicator_protected_oecm_only,
        percent_indicator_protected_overlap
      ),
    
    names_to =
      "protection_category",
    
    values_to =
      "percent_indicator"
  ) |>
  dplyr::mutate(
    
    protection_category =
      dplyr::recode(
        
        protection_category,
        
        percent_indicator_protected_mpa_only =
          "MPA only",
        
        percent_indicator_protected_oecm_only =
          "OECM only",
        
        percent_indicator_protected_overlap =
          "MPA-OECM overlap"
      ),
    
    
    protection_category =
      factor(
        protection_category,
        levels =
          c(
            "MPA only",
            "OECM only",
            "MPA-OECM overlap"
          )
      )
  )



composition_long_csv <-
  file.path(
    out_dir,
    "element3_indicator_protection_composition_long.csv"
  )



readr::write_csv(
  composition_long,
  composition_long_csv
)



# ============================================================
# 24. SAVE FINAL OUTPUT
# ============================================================


out_csv <-
  file.path(
    out_dir,
    "wio_element3_indicator_protection_by_sovereign.csv"
  )



readr::write_csv(
  final_summary,
  out_csv
)



message(
  "\n============================================================"
)


message(
  "ELEMENT 3 COMPLETE"
)


message(
  "============================================================"
)



message(
  "\nMain summary:"
)


message(
  normalizePath(
    out_csv
  )
)



message(
  "\nStacked-bar data:"
)


message(
  normalizePath(
    composition_long_csv
  )
)



message(
  "\nExclusive protection zones:"
)


message(
  normalizePath(
    exclusive_gpkg
  )
)



if (
  file.exists(
    larval_threshold_csv
  )
) {
  
  message(
    "\nLarval q75 thresholds:"
  )
  
  
  message(
    normalizePath(
      larval_threshold_csv
    )
  )
}



message(
  "\nPlots:"
)


message(
  normalizePath(
    plot_dir
  )
)



print(
  final_summary,
  n = Inf
)



message(
  "\nDone."
)
