# ============================================================
# ELEMENT 2
# WIO ecological representativeness
#
# Outputs:
#   1. Habitat protection by sovereign state
#   2. Exclusive protection composition:
#        - MPA only
#        - OECM only
#        - MPA-OECM overlap
#   3. Habitat amount in each individual MPA
#   4. Gini coefficient by country x habitat
#
# IMPORTANT:
#   - Protection layers are loaded from the FILTERED Element 1 GPKG.
# ============================================================

rm(list = ls())


# ------------------------------------------------------------
# 1. Packages
# ------------------------------------------------------------

pkgs <- c(
  "sf",
  "terra",
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

missing_pkgs <- pkgs[
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

sf::sf_use_s2(FALSE)

terra::terraOptions(
  threads = TRUE,
  progress = 1,
  memfrac = 0.6
)


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

MPA_UNIQUE_LAYER <-
  "mpa_unique_by_country"

OECM_UNIQUE_LAYER <-
  "oecm_unique_by_country"

MPA_INDIVIDUAL_LAYER <-
  "mpa_by_country_individual"


# ------------------------------------------------------------
# 2b. Individual MPA identity used for Gini
# ------------------------------------------------------------


MPA_OFFICIAL_ID_COL <-
  "IDN"


# ------------------------------------------------------------
# 2c. Sovereign states excluded from Elements 2 onward
# ------------------------------------------------------------
#
# "Disputed" is retained in the Element 1 master database but is
# excluded completely from Element 2 and all downstream analyses.
# ------------------------------------------------------------

EXCLUDED_SOVEREIGN_STATES <-
  c(
    "Disputed"
  )


# ------------------------------------------------------------
# 2d. Gini plot settings
# ------------------------------------------------------------
#
# TRUE adds the distribution of MPA area among MPAs as an
# additional "MPA area" column in the FIGURE ONLY, matching the
# older plotting approach. The main habitat Gini CSV remains
# habitat-only.
# ------------------------------------------------------------

INCLUDE_MPA_AREA_IN_GINI_PLOT <-
  TRUE


GINI_COUNTRY_ORDER <-
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


GINI_HABITAT_ORDER <-
  c(
    "Seagrass",
    "Coral",
    "Mangroves",
    "Seamounts",
    "MPA area"
  )


# ------------------------------------------------------------
# 2e. Habitat inputs
# ------------------------------------------------------------

indicator_inputs <- tibble::tribble(
  ~path, ~layer, ~indicator, ~data_type, ~measure_type, ~filter_expr,
  
  # "indicators/WIO_Mangroves_WCMC/WIO_Mangrove.shp",
  # NA_character_,
  # "Mangroves",
  # "auto",
  # "area",
  # NA_character_,
  # 
  # "indicators/WIO_Geomorphic/Seamounts.shp",
  # NA_character_,
  # "Seamounts",
  # "auto",
  # "area",
  # NA_character_,
  
  "indicators/wio_coral_allen_wcmc/wio_coral_allen_wcmc.shp", 
  NA_character_,
  "Coral",
  "auto",
  "area",
  NA_character_,

  "indicators/GlobalSeagrass2023_2024/GlobalSeagrass2023_2024_WIO_EEZmasked.tif",   
  NA_character_,
  "Seagrass",
  "raster",
  "area",
  NA_character_
)

SOURCE_INDICATOR_CRS_IF_MISSING <-
  NA_character_


# ------------------------------------------------------------
# 2f. Raster settings
# ------------------------------------------------------------

RASTER_PRESENCE_RULE <-
  "nonzero"

RASTER_LAYER_INDEX <-
  1


# ------------------------------------------------------------
# 2g. Vector memory settings
# ------------------------------------------------------------
#
# All polygon habitats are reduced to ONE unique habitat
# footprint per sovereign state before the protection overlays.
#
# Coral gets a smaller batch size because it is the heavy layer.
# ------------------------------------------------------------

VECTOR_BATCH_SIZE <-
  2000

CORAL_BATCH_SIZE <-
  500


# ------------------------------------------------------------
# 2h. Gini settings
# ------------------------------------------------------------

GINI_INCLUDE_ZERO_MPAS <-
  TRUE


# ------------------------------------------------------------
# 2i. Outputs / cache
# ------------------------------------------------------------

out_dir <-
  file.path(
    "outputs",
    "element2"
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
    "element2_protection_exclusive_zones.gpkg"
  )

FORCE_RERUN <-
  FALSE

CACHE_VERSION <-
  "element2_filtered_mpa_oecm_exclusive_v2_no_disputed"


# ============================================================
# 3. BASIC HELPERS
# ============================================================

timer <- function(label, expr) {
  
  message(
    "\n--- ",
    label,
    " ---"
  )
  
  t <- system.time(
    out <- force(expr)
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


safe_divide <- function(num, den) {
  
  ifelse(
    !is.na(den) &
      den > 0,
    num / den,
    NA_real_
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
    !(sovereign_col %in% names(x))
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
    n_removed > 0
  ) {
    
    message(
      "Excluded ",
      n_removed,
      " row(s) from ",
      sovereign_col,
      ": ",
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


sum_or_na <- function(x) {
  
  if (all(is.na(x))) {
    return(NA_real_)
  }
  
  sum(
    x,
    na.rm = TRUE
  )
}


sum_int_or_na <- function(x) {
  
  if (all(is.na(x))) {
    return(NA_integer_)
  }
  
  as.integer(
    sum(
      x,
      na.rm = TRUE
    )
  )
}


read_sf_any <- function(path, layer = NA_character_) {
  
  layer_missing <-
    is.null(layer) ||
    length(layer) == 0 ||
    is.na(layer) ||
    !nzchar(layer)
  
  if (!file.exists(path)) {
    stop(
      "File not found: ",
      path
    )
  }
  
  if (layer_missing) {
    
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


read_required_gpkg_layer <- function(gpkg, layer) {
  
  available_layers <-
    sf::st_layers(
      gpkg
    )$name
  
  if (!(layer %in% available_layers)) {
    
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
  
  if (!inherits(x, "sf")) {
    stop(
      "make_valid_polygonal() expects an sf object."
    )
  }
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  x <-
    suppressWarnings(
      sf::st_make_valid(x)
    )
  
  x <-
    x[
      !sf::st_is_empty(x),
      ,
      drop = FALSE
    ]
  
  if (nrow(x) == 0) {
    return(x)
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
      !sf::st_is_empty(x),
      ,
      drop = FALSE
    ]
  
  if (nrow(x) == 0) {
    return(x)
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
  
  if (!inherits(x, "sf")) {
    stop(
      "make_point_sf() expects an sf object."
    )
  }
  
  if (nrow(x) == 0) {
    return(x)
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
      "Point indicator still contains non-point geometries: ",
      paste(
        geom_types,
        collapse = ", "
      )
    )
  }
  
  x[
    !sf::st_is_empty(x),
    ,
    drop = FALSE
  ]
}


apply_optional_filter <- function(x, filter_expr, indicator) {
  
  no_filter <-
    is.null(filter_expr) ||
    length(filter_expr) == 0 ||
    is.na(filter_expr) ||
    !nzchar(
      stringr::str_squish(
        filter_expr
      )
    )
  
  if (no_filter) {
    return(x)
  }
  
  message(
    "Applying habitat filter for ",
    indicator,
    ": ",
    filter_expr
  )
  
  expr <-
    rlang::parse_expr(
      filter_expr
    )
  
  dplyr::filter(
    x,
    !!expr
  )
}


infer_data_type <- function(path, data_type = "auto") {
  
  data_type <-
    stringr::str_to_lower(
      data_type
    )
  
  if (
    data_type %in%
    c(
      "vector",
      "raster"
    )
  ) {
    return(data_type)
  }
  
  ext <-
    stringr::str_to_lower(
      tools::file_ext(
        path
      )
    )
  
  if (
    ext %in%
    c(
      "shp",
      "gpkg",
      "geojson",
      "json"
    )
  ) {
    return("vector")
  }
  
  if (
    ext %in%
    c(
      "vrt",
      "tif",
      "tiff",
      "img",
      "grd",
      "nc"
    )
  ) {
    return("raster")
  }
  
  stop(
    "Could not infer data type for: ",
    path
  )
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
    return("points")
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
    return("area")
  }
  
  stop(
    "Could not infer measure type from: ",
    paste(
      geom_types,
      collapse = ", "
    )
  )
}


# ============================================================
# 4. CHECK INPUTS
# ============================================================

if (!file.exists(PROTECTION_GPKG)) {
  
  stop(
    "Filtered Element 1 GeoPackage not found:\n",
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
    MPA_UNIQUE_LAYER,
    OECM_UNIQUE_LAYER,
    MPA_INDIVIDUAL_LAYER
  )

missing_protection_layers <-
  setdiff(
    required_protection_layers,
    available_protection_layers
  )

if (length(missing_protection_layers) > 0) {
  
  stop(
    "The filtered Element 1 GeoPackage is missing required layers:\n",
    paste(
      missing_protection_layers,
      collapse = "\n"
    ),
    "\n\nAvailable layers are:\n",
    paste(
      available_protection_layers,
      collapse = "\n"
    )
  )
}

missing_indicator_files <-
  indicator_inputs |>
  dplyr::filter(
    !file.exists(path)
  )

if (
  nrow(
    missing_indicator_files
  ) > 0
) {
  
  stop(
    "Missing habitat files:\n",
    paste(
      missing_indicator_files$path,
      collapse = "\n"
    )
  )
}


indicator_inputs <-
  indicator_inputs |>
  dplyr::mutate(
    
    data_type =
      purrr::map2_chr(
        path,
        data_type,
        infer_data_type
      ),
    
    measure_type =
      stringr::str_to_lower(
        measure_type
      )
  )


message(
  "\nHabitats to process:"
)

print(
  indicator_inputs
)


# ============================================================
# 5. LOAD FILTERED ELEMENT 1 LAYERS
# ============================================================

eez_by_country <-
  timer(
    "Load EEZ by country",
    read_required_gpkg_layer(
      PROTECTION_GPKG,
      EEZ_LAYER
    )
  ) |>
  exclude_sovereign_states()

ANALYSIS_CRS <-
  sf::st_crs(
    eez_by_country
  )

if (is.na(ANALYSIS_CRS)) {
  stop(
    "eez_by_country has no CRS."
  )
}


if (
  !(
    "sovereign_state" %in%
    names(
      eez_by_country
    )
  )
) {
  stop(
    "eez_by_country is missing sovereign_state."
  )
}


if (
  !(
    "eez_area_km2" %in%
    names(
      eez_by_country
    )
  )
) {
  
  eez_by_country$eez_area_km2 <-
    as.numeric(
      sf::st_area(
        eez_by_country
      )
    ) /
    1e6
}


eez_by_country <-
  eez_by_country |>
  dplyr::select(
    sovereign_state,
    eez_area_km2
  )


protected_unique_by_country <-
  timer(
    "Load filtered combined MPA + OECM footprint",
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


mpa_unique_by_country <-
  timer(
    "Load filtered MPA footprint",
    read_required_gpkg_layer(
      PROTECTION_GPKG,
      MPA_UNIQUE_LAYER
    ) |>
      sf::st_transform(
        ANALYSIS_CRS
      ) |>
      dplyr::select(
        sovereign_state
      )
  ) |>
  exclude_sovereign_states()


oecm_unique_by_country <-
  timer(
    "Load filtered OECM footprint",
    read_required_gpkg_layer(
      PROTECTION_GPKG,
      OECM_UNIQUE_LAYER
    ) |>
      sf::st_transform(
        ANALYSIS_CRS
      ) |>
      dplyr::select(
        sovereign_state
      )
  ) |>
  exclude_sovereign_states()


mpa_individual_raw <-
  timer(
    "Load filtered individual MPAs",
    read_required_gpkg_layer(
      PROTECTION_GPKG,
      MPA_INDIVIDUAL_LAYER
    ) |>
      sf::st_transform(
        ANALYSIS_CRS
      )
  ) |>
  exclude_sovereign_states()


# ============================================================
# 6. PREPARE INDIVIDUAL MPAs FOR GINI
# ============================================================

if (
  !(
    "sovereign_state" %in%
    names(
      mpa_individual_raw
    )
  )
) {
  
  stop(
    "mpa_by_country_individual is missing sovereign_state."
  )
}


if (
  !is.na(
    MPA_OFFICIAL_ID_COL
  )
) {
  
  if (
    !(
      MPA_OFFICIAL_ID_COL %in%
      names(
        mpa_individual_raw
      )
    )
  ) {
    
    stop(
      "MPA_OFFICIAL_ID_COL not found: ",
      MPA_OFFICIAL_ID_COL,
      "\n\nAvailable columns:\n",
      paste(
        names(
          mpa_individual_raw
        ),
        collapse = ", "
      )
    )
  }
  
  mpa_individual_raw <-
    mpa_individual_raw |>
    dplyr::mutate(
      mpa_id =
        as.character(
          .data[[MPA_OFFICIAL_ID_COL]]
        )
    )
  
} else {
  
  if (
    !(
      "analysis_pa_id" %in%
      names(
        mpa_individual_raw
      )
    )
  ) {
    
    stop(
      "No MPA_OFFICIAL_ID_COL was supplied and ",
      "analysis_pa_id is absent from the Element 1 MPA layer."
    )
  }
  
  mpa_individual_raw <-
    mpa_individual_raw |>
    dplyr::mutate(
      mpa_id =
        as.character(
          analysis_pa_id
        )
    )
}


mpa_individual_raw <-
  mpa_individual_raw |>
  dplyr::filter(
    !is.na(
      mpa_id
    ),
    mpa_id !=
      ""
  ) |>
  dplyr::mutate(
    country_mpa_id =
      paste(
        sovereign_state,
        mpa_id,
        sep = "__"
      )
  )


# Recombine pieces from the same real/source MPA within a country.
mpa_individual <-
  mpa_individual_raw |>
  dplyr::select(
    sovereign_state,
    mpa_id,
    country_mpa_id
  ) |>
  dplyr::group_by(
    sovereign_state,
    mpa_id,
    country_mpa_id
  ) |>
  dplyr::summarise(
    .groups = "drop"
  ) |>
  make_valid_polygonal()


mpa_base_table <-
  mpa_individual |>
  sf::st_drop_geometry() |>
  dplyr::distinct(
    sovereign_state,
    mpa_id,
    country_mpa_id
  )


message(
  "\nFiltered individual MPAs used for Gini: ",
  nrow(
    mpa_base_table
  )
)


# ============================================================
# 7. CREATE MUTUALLY EXCLUSIVE PROTECTION ZONES
# ============================================================
#
# These three categories partition the combined protected area:
#
#   MPA only
#   OECM only
#   MPA-OECM overlap
#
# Therefore:
#
# protected total =
#   MPA only + OECM only + overlap
#
# and:
#
# total MPA =
#   MPA only + overlap
#
# total OECM =
#   OECM only + overlap
#
# ============================================================

create_exclusive_protection_zones <- function(
    eez_sf,
    mpa_sf,
    oecm_sf) {
  
  out_list <-
    list()
  
  k <-
    1
  
  countries <-
    eez_sf$sovereign_state
  
  for (country in countries) {
    
    message(
      "Building exclusive protection zones: ",
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
    
    
    if (has_mpa) {
      
      mpa_geom <-
        sf::st_union(
          sf::st_geometry(
            mpa_country
          )
        )
    }
    
    
    if (has_oecm) {
      
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
      
      overlap_geom <-
        suppressWarnings(
          sf::st_intersection(
            mpa_geom,
            oecm_geom
          )
        )
      
      mpa_only_geom <-
        suppressWarnings(
          sf::st_difference(
            mpa_geom,
            oecm_geom
          )
        )
      
      oecm_only_geom <-
        suppressWarnings(
          sf::st_difference(
            oecm_geom,
            mpa_geom
          )
        )
      
      
      pieces <-
        list(
          "MPA only" =
            mpa_only_geom,
          "OECM only" =
            oecm_only_geom,
          "MPA-OECM overlap" =
            overlap_geom
        )
      
    } else if (has_mpa) {
      
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
        length(g) == 0 ||
        all(
          sf::st_is_empty(g)
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
        ) == 0
      ) {
        next
      }
      
      # Re-dissolve in case make_valid created multiple pieces.
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
      
      out_list[[k]] <-
        list(
          temp
        )
      
      k <-
        k + 1
    }
  }
  
  
  if (
    length(
      out_list
    ) == 0
  ) {
    
    stop(
      "No exclusive protection zones could be created."
    )
  }
  
  
  dplyr::bind_rows(
    out_list
  )
}


protection_exclusive <-
  timer(
    "Create MPA-only / OECM-only / overlap zones",
    create_exclusive_protection_zones(
      eez_sf =
        eez_by_country,
      mpa_sf =
        mpa_unique_by_country,
      oecm_sf =
        oecm_unique_by_country
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


exclusive_area_check <-
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
    .groups =
      "drop"
  )


protected_area_check <-
  protected_unique_by_country |>
  dplyr::mutate(
    protected_area_km2_check =
      as.numeric(
        sf::st_area(
          protected_unique_by_country
        )
      ) /
      1e6
  ) |>
  sf::st_drop_geometry() |>
  dplyr::select(
    sovereign_state,
    protected_area_km2_check
  )


# exclusive_area_qa <-
#   protected_area_check |>
#   dplyr::left_join(
#     exclusive_area_check,
#     by =
#       "sovereign_state"
#   ) |>
#   dplyr::mutate(
#     exclusive_area_km2 =
#       tidyr::replace_na(
#         exclusive_area_km2,
#         0
#       ),
#     difference_km2 =
#       protected_area_km2_check -
#       exclusive_area_km2
#   ) |>
#   dplyr::filter(
#     abs(
#       difference_km2
#     ) >
#       0.001
#   )
# 
# 
# if (
#   nrow(
#     exclusive_area_qa
#   ) >
#   0
# ) {
#   
#   warning(
#     "Exclusive MPA/OECM categories do not reconstruct the Element 1 combined footprint for some countries."
#   )
#   
#   print(
#     exclusive_area_qa
#   )
# }


# ============================================================
# 8. OVERALL EEZ PROTECTION COMPOSITION
# ============================================================

eez_table <-
  eez_by_country |>
  sf::st_drop_geometry() |>
  dplyr::select(
    sovereign_state,
    eez_area_km2
  )


overall_composition <-
  protection_exclusive |>
  sf::st_drop_geometry() |>
  dplyr::select(
    sovereign_state,
    protection_category,
    area_km2
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
        area_km2 = 0
      )
  ) |>
  dplyr::left_join(
    eez_table,
    by =
      "sovereign_state"
  ) |>
  dplyr::mutate(
    percent_eez =
      100 *
      safe_divide(
        area_km2,
        eez_area_km2
      )
  )


wio_eez_area <-
  sum(
    eez_table$eez_area_km2,
    na.rm = TRUE
  )


overall_wio <-
  overall_composition |>
  dplyr::group_by(
    protection_category
  ) |>
  dplyr::summarise(
    sovereign_state =
      "WIO",
    area_km2 =
      sum(
        area_km2,
        na.rm = TRUE
      ),
    eez_area_km2 =
      wio_eez_area,
    .groups =
      "drop"
  ) |>
  dplyr::mutate(
    percent_eez =
      100 *
      safe_divide(
        area_km2,
        eez_area_km2
      )
  )


overall_composition <-
  dplyr::bind_rows(
    overall_composition,
    overall_wio
  )


readr::write_csv(
  overall_composition,
  file.path(
    out_dir,
    "element2_overall_protection_composition.csv"
  )
)


overall_plot_data <-
  overall_composition |>
  dplyr::filter(
    sovereign_state !=
      "WIO"
  ) |>
  dplyr::mutate(
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


# overall_plot <-
#   ggplot2::ggplot(
#     overall_plot_data,
#     ggplot2::aes(
#       x =
#         sovereign_state,
#       y =
#         percent_eez,
#       fill =
#         protection_category
#     )
#   ) +
#   ggplot2::geom_col() +
#   ggplot2::coord_flip() +
#   ggplot2::labs(
#     title =
#       "Protected EEZ area by management category",
#     subtitle =
#       "Filtered MPA and OECM dataset; overlapping area counted as its own category",
#     x =
#       NULL,
#     y =
#       "Proportion of EEZ (%)",
#     fill =
#       "Protection category"
#   ) +
#   ggplot2::theme_minimal()
# 
# 
# ggplot2::ggsave(
#   file.path(
#     plot_dir,
#     "overall_eez_protection_composition.png"
#   ),
#   plot =
#     overall_plot,
#   width =
#     10,
#   height =
#     7,
#   dpi =
#     300
# )


# ============================================================
# 9. GINI FUNCTIONS
# ============================================================

gini_raw <- function(x) {
  
  x <-
    x[
      is.finite(x) &
        !is.na(x)
    ]
  
  if (
    length(x) == 0 ||
    sum(x) == 0
  ) {
    return(NA_real_)
  }
  
  if (any(x < 0)) {
    stop(
      "Gini values cannot be negative."
    )
  }
  
  n <-
    length(x)
  
  if (n == 1) {
    return(0)
  }
  
  x <-
    sort(x)
  
  (
    2 *
      sum(
        seq_len(n) *
          x
      ) /
      (
        n *
          sum(x)
      )
  ) -
    (
      n + 1
    ) /
    n
}


gini_normalised <- function(x) {
  
  x <-
    x[
      is.finite(x) &
        !is.na(x)
    ]
  
  if (
    length(x) < 2 ||
    sum(x) == 0
  ) {
    return(NA_real_)
  }
  
  raw <-
    gini_raw(x)
  
  raw *
    length(x) /
    (
      length(x) -
        1
    )
}


# ============================================================
# 10. VECTOR AREA: DISSOLVE HABITAT BY COUNTRY IN BATCHES
# ============================================================

read_vector_habitat <- function(
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
      sf::st_crs(x)
    )
  ) {
    
    if (
      is.na(
        SOURCE_INDICATOR_CRS_IF_MISSING
      )
    ) {
      
      stop(
        "Habitat layer has missing CRS:\n",
        path
      )
    }
    
    sf::st_crs(x) <-
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


dissolve_vector_habitat_by_country <- function(
    habitat_sf,
    eez_sf,
    indicator,
    batch_size) {
  

  habitat_geom <-
    sf::st_sf(
      geometry =
        sf::st_geometry(
          habitat_sf
        )
    )
  
  country_results <-
    vector(
      "list",
      nrow(
        eez_sf
      )
    )
  
  
  for (
    i in
    seq_len(
      nrow(
        eez_sf
      )
    )
  ) {
    
    country_zone <-
      eez_sf[
        i,
        ,
        drop = FALSE
      ]
    
    country <-
      country_zone$sovereign_state[[1]]
    
    message(
      "\n",
      indicator,
      ": preparing unique habitat footprint for ",
      country
    )
    
    hits <-
      sf::st_intersects(
        habitat_geom,
        country_zone,
        sparse = TRUE
      )
    
    keep <-
      lengths(
        hits
      ) >
      0
    
    idx <-
      which(
        keep
      )
    
    if (
      length(
        idx
      ) == 0
    ) {
      next
    }
    
    starts <-
      seq(
        1,
        length(idx),
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
          length(idx)
        )
      
      batch_idx <-
        idx[
          start_pos:end_pos
        ]
      
      message(
        "  batch ",
        b,
        "/",
        length(starts),
        " (",
        length(batch_idx),
        " features)"
      )
      
      batch <-
        habitat_geom[
          batch_idx,
          ,
          drop = FALSE
        ] |>
        make_valid_polygonal()
      
      if (
        nrow(
          batch
        ) == 0
      ) {
        next
      }
      
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
        ) == 0
      ) {
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
        ) > 0
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
      ) == 0
    ) {
      next
    }
    
    
    combined_batches <-
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
              combined_batches
            )
          )
      ) |>
      make_valid_polygonal()
    
    
    if (
      nrow(
        country_result
      ) > 0
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
      combined_batches,
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
    ) == 0
  ) {
    
    stop(
      "No ",
      indicator,
      " polygons intersected the WIO EEZs."
    )
  }
  
  
  dplyr::bind_rows(
    country_results
  )
}


# ============================================================
# 11. AREA HABITAT AGAINST EXCLUSIVE PROTECTION ZONES
# ============================================================

area_composition_from_country_habitat <- function(
    habitat_by_country,
    exclusive_zones) {
  
  countries <-
    unique(
      habitat_by_country$sovereign_state
    )
  
  results <-
    list()
  
  k <-
    1
  
  
  for (country in countries) {
    
    habitat_country <-
      habitat_by_country |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    if (
      nrow(
        habitat_country
      ) == 0
    ) {
      next
    }
    
    
    habitat_area <-
      as.numeric(
        sf::st_area(
          habitat_country
        )
      ) /
      1e6
    
    
    results[[k]] <-
      tibble::tibble(
        sovereign_state =
          country,
        protection_category =
          "TOTAL_HABITAT",
        amount =
          sum(
            habitat_area,
            na.rm = TRUE
          )
      )
    
    k <-
      k + 1
    
    
    zones_country <-
      exclusive_zones |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    if (
      nrow(
        zones_country
      ) == 0
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
      
      zone <-
        zones_country[
          z,
          ,
          drop = FALSE
        ]
      
      category <-
        zone$protection_category[[1]]
      
      inter <-
        suppressWarnings(
          sf::st_intersection(
            habitat_country |>
              dplyr::select(
                sovereign_state
              ),
            zone |>
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
        k + 1
    }
  }
  
  
  dplyr::bind_rows(
    results
  )
}


# ============================================================
# 12. AREA HABITAT WITHIN INDIVIDUAL MPAs
# ============================================================

area_in_individual_mpas <- function(
    habitat_by_country,
    mpa_sf) {
  
  output <-
    vector(
      "list",
      length(
        unique(
          mpa_sf$sovereign_state
        )
      )
    )
  
  countries <-
    unique(
      mpa_sf$sovereign_state
    )
  
  
  for (
    i in
    seq_along(
      countries
    )
  ) {
    
    country <-
      countries[[i]]
    
    message(
      "Habitat x individual MPA: ",
      country
    )
    
    
    habitat_country <-
      habitat_by_country |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    mpas_country <-
      mpa_sf |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    if (
      nrow(
        mpas_country
      ) == 0
    ) {
      next
    }
    
    
    if (
      nrow(
        habitat_country
      ) == 0
    ) {
      
      output[[i]] <-
        mpas_country |>
        sf::st_drop_geometry() |>
        dplyr::select(
          sovereign_state,
          mpa_id,
          country_mpa_id
        ) |>
        dplyr::mutate(
          indicator_area_in_mpa_km2 =
            0
        )
      
      next
    }
    
    
    inter <-
      suppressWarnings(
        sf::st_intersection(
          mpas_country |>
            dplyr::select(
              sovereign_state,
              mpa_id,
              country_mpa_id
            ),
          sf::st_sf(
            geometry =
              sf::st_geometry(
                habitat_country
              )
          )
        )
      ) |>
      make_valid_polygonal()
    
    
    if (
      nrow(
        inter
      ) ==
      0
    ) {
      
      area_tbl <-
        tibble::tibble(
          sovereign_state =
            character(),
          mpa_id =
            character(),
          country_mpa_id =
            character(),
          indicator_area_in_mpa_km2 =
            numeric()
        )
      
    } else {
      
      inter$indicator_area_in_mpa_km2 <-
        as.numeric(
          sf::st_area(
            inter
          )
        ) /
        1e6
      
      
      area_tbl <-
        inter |>
        sf::st_drop_geometry() |>
        dplyr::group_by(
          sovereign_state,
          mpa_id,
          country_mpa_id
        ) |>
        dplyr::summarise(
          indicator_area_in_mpa_km2 =
            sum(
              indicator_area_in_mpa_km2,
              na.rm = TRUE
            ),
          .groups =
            "drop"
        )
    }
    
    
    output[[i]] <-
      mpas_country |>
      sf::st_drop_geometry() |>
      dplyr::select(
        sovereign_state,
        mpa_id,
        country_mpa_id
      ) |>
      dplyr::left_join(
        area_tbl,
        by =
          c(
            "sovereign_state",
            "mpa_id",
            "country_mpa_id"
          )
      ) |>
      dplyr::mutate(
        indicator_area_in_mpa_km2 =
          tidyr::replace_na(
            indicator_area_in_mpa_km2,
            0
          )
      )
  }
  
  
  dplyr::bind_rows(
    output
  )
}


# ============================================================
# 13. POINT HABITAT HELPERS
# ============================================================

point_counts_by_country <- function(
    points,
    eez_sf) {
  
  points <-
    points |>
    dplyr::mutate(
      point_id =
        dplyr::row_number()
    )
  
  
  hits <-
    sf::st_intersects(
      points,
      eez_sf,
      sparse = TRUE
    )
  
  
  out <-
    purrr::map_dfr(
      seq_along(
        hits
      ),
      function(i) {
        
        ids <-
          hits[[i]]
        
        if (
          length(
            ids
          ) ==
          0
        ) {
          return(NULL)
        }
        
        tibble::tibble(
          point_id =
            i,
          sovereign_state =
            eez_sf$sovereign_state[
              ids
            ]
        )
      }
    )
  
  
  if (
    nrow(
      out
    ) ==
    0
  ) {
    return(
      tibble::tibble(
        sovereign_state =
          character(),
        indicator_point_count =
          integer()
      )
    )
  }
  
  
  out |>
    dplyr::distinct(
      point_id,
      sovereign_state
    ) |>
    dplyr::count(
      sovereign_state,
      name =
        "indicator_point_count"
    )
}


point_composition_exclusive <- function(
    points,
    exclusive_zones) {
  
  points <-
    points |>
    dplyr::mutate(
      point_id =
        dplyr::row_number()
    )
  
  
  hits <-
    sf::st_intersects(
      points,
      exclusive_zones,
      sparse = TRUE
    )
  
  
  zone_tbl <-
    exclusive_zones |>
    sf::st_drop_geometry() |>
    dplyr::select(
      sovereign_state,
      protection_category
    )
  
  
  out <-
    purrr::map_dfr(
      seq_along(
        hits
      ),
      function(i) {
        
        ids <-
          hits[[i]]
        
        if (
          length(
            ids
          ) ==
          0
        ) {
          return(NULL)
        }
        
        zone_tbl[
          ids,
          ,
          drop = FALSE
        ] |>
          dplyr::mutate(
            point_id =
              i
          )
      }
    )
  
  
  if (
    nrow(
      out
    ) ==
    0
  ) {
    return(
      tibble::tibble(
        sovereign_state =
          character(),
        protection_category =
          character(),
        amount =
          integer()
      )
    )
  }
  
  
  out |>
    dplyr::distinct(
      point_id,
      sovereign_state,
      protection_category
    ) |>
    dplyr::count(
      sovereign_state,
      protection_category,
      name =
        "amount"
    )
}


point_counts_individual_mpa <- function(
    points,
    mpa_sf) {
  
  points <-
    points |>
    dplyr::mutate(
      point_id =
        dplyr::row_number()
    )
  
  
  hits <-
    sf::st_intersects(
      points,
      mpa_sf,
      sparse = TRUE
    )
  
  
  mpa_tbl <-
    mpa_sf |>
    sf::st_drop_geometry() |>
    dplyr::select(
      sovereign_state,
      mpa_id,
      country_mpa_id
    )
  
  
  out <-
    purrr::map_dfr(
      seq_along(
        hits
      ),
      function(i) {
        
        ids <-
          hits[[i]]
        
        if (
          length(
            ids
          ) ==
          0
        ) {
          return(NULL)
        }
        
        mpa_tbl[
          ids,
          ,
          drop = FALSE
        ] |>
          dplyr::mutate(
            point_id =
              i
          )
      }
    )
  
  
  if (
    nrow(
      out
    ) ==
    0
  ) {
    
    counts <-
      tibble::tibble(
        sovereign_state =
          character(),
        mpa_id =
          character(),
        country_mpa_id =
          character(),
        indicator_point_count_in_mpa =
          integer()
      )
    
  } else {
    
    counts <-
      out |>
      dplyr::distinct(
        point_id,
        sovereign_state,
        mpa_id,
        country_mpa_id
      ) |>
      dplyr::count(
        sovereign_state,
        mpa_id,
        country_mpa_id,
        name =
          "indicator_point_count_in_mpa"
      )
  }
  
  
  mpa_base_table |>
    dplyr::left_join(
      counts,
      by =
        c(
          "sovereign_state",
          "mpa_id",
          "country_mpa_id"
        )
    ) |>
    dplyr::mutate(
      indicator_point_count_in_mpa =
        tidyr::replace_na(
          indicator_point_count_in_mpa,
          0L
        )
    )
}


# ============================================================
# 14. RASTER HELPERS
# ============================================================

exact_raster_sum <- function(
    area_raster,
    zones_sf) {
  
  if (
    nrow(
      zones_sf
    ) ==
    0
  ) {
    return(
      numeric(0)
    )
  }
  
  
  zones_vect <-
    zones_sf |>
    sf::st_transform(
      terra::crs(
        area_raster
      )
    ) |>
    terra::vect()
  
  
  ex <-
    terra::extract(
      area_raster,
      zones_vect,
      fun =
        "sum",
      exact =
        TRUE,
      na.rm =
        TRUE
    )
  
  
  value_col <-
    setdiff(
      names(ex),
      "ID"
    )[[1]]
  
  
  values <-
    as.numeric(
      ex[[value_col]]
    )
  
  values[
    is.na(
      values
    ) |
      !is.finite(
        values
      )
  ] <-
    0
  
  values
}


process_raster_habitat <- function(
    path,
    indicator) {
  
  r <-
    terra::rast(
      path
    )
  
  
  if (
    terra::nlyr(r) <
    RASTER_LAYER_INDEX
  ) {
    
    stop(
      "Raster has fewer layers than RASTER_LAYER_INDEX:\n",
      path
    )
  }
  
  
  if (
    is.na(
      terra::crs(r)
    ) ||
    terra::crs(r) ==
    ""
  ) {
    
    if (
      is.na(
        SOURCE_INDICATOR_CRS_IF_MISSING
      )
    ) {
      
      stop(
        "Raster has missing CRS:\n",
        path
      )
    }
    
    terra::crs(r) <-
      SOURCE_INDICATOR_CRS_IF_MISSING
  }
  
  
  r <-
    r[[RASTER_LAYER_INDEX]]
  
  
  country_results <-
    vector(
      "list",
      nrow(
        eez_by_country
      )
    )
  
  
  mpa_results <-
    vector(
      "list",
      nrow(
        eez_by_country
      )
    )
  
  
  for (
    i in
    seq_len(
      nrow(
        eez_by_country
      )
    )
  ) {
    
    country <-
      eez_by_country$sovereign_state[[i]]
    
    message(
      "\n",
      indicator,
      " raster: ",
      country
    )
    
    
    eez_country <-
      eez_by_country[
        i,
        ,
        drop = FALSE
      ]
    
    
    eez_raster_crs <-
      eez_country |>
      sf::st_transform(
        terra::crs(r)
      ) |>
      terra::vect()
    
    
    r_country <-
      terra::crop(
        r,
        eez_raster_crs
      )
    
    
    if (
      RASTER_PRESENCE_RULE ==
      "nonzero"
    ) {
      
      presence <-
        terra::ifel(
          !is.na(
            r_country
          ) &
            r_country !=
            0,
          1,
          NA
        )
      
    } else if (
      RASTER_PRESENCE_RULE ==
      "not_na"
    ) {
      
      presence <-
        terra::ifel(
          !is.na(
            r_country
          ),
          1,
          NA
        )
      
    } else {
      
      stop(
        "Unknown RASTER_PRESENCE_RULE: ",
        RASTER_PRESENCE_RULE
      )
    }
    
    
    cell_area <-
      terra::cellSize(
        presence,
        unit =
          "km"
      )
    
    
    area_raster <-
      cell_area *
      presence
    
    
    names(
      area_raster
    ) <-
      "habitat_area_km2"
    
    
    total_area <-
      exact_raster_sum(
        area_raster,
        eez_country |>
          dplyr::select(
            sovereign_state
          )
      )
    
    
    total_area <-
      if (
        length(
          total_area
        ) ==
        0
      ) {
        0
      } else {
        total_area[[1]]
      }
    
    
    zones_country <-
      protection_exclusive |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    category_tbl <-
      tibble::tibble(
        protection_category =
          c(
            "MPA only",
            "OECM only",
            "MPA-OECM overlap"
          ),
        amount =
          0
      )
    
    
    if (
      nrow(
        zones_country
      ) >
      0
    ) {
      
      zone_values <-
        exact_raster_sum(
          area_raster,
          zones_country
        )
      
      
      zone_tbl <-
        zones_country |>
        sf::st_drop_geometry() |>
        dplyr::transmute(
          protection_category =
            protection_category,
          amount =
            zone_values
        )
      
      
      category_tbl <-
        category_tbl |>
        dplyr::select(
          -amount
        ) |>
        dplyr::left_join(
          zone_tbl,
          by =
            "protection_category"
        ) |>
        dplyr::mutate(
          amount =
            tidyr::replace_na(
              amount,
              0
            )
        )
    }
    
    
    country_results[[i]] <-
      dplyr::bind_rows(
        tibble::tibble(
          sovereign_state =
            country,
          protection_category =
            "TOTAL_HABITAT",
          amount =
            total_area
        ),
        category_tbl |>
          dplyr::mutate(
            sovereign_state =
              country,
            .before =
              1
          )
      )
    
    
    mpas_country <-
      mpa_individual |>
      dplyr::filter(
        sovereign_state ==
          country
      )
    
    
    if (
      nrow(
        mpas_country
      ) >
      0
    ) {
      
      mpa_values <-
        exact_raster_sum(
          area_raster,
          mpas_country
        )
      
      
      mpa_results[[i]] <-
        mpas_country |>
        sf::st_drop_geometry() |>
        dplyr::select(
          sovereign_state,
          mpa_id,
          country_mpa_id
        ) |>
        dplyr::mutate(
          indicator_area_in_mpa_km2 =
            mpa_values
        )
    }
    
    
    rm(
      eez_raster_crs,
      r_country,
      presence,
      cell_area,
      area_raster
    )
    
    gc(
      verbose = FALSE
    )
  }
  
  
  list(
    composition =
      dplyr::bind_rows(
        country_results
      ),
    mpa =
      dplyr::bind_rows(
        mpa_results
      )
  )
}


# ============================================================
# 15. BUILD STANDARD COUNTRY OUTPUT FROM EXCLUSIVE COMPONENTS
# ============================================================

build_area_country_output <- function(
    composition_tbl,
    indicator,
    data_type,
    filter_expr) {
  
  total_tbl <-
    composition_tbl |>
    dplyr::filter(
      protection_category ==
        "TOTAL_HABITAT"
    ) |>
    dplyr::transmute(
      sovereign_state,
      indicator_area_km2 =
        amount
    )
  
  
  protection_wide <-
    composition_tbl |>
    dplyr::filter(
      protection_category !=
        "TOTAL_HABITAT"
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
      protection_wide,
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
        ),
      
      indicator_total_in_all_eezs_km2 =
        regional_total,
      
      indicator_total_points_in_all_eezs =
        NA_integer_
    ) |>
    dplyr::select(
      sovereign_state,
      indicator,
      data_type,
      measure_type,
      filter_expr_applied,
      eez_area_km2,
      
      indicator_area_km2,
      protected_indicator_area_km2,
      mpa_indicator_area_km2,
      oecm_indicator_area_km2,
      
      mpa_only_indicator_area_km2,
      oecm_only_indicator_area_km2,
      overlap_indicator_area_km2,
      
      indicator_point_count,
      protected_indicator_point_count,
      mpa_indicator_point_count,
      oecm_indicator_point_count,
      
      mpa_only_indicator_point_count,
      oecm_only_indicator_point_count,
      overlap_indicator_point_count,
      
      indicator_total_in_all_eezs_km2,
      indicator_total_points_in_all_eezs,
      
      percent_eez_covered_by_indicator,
      percent_of_indicator_in_all_eezs,
      
      percent_indicator_protected_total,
      percent_indicator_protected_mpa,
      percent_indicator_protected_oecm,
      
      percent_indicator_protected_mpa_only,
      percent_indicator_protected_oecm_only,
      percent_indicator_protected_overlap
    )
}


build_point_country_output <- function(
    point_sf,
    indicator,
    data_type,
    filter_expr) {
  
  total_tbl <-
    point_counts_by_country(
      point_sf,
      eez_by_country |>
        dplyr::select(
          sovereign_state
        )
    )
  
  
  exclusive_tbl <-
    point_composition_exclusive(
      point_sf,
      protection_exclusive
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
      exclusive_tbl,
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
        ),
      
      indicator_total_in_all_eezs_km2 =
        NA_real_,
      
      indicator_total_points_in_all_eezs =
        regional_total
    ) |>
    dplyr::select(
      sovereign_state,
      indicator,
      data_type,
      measure_type,
      filter_expr_applied,
      eez_area_km2,
      
      indicator_area_km2,
      protected_indicator_area_km2,
      mpa_indicator_area_km2,
      oecm_indicator_area_km2,
      
      mpa_only_indicator_area_km2,
      oecm_only_indicator_area_km2,
      overlap_indicator_area_km2,
      
      indicator_point_count,
      protected_indicator_point_count,
      mpa_indicator_point_count,
      oecm_indicator_point_count,
      
      mpa_only_indicator_point_count,
      oecm_only_indicator_point_count,
      overlap_indicator_point_count,
      
      indicator_total_in_all_eezs_km2,
      indicator_total_points_in_all_eezs,
      
      percent_eez_covered_by_indicator,
      percent_of_indicator_in_all_eezs,
      
      percent_indicator_protected_total,
      percent_indicator_protected_mpa,
      percent_indicator_protected_oecm,
      
      percent_indicator_protected_mpa_only,
      percent_indicator_protected_oecm_only,
      percent_indicator_protected_overlap
    )
}


# ============================================================
# 16. CACHE KEY
# ============================================================

cache_key_for_indicator <- function(
    path,
    indicator,
    data_type,
    measure_type,
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
      indicator =
        indicator,
      data_type =
        data_type,
      measure_type =
        measure_type,
      filter_expr =
        filter_expr,
      cache_version =
        CACHE_VERSION,
      raster_presence =
        RASTER_PRESENCE_RULE,
      raster_layer =
        RASTER_LAYER_INDEX,
      vector_batch_size =
        VECTOR_BATCH_SIZE,
      coral_batch_size =
        CORAL_BATCH_SIZE,
      mpa_official_id =
        MPA_OFFICIAL_ID_COL,
      excluded_sovereign_states =
        EXCLUDED_SOVEREIGN_STATES,
      gini_include_zero =
        GINI_INCLUDE_ZERO_MPAS
    )
  )
}


# ============================================================
# 17. PROCESS ONE HABITAT
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
  
  filter_expr <-
    indicator_inputs$filter_expr[[j]]
  
  
  key <-
    cache_key_for_indicator(
      path =
        path,
      indicator =
        indicator,
      data_type =
        data_type,
      measure_type =
        requested_measure_type,
      filter_expr =
        filter_expr
    )
  
  
  key_short <-
    substr(
      key,
      1,
      12
    )
  
  
  country_cache_file <-
    file.path(
      cache_dir,
      paste0(
        clean_filename(
          indicator
        ),
        "_",
        key_short,
        "_country.csv"
      )
    )
  
  
  mpa_cache_file <-
    file.path(
      cache_dir,
      paste0(
        clean_filename(
          indicator
        ),
        "_",
        key_short,
        "_mpa.csv"
      )
    )
  
  
  dissolved_cache_gpkg <-
    file.path(
      cache_dir,
      paste0(
        clean_filename(
          indicator
        ),
        "_",
        key_short,
        "_dissolved_by_country.gpkg"
      )
    )
  
  
  if (
    file.exists(
      country_cache_file
    ) &&
    file.exists(
      mpa_cache_file
    ) &&
    !FORCE_RERUN
  ) {
    
    message(
      "\nUsing cached Element 2 results for: ",
      indicator
    )
    
    return(
      list(
        country =
          readr::read_csv(
            country_cache_file,
            show_col_types = FALSE
          ),
        mpa =
          readr::read_csv(
            mpa_cache_file,
            show_col_types = FALSE
          )
      )
    )
  }
  
  
  message(
    "\n============================================================"
  )
  
  message(
    "Processing habitat: ",
    indicator
  )
  
  message(
    "============================================================"
  )
  
  
  # ----------------------------------------------------------
  # Raster area habitat
  # ----------------------------------------------------------
  
  if (
    data_type ==
    "raster"
  ) {
    
    if (
      !(
        requested_measure_type %in%
        c(
          "area",
          "auto"
        )
      )
    ) {
      
      stop(
        "Raster habitat must use measure_type = area/auto."
      )
    }
    
    
    raster_result <-
      timer(
        paste0(
          indicator,
          ": memory-safe raster processing"
        ),
        process_raster_habitat(
          path =
            path,
          indicator =
            indicator
        )
      )
    
    
    country_out <-
      build_area_country_output(
        composition_tbl =
          raster_result$composition,
        indicator =
          indicator,
        data_type =
          data_type,
        filter_expr =
          filter_expr
      )
    
    
    mpa_out <-
      mpa_base_table |>
      dplyr::left_join(
        raster_result$mpa,
        by =
          c(
            "sovereign_state",
            "mpa_id",
            "country_mpa_id"
          )
      ) |>
      dplyr::mutate(
        indicator_area_in_mpa_km2 =
          tidyr::replace_na(
            indicator_area_in_mpa_km2,
            0
          ),
        indicator_point_count_in_mpa =
          NA_integer_,
        indicator =
          indicator,
        data_type =
          data_type,
        measure_type =
          "area"
      )
    
    
    # ----------------------------------------------------------
    # Vector habitat
    # ----------------------------------------------------------
    
  } else {
    
    habitat_raw <-
      timer(
        paste0(
          indicator,
          ": read vector habitat"
        ),
        read_vector_habitat(
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
        habitat_raw
      ) ==
      0
    ) {
      
      stop(
        "No features remain for ",
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
          habitat_raw
        )
        
      } else {
        
        requested_measure_type
      }
    
    
    # --------------------------------------------------------
    # Vector area
    # --------------------------------------------------------
    
    if (
      final_measure_type ==
      "area"
    ) {
      
      batch_size <-
        if (
          stringr::str_to_lower(
            indicator
          ) ==
          "coral"
        ) {
          
          CORAL_BATCH_SIZE
          
        } else {
          
          VECTOR_BATCH_SIZE
        }
      
      
      if (
        file.exists(
          dissolved_cache_gpkg
        ) &&
        !FORCE_RERUN
      ) {
        
        message(
          "Loading cached dissolved habitat geometry for ",
          indicator
        )
        
        habitat_by_country <-
          sf::st_read(
            dissolved_cache_gpkg,
            layer =
              "habitat_by_country",
            quiet =
              TRUE
          )
        
      } else {
        
        habitat_by_country <-
          timer(
            paste0(
              indicator,
              ": dissolve unique habitat by country"
            ),
            dissolve_vector_habitat_by_country(
              habitat_sf =
                habitat_raw,
              eez_sf =
                eez_by_country,
              indicator =
                indicator,
              batch_size =
                batch_size
            )
          )
        
        
        if (
          file.exists(
            dissolved_cache_gpkg
          )
        ) {
          unlink(
            dissolved_cache_gpkg
          )
        }
        
        
        sf::st_write(
          habitat_by_country,
          dsn =
            dissolved_cache_gpkg,
          layer =
            "habitat_by_country",
          quiet =
            TRUE
        )
      }
      
      
      composition_tbl <-
        timer(
          paste0(
            indicator,
            ": calculate exclusive protection composition"
          ),
          area_composition_from_country_habitat(
            habitat_by_country =
              habitat_by_country,
            exclusive_zones =
              protection_exclusive
          )
        )
      
      
      country_out <-
        build_area_country_output(
          composition_tbl =
            composition_tbl,
          indicator =
            indicator,
          data_type =
            data_type,
          filter_expr =
            filter_expr
        )
      
      
      mpa_area_tbl <-
        timer(
          paste0(
            indicator,
            ": habitat by individual MPA for Gini"
          ),
          area_in_individual_mpas(
            habitat_by_country =
              habitat_by_country,
            mpa_sf =
              mpa_individual
          )
        )
      
      
      mpa_out <-
        mpa_base_table |>
        dplyr::left_join(
          mpa_area_tbl,
          by =
            c(
              "sovereign_state",
              "mpa_id",
              "country_mpa_id"
            )
        ) |>
        dplyr::mutate(
          indicator_area_in_mpa_km2 =
            tidyr::replace_na(
              indicator_area_in_mpa_km2,
              0
            ),
          indicator_point_count_in_mpa =
            NA_integer_,
          indicator =
            indicator,
          data_type =
            data_type,
          measure_type =
            "area"
        )
      
      
      rm(
        habitat_by_country,
        composition_tbl,
        mpa_area_tbl
      )
      
      gc(
        verbose = FALSE
      )
      
      
      # --------------------------------------------------------
      # Vector points
      # --------------------------------------------------------
      
    } else if (
      final_measure_type ==
      "points"
    ) {
      
      point_sf <-
        habitat_raw |>
        make_point_sf() |>
        dplyr::select(
          geometry
        )
      
      
      country_out <-
        build_point_country_output(
          point_sf =
            point_sf,
          indicator =
            indicator,
          data_type =
            data_type,
          filter_expr =
            filter_expr
        )
      
      
      mpa_point_tbl <-
        point_counts_individual_mpa(
          point_sf,
          mpa_individual
        )
      
      
      mpa_out <-
        mpa_point_tbl |>
        dplyr::mutate(
          indicator_area_in_mpa_km2 =
            NA_real_,
          indicator =
            indicator,
          data_type =
            data_type,
          measure_type =
            "points"
        )
      
      
    } else {
      
      stop(
        "Unsupported measure type: ",
        final_measure_type
      )
    }
  }
  
  
  # Standardise individual-MPA output.
  mpa_out <-
    mpa_out |>
    dplyr::select(
      sovereign_state,
      mpa_id,
      country_mpa_id,
      indicator,
      data_type,
      measure_type,
      indicator_area_in_mpa_km2,
      indicator_point_count_in_mpa
    )
  
  
  readr::write_csv(
    country_out,
    country_cache_file
  )
  
  
  readr::write_csv(
    mpa_out,
    mpa_cache_file
  )
  
  
  message(
    "Finished and cached: ",
    indicator
  )
  
  
  if (exists("habitat_raw", inherits = FALSE)) {
    rm(
      habitat_raw
    )
  }
  
  gc(
    verbose = FALSE
  )
  
  
  list(
    country =
      country_out,
    mpa =
      mpa_out
  )
}


# ============================================================
# 18. RUN HABITATS SEQUENTIALLY
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
    process_one_indicator(
      j
    )
  
  gc(
    verbose = FALSE
  )
}


# ============================================================
# 19. COMBINE COUNTRY RESULTS
# ============================================================

country_summary <-
  indicator_results |>
  purrr::map(
    "country"
  ) |>
  dplyr::bind_rows() |>
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
    
    protected_indicator_area_km2 =
      sum_or_na(
        protected_indicator_area_km2
      ),
    
    mpa_indicator_area_km2 =
      sum_or_na(
        mpa_indicator_area_km2
      ),
    
    oecm_indicator_area_km2 =
      sum_or_na(
        oecm_indicator_area_km2
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
    
    indicator_point_count =
      sum_int_or_na(
        indicator_point_count
      ),
    
    protected_indicator_point_count =
      sum_int_or_na(
        protected_indicator_point_count
      ),
    
    mpa_indicator_point_count =
      sum_int_or_na(
        mpa_indicator_point_count
      ),
    
    oecm_indicator_point_count =
      sum_int_or_na(
        oecm_indicator_point_count
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


country_summary <-
  dplyr::bind_rows(
    country_summary,
    wio_rows
  ) |>
  dplyr::arrange(
    indicator,
    sovereign_state
  )


# ============================================================
# 21. COMBINE INDIVIDUAL MPA RESULTS
# ============================================================

mpa_summary <-
  indicator_results |>
  purrr::map(
    "mpa"
  ) |>
  dplyr::bind_rows() |>
  dplyr::arrange(
    indicator,
    sovereign_state,
    mpa_id
  )


# ============================================================
# 22. GINI COEFFICIENT
# ============================================================

gini_input <-
  mpa_summary |>
  dplyr::mutate(
    indicator_amount_in_mpa =
      dplyr::case_when(
        measure_type ==
          "area" ~
          indicator_area_in_mpa_km2,
        measure_type ==
          "points" ~
          as.numeric(
            indicator_point_count_in_mpa
          ),
        TRUE ~
          NA_real_
      )
  )


if (
  !GINI_INCLUDE_ZERO_MPAS
) {
  
  gini_input <-
    gini_input |>
    dplyr::filter(
      indicator_amount_in_mpa >
        0
    )
}


gini_summary <-
  gini_input |>
  dplyr::group_by(
    sovereign_state,
    indicator,
    data_type,
    measure_type
  ) |>
  dplyr::summarise(
    
    n_mpas_used_for_gini =
      dplyr::n_distinct(
        country_mpa_id
      ),
    
    n_mpas_with_indicator =
      dplyr::n_distinct(
        country_mpa_id[
          indicator_amount_in_mpa >
            0
        ]
      ),
    
    total_indicator_amount_across_mpas =
      sum(
        indicator_amount_in_mpa,
        na.rm = TRUE
      ),
    
    gini_raw =
      gini_raw(
        indicator_amount_in_mpa
      ),
    
    gini_normalised =
      gini_normalised(
        indicator_amount_in_mpa
      ),
    
    .groups =
      "drop"
  )


n_mpas_country <-
  mpa_base_table |>
  dplyr::group_by(
    sovereign_state
  ) |>
  dplyr::summarise(
    n_mpas_total =
      dplyr::n_distinct(
        country_mpa_id
      ),
    .groups =
      "drop"
  )


gini_summary <-
  gini_summary |>
  dplyr::left_join(
    n_mpas_country,
    by =
      "sovereign_state"
  ) |>
  dplyr::relocate(
    n_mpas_total,
    .before =
      n_mpas_used_for_gini
  ) |>
  dplyr::arrange(
    indicator,
    sovereign_state
  )


# ============================================================
# 23. GINI BUBBLE PLOT
# ============================================================
#
# This follows the logic of the previous WIO figure:
#
#   x     = habitat/type
#   y     = sovereign state
#   fill  = normalised Gini coefficient
#   size  = total number of MPAs in the country
#   label = Gini coefficient
#
# Normalised Gini is used because the number of MPAs differs
# among sovereign states and this puts the finite-sample range
# onto a directly comparable 0-1 scale.
# ============================================================


gini_plot_summary <-
  gini_summary


# ------------------------------------------------------------
# Optional fifth column: Gini of MPA area itself
# ------------------------------------------------------------

if (
  INCLUDE_MPA_AREA_IN_GINI_PLOT
) {
  
  mpa_area_gini_input <-
    mpa_individual |>
    dplyr::mutate(
      mpa_area_km2 =
        as.numeric(
          sf::st_area(
            mpa_individual
          )
        ) /
        1e6
    ) |>
    sf::st_drop_geometry()
  
  
  mpa_area_gini <-
    mpa_area_gini_input |>
    dplyr::group_by(
      sovereign_state
    ) |>
    dplyr::summarise(
      
      indicator =
        "MPA area",
      
      data_type =
        "vector",
      
      measure_type =
        "area",
      
      n_mpas_total =
        dplyr::n_distinct(
          country_mpa_id
        ),
      
      n_mpas_used_for_gini =
        dplyr::n_distinct(
          country_mpa_id
        ),
      
      n_mpas_with_indicator =
        dplyr::n_distinct(
          country_mpa_id[
            mpa_area_km2 >
              0
          ]
        ),
      
      total_indicator_amount_across_mpas =
        sum(
          mpa_area_km2,
          na.rm = TRUE
        ),
      
      gini_raw =
        gini_raw(
          mpa_area_km2
        ),
      
      gini_normalised =
        gini_normalised(
          mpa_area_km2
        ),
      
      .groups =
        "drop"
    )
  
  
  gini_plot_summary <-
    dplyr::bind_rows(
      gini_plot_summary,
      mpa_area_gini
    )
}


# ------------------------------------------------------------
# Preserve the familiar country/type ordering where possible.
# Any additional countries or indicator types are appended.
# ------------------------------------------------------------

observed_gini_countries <-
  unique(
    gini_plot_summary$sovereign_state
  )


gini_country_levels <-
  c(
    intersect(
      GINI_COUNTRY_ORDER,
      observed_gini_countries
    ),
    setdiff(
      sort(
        observed_gini_countries
      ),
      GINI_COUNTRY_ORDER
    )
  )


observed_gini_types <-
  unique(
    gini_plot_summary$indicator
  )


gini_type_levels <-
  c(
    intersect(
      GINI_HABITAT_ORDER,
      observed_gini_types
    ),
    setdiff(
      sort(
        observed_gini_types
      ),
      GINI_HABITAT_ORDER
    )
  )


gini_plot_data <-
  gini_plot_summary |>
  dplyr::mutate(
    
    sovereign_state =
      factor(
        sovereign_state,
        levels =
          gini_country_levels
      ),
    
    indicator =
      factor(
        indicator,
        levels =
          gini_type_levels
      ),
    
    gini_label =
      dplyr::if_else(
        is.na(
          gini_normalised
        ),
        "NA",
        sprintf(
          "%.2f",
          gini_normalised
        )
      )
  )


readr::write_csv(
  gini_plot_data |>
    dplyr::mutate(
      sovereign_state =
        as.character(
          sovereign_state
        ),
      indicator =
        as.character(
          indicator
        )
    ),
  file.path(
    out_dir,
    "element2_gini_plot_data.csv"
  )
)


# gini_bubble_plot <-
#   ggplot2::ggplot(
#     gini_plot_data,
#     ggplot2::aes(
#       x =
#         indicator,
#       y =
#         sovereign_state
#     )
#   ) +
#   ggplot2::geom_point(
#     ggplot2::aes(
#       fill =
#         gini_normalised,
#       size =
#         n_mpas_total
#     ),
#     shape =
#       21,
#     colour =
#       "grey40",
#     stroke =
#       0.4
#   ) +
#   ggplot2::geom_text(
#     ggplot2::aes(
#       label =
#         gini_label
#     ),
#     colour =
#       "black",
#     size =
#       2.5
#   ) +
#   ggplot2::scale_size_area(
#     max_size =
#       15
#   ) +
#   ggplot2::scale_fill_viridis_c(
#     option =
#       "E",
#     limits =
#       c(
#         0,
#         1
#       ),
#     na.value =
#       "grey90"
#   ) +
#   ggplot2::guides(
#     size =
#       "none",
#     fill =
#       ggplot2::guide_colorbar(
#         barheight =
#           grid::unit(
#             0.5,
#             "cm"
#           ),
#         barwidth =
#           grid::unit(
#             10,
#             "cm"
#           ),
#         title.position =
#           "top"
#       )
#   ) +
#   ggplot2::labs(
#     x =
#       NULL,
#     y =
#       NULL,
#     fill =
#       "Normalised Gini coefficient",
#     title =
#       "Distribution of protected habitats among MPAs",
#     subtitle =
#       "Bubble size represents the number of MPAs in each sovereign state"
#   ) +
#   ggplot2::theme_minimal() +
#   ggplot2::theme(
#     legend.position =
#       "top",
#     text =
#       ggplot2::element_text(
#         colour =
#           "grey40"
#       ),
#     panel.grid.minor =
#       ggplot2::element_blank()
#   )
# 
# 
# gini_plot_file <-
#   file.path(
#     plot_dir,
#     "element2_gini_bubble_plot.png"
#   )
# 
# 
# ggplot2::ggsave(
#   filename =
#     gini_plot_file,
#   plot =
#     gini_bubble_plot,
#   width =
#     11,
#   height =
#     7,
#   dpi =
#     300
# )


# ============================================================
# 24. LONG TABLE FOR STACKED PROTECTION PLOTS
# ============================================================

composition_long <-
  country_summary |>
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


readr::write_csv(
  composition_long,
  file.path(
    out_dir,
    "element2_habitat_protection_composition_long.csv"
  )
)


# ============================================================
# 25. STACKED BAR PLOTS
# ============================================================

for (
  habitat_name in
  unique(
    composition_long$indicator
  )
) {
  
  plot_data <-
    composition_long |>
    dplyr::filter(
      indicator ==
        habitat_name,
      sovereign_state !=
        "WIO"
    )
  
  
  totals <-
    plot_data |>
    dplyr::group_by(
      sovereign_state
    ) |>
    dplyr::summarise(
      total_protected_percent =
        sum(
          percent_indicator,
          na.rm = TRUE
        ),
      .groups =
        "drop"
    ) |>
    dplyr::arrange(
      total_protected_percent
    )
  
  
  plot_data <-
    plot_data |>
    dplyr::mutate(
      sovereign_state =
        factor(
          sovereign_state,
          levels =
            totals$sovereign_state
        )
    )
  
  
#   p <-
#     ggplot2::ggplot(
#       plot_data,
#       ggplot2::aes(
#         x =
#           sovereign_state,
#         y =
#           percent_indicator,
#         fill =
#           protection_category
#       )
#     ) +
#     ggplot2::geom_col() +
#     ggplot2::coord_flip() +
#     ggplot2::labs(
#       title =
#         paste0(
#           habitat_name,
#           ": protected habitat by management category"
#         ),
#       subtitle =
#         "Stack height = total proportion protected; overlap is counted once",
#       x =
#         NULL,
#       y =
#         "Proportion of habitat protected (%)",
#       fill =
#         "Protection category"
#     ) +
#     ggplot2::theme_minimal()
#   
#   
#   ggplot2::ggsave(
#     filename =
#       file.path(
#         plot_dir,
#         paste0(
#           "element2_",
#           clean_filename(
#             habitat_name
#           ),
#           "_protection_composition.png"
#         )
#       ),
#     plot =
#       p,
#     width =
#       10,
#     height =
#       7,
#     dpi =
#       300
#   )
# }
# 
# 
# # Combined faceted plot.
# facet_data <-
#   composition_long |>
#   dplyr::filter(
#     sovereign_state !=
#       "WIO"
#   )
# 
# 
# facet_plot <-
#   ggplot2::ggplot(
#     facet_data,
#     ggplot2::aes(
#       x =
#         sovereign_state,
#       y =
#         percent_indicator,
#       fill =
#         protection_category
#     )
#   ) +
#   ggplot2::geom_col() +
#   ggplot2::coord_flip() +
#   ggplot2::facet_wrap(
#     ~ indicator
#   ) +
#   ggplot2::labs(
#     title =
#       "Element 2 habitat protection composition",
#     subtitle =
#       "MPA only + OECM only + overlap = total protected proportion",
#     x =
#       NULL,
#     y =
#       "Proportion of habitat protected (%)",
#     fill =
#       "Protection category"
#   ) +
#   ggplot2::theme_minimal()
# 
# 
# ggplot2::ggsave(
#   filename =
#     file.path(
#       plot_dir,
#       "element2_all_habitats_protection_composition.png"
#     ),
#   plot =
#     facet_plot,
#   width =
#     14,
#   height =
#     10,
#   dpi =
#     300
# )


# ============================================================
# 26. QA CHECKS
# ============================================================
# 
# message(
#   "\nRunning QA checks..."
# )
# 
# 
# # Exclusive components should reproduce total protected amount.
# qa_partition <-
#   country_summary |>
#   dplyr::filter(
#     sovereign_state !=
#       "WIO"
#   ) |>
#   dplyr::mutate(
#     component_area_sum =
#       mpa_only_indicator_area_km2 +
#       oecm_only_indicator_area_km2 +
#       overlap_indicator_area_km2,
#     
#     component_point_sum =
#       mpa_only_indicator_point_count +
#       oecm_only_indicator_point_count +
#       overlap_indicator_point_count
#   ) |>
#   dplyr::filter(
#     (
#       measure_type ==
#         "area" &
#         abs(
#           protected_indicator_area_km2 -
#             component_area_sum
#         ) >
#         0.001
#     ) |
#       (
#         measure_type ==
#           "points" &
#           protected_indicator_point_count !=
#           component_point_sum
#       )
#   )
# 
# 
# if (
#   nrow(
#     qa_partition
#   ) >
#   0
# ) {
#   
#   warning(
#     "Exclusive components do not exactly reproduce total protection for some rows."
#   )
#   
#   print(
#     qa_partition
#   )
# }
# 
# 
# # Protected habitat should not exceed total habitat.
# qa_protected_total <-
#   country_summary |>
#   dplyr::filter(
#     sovereign_state !=
#       "WIO"
#   ) |>
#   dplyr::filter(
#     (
#       measure_type ==
#         "area" &
#         protected_indicator_area_km2 >
#         indicator_area_km2 +
#         0.001
#     ) |
#       (
#         measure_type ==
#           "points" &
#           protected_indicator_point_count >
#           indicator_point_count
#       )
#   )
# 
# 
# if (
#   nrow(
#     qa_protected_total
#   ) >
#   0
# ) {
#   
#   warning(
#     "Protected indicator amount exceeds total indicator amount for some rows."
#   )
#   
#   print(
#     qa_protected_total
#   )
# }
# 
# 
# # Gini should be in 0-1.
# qa_gini <-
#   gini_summary |>
#   dplyr::filter(
#     !is.na(
#       gini_normalised
#     ),
#     gini_normalised <
#       -1e-8 |
#       gini_normalised >
#       1 +
#       1e-8
#   )
# 
# 
# if (
#   nrow(
#     qa_gini
#   ) >
#   0
# ) {
#   
#   warning(
#     "Some normalised Gini values fall outside 0-1."
#   )
#   
#   print(
#     qa_gini
#   )
# }


# ============================================================
# 27. SAVE FINAL OUTPUTS
# ============================================================

country_out_csv <-
  file.path(
    out_dir,
    "element2_habitat_protection_by_sovereign.csv"
  )

mpa_out_csv <-
  file.path(
    out_dir,
    "element2_habitat_by_individual_mpa.csv"
  )

gini_out_csv <-
  file.path(
    out_dir,
    "element2_habitat_gini_by_sovereign.csv"
  )


readr::write_csv(
  country_summary,
  country_out_csv
)

readr::write_csv(
  mpa_summary,
  mpa_out_csv
)

readr::write_csv(
  gini_summary,
  gini_out_csv
)

