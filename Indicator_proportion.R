# ============================================================
# ELEMENT 3
# WIO areas of particular importance for biodiversity and
# ecosystem functions / services
#
# REUSABLE SPATIAL-INTERSECTION VERSION
# ============================================================
#
# PURPOSE
# -------
# For every Element 3 indicator, this script:
#
#   1. Loads the reusable Element 1 protection database.
#   2. DOES NOT rebuild EEZ / MPA / LMMA geometry from raw files.
#   3. For VECTOR indicators, performs and SAVES the expensive
#      spatial intersections BEFORE applying filter_expr:
#
#        indicator_prepared_unfiltered
#        indicator_x_eez
#        indicator_x_protected_unique
#        indicator_x_mpa_full
#        indicator_x_lmma_full
#
#      The MPA/LMMA intersections retain the full attributes
#      already saved in Element 1.
#
#   4. Applies filter_expr only when producing the summary.
#      Therefore future changes to indicator filters do NOT
#      require the spatial intersections to be repeated.
#
#   5. Calculates, by sovereign EEZ and for WIO overall:
#
#      AREA INDICATORS
#        - indicator area
#        - unique protected indicator area
#        - MPA indicator area
#        - LMMA indicator area
#        - percentages protected
#
#      POINT INDICATORS
#        - indicator point count
#        - unique protected point count
#        - MPA point count
#        - LMMA point count
#        - percentages protected
#
# IMPORTANT
# ---------
# The detailed MPA/LMMA overlays are saved separately from the
# combined unique protected footprint because later filtering by
# MPA/LMMA status, designation, year, etc. requires individual
# PA identity and attributes.
#
# Raster indicators are not converted to vector intersections.
# Their source raster/VRT is already the reusable spatial object;
# raster zonal summaries are cached as CSV.
#
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
  "rnaturalearth",
  "lwgeom",
  "rlang",
  "digest"
)

missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_pkgs) > 0) {
  install.packages(missing_pkgs)
}

invisible(lapply(pkgs, library, character.only = TRUE))

sf::sf_use_s2(FALSE)

terra::terraOptions(
  threads = TRUE,
  progress = 1,
  memfrac = 0.7
)


# ============================================================
# 2. USER SETTINGS
# ============================================================


# ------------------------------------------------------------
# 2a. Element 1 reusable protection database
# ------------------------------------------------------------

PROTECTION_GPKG <- "outputs/wio_protected_area_spatial_database.gpkg"

EEZ_LAYER <- "eez_by_country"
PROTECTED_UNIQUE_LAYER <- "protected_unique_by_country"
MPA_UNIQUE_LAYER <- "mpa_unique_by_country"
LMMA_UNIQUE_LAYER <- "lmma_unique_by_country"

# These are the IMPORTANT detailed full-attribute layers.
MPA_DETAIL_LAYER <- "mpa_by_country_individual"
LMMA_DETAIL_LAYER <- "lmma_by_country_individual"


# ------------------------------------------------------------
# 2b. Indicator inputs
# ------------------------------------------------------------
#
# data_type:
#   "auto"   = infer from extension
#   "vector" = SHP / GPKG / GeoJSON
#   "raster" = VRT / TIF / TIFF / etc.
#
# measure_type:
#   "auto"   = infer from vector geometry
#   "area"   = polygon/raster area
#   "points" = point count
#
# filter_expr:
#   Optional dplyr filter used ONLY FOR THE SUMMARY.
#
#   The expensive vector intersections are saved BEFORE this
#   filter is applied.
#
#   Therefore you can change filter_expr later without repeating
#   the spatial overlay.
#
# Examples:
#   "status == 'confirmed'"
#   "score >= 3"
#   "OutDegP5 > 0 & InDegP5 > 0"
#
# NOTE:
#   The table below preserves your currently active indicator.
#   Uncomment/add other indicators as required.
# ------------------------------------------------------------

indicator_inputs <- tibble::tribble(
  ~path, ~layer, ~indicator, ~data_type, ~measure_type, ~filter_expr,
  
  # "indicators/WIO_Mangroves_WCMC/WIO_Mangrove.shp",
  # NA_character_, "Mangroves", "auto", "area", NA_character_,
  
  # "indicators/WIO_Geomorphic/Seamounts.shp",
  # NA_character_, "Seamounts", "auto", "area", NA_character_,
  
  # "indicators/KBA_wio/KBA_wio.shp",
  # NA_character_, "KBAs", "auto", "area", NA_character_,
  
  # "indicators/IBA_wio/IBA_wio.shp",
  # NA_character_, "IBAs", "auto", "area", NA_character_,
  
  "indicators/wio_coral_allen_wcmc/wio_coral_allen_wcmc.shp",
  NA_character_, "Coral", "auto", "area", NA_character_
  
  # "indicators/obis_seamap_swot_6a79375d314f6_20260809_223819_site_locations_shapefile_99283/obis_seamap_swot_6a79375d314f6_20260809_223819_site_locations_shapefile.shp",
  # NA_character_, "Turtles", "auto", "points", NA_character_,
  
  # "indicators/Connectivity/Connectivity.shp",
  # NA_character_, "Larval Dispersal", "auto", "points",  NA_character_,
  
  # Raster example - point this to your actual VRT/TIF:
  # ,"indicators/GlobalSeagrass2023_2024/seagrass_wio_crop.tif",
  # NA_character_, "Seagrass", "raster", "area", NA_character_
)


# Assign a fallback CRS ONLY if an indicator genuinely lacks CRS metadata.
SOURCE_INDICATOR_CRS_IF_MISSING <- NA_character_


# ------------------------------------------------------------
# 2c. Raster settings
# ------------------------------------------------------------

# "nonzero" = habitat where raster value != 0 and is not NA
# "not_na"  = habitat everywhere raster is not NA
RASTER_PRESENCE_RULE <- "nonzero"
RASTER_LAYER_INDEX <- 1


# ------------------------------------------------------------
# 2d. Spatial settings
# ------------------------------------------------------------

WIO_BBOX <- c(
  xmin = 20,
  xmax = 85,
  ymin = -40,
  ymax = 20
)

# Normally FALSE because EEZ layers already constrain analysis.
CLIP_VECTOR_INDICATORS_TO_WIO_BBOX <- FALSE

# TRUE is recommended for final habitat-area calculations.
# It prevents overlapping polygons within the SAME indicator
# from being counted twice after the spatial intersections.
AVOID_INTERNAL_INDICATOR_DOUBLE_COUNTING <- TRUE

# Subdivide large polygon indicators before expensive overlay.
# Attributes and source IDs are preserved.
SUBDIVIDE_COMPLEX_GEOMETRIES <- TRUE
SUBDIVIDE_MAX_VERTICES <- 512

MAKE_CHECK_MAP <- F


# ------------------------------------------------------------
# 2e. Output / cache settings
# ------------------------------------------------------------

out_dir <- file.path("outputs", "element3")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

intersection_dir <- file.path(out_dir, "intersections")
dir.create(intersection_dir, showWarnings = FALSE, recursive = TRUE)

summary_cache_dir <- file.path(out_dir, "summary_cache")
dir.create(summary_cache_dir, showWarnings = FALSE, recursive = TRUE)

# FALSE = reuse valid saved intersections.
# TRUE  = force all vector spatial overlays to be rebuilt.
FORCE_RERUN_SPATIAL <- FALSE

# FALSE = reuse a valid summary CSV where possible.
# TRUE  = recalculate summaries from the saved intersections.
FORCE_RERUN_SUMMARY <- FALSE

SPATIAL_CACHE_VERSION <- "element3_spatial_full_attributes_v1"
SUMMARY_CACHE_VERSION <- "element3_summary_from_saved_intersections_v1"


# ============================================================
# 3. BASIC INPUT CHECKS
# ============================================================

if (!file.exists(PROTECTION_GPKG)) {
  stop(
    "Element 1 protection GeoPackage not found:\n",
    PROTECTION_GPKG
  )
}

if (nrow(indicator_inputs) == 0) {
  stop("No indicators are listed in indicator_inputs.")
}

missing_indicator_files <- indicator_inputs |>
  dplyr::filter(!file.exists(path))

if (nrow(missing_indicator_files) > 0) {
  stop(
    "The following indicator files do not exist:\n\n",
    paste(missing_indicator_files$path, collapse = "\n")
  )
}


# ============================================================
# 4. HELPER FUNCTIONS
# ============================================================


timer <- function(label, expr) {
  message("\n--- ", label, " ---")
  t <- system.time(out <- force(expr))
  message(label, " elapsed seconds: ", round(t[["elapsed"]], 2))
  out
}


clean_filename <- function(x) {
  x |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("[^a-z0-9]+", "_") |>
    stringr::str_replace_all("^_|_$", "")
}


safe_divide <- function(num, den) {
  ifelse(!is.na(den) & den > 0, num / den, NA_real_)
}


sum_or_na <- function(x) {
  if (all(is.na(x))) {
    return(NA_real_)
  }
  sum(x, na.rm = TRUE)
}


sum_int_or_na <- function(x) {
  if (all(is.na(x))) {
    return(NA_integer_)
  }
  as.integer(sum(x, na.rm = TRUE))
}


read_sf_any <- function(path, layer = NA_character_) {
  layer_missing <- is.null(layer) ||
    length(layer) == 0 ||
    is.na(layer) ||
    !nzchar(layer)
  
  if (!file.exists(path)) {
    stop("File not found: ", path)
  }
  
  if (layer_missing) {
    sf::st_read(path, quiet = FALSE)
  } else {
    sf::st_read(path, layer = layer, quiet = FALSE)
  }
}


read_required_gpkg_layer <- function(gpkg, layer) {
  available <- sf::st_layers(gpkg)$name
  
  if (!(layer %in% available)) {
    stop(
      "Required layer not found in Element 1 GeoPackage: ", layer,
      "\n\nAvailable layers:\n",
      paste(available, collapse = "\n")
    )
  }
  
  sf::st_read(gpkg, layer = layer, quiet = FALSE)
}


standardise_geometry_column <- function(x) {
  if (!inherits(x, "sf")) {
    stop("standardise_geometry_column() expects an sf object.")
  }
  
  geom_col <- attr(x, "sf_column")
  
  if (!is.null(geom_col) && geom_col != "geometry") {
    names(x)[names(x) == geom_col] <- "geometry"
    sf::st_geometry(x) <- "geometry"
  }
  
  x
}


make_valid_polygonal <- function(x) {
  if (!inherits(x, "sf")) {
    stop("make_valid_polygonal() expects an sf object.")
  }
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  x <- suppressWarnings(sf::st_make_valid(x))
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  geom_types <- as.character(sf::st_geometry_type(x, by_geometry = TRUE))
  
  if (any(geom_types %in% c("GEOMETRY", "GEOMETRYCOLLECTION"))) {
    x <- suppressWarnings(
      sf::st_collection_extract(x, "POLYGON", warn = FALSE)
    )
  }
  
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  geom_types <- as.character(sf::st_geometry_type(x, by_geometry = TRUE))
  
  x <- x[
    geom_types %in% c("POLYGON", "MULTIPOLYGON"),
    ,
    drop = FALSE
  ]
  
  standardise_geometry_column(x)
}


make_point_sf <- function(x) {
  if (!inherits(x, "sf")) {
    stop("make_point_sf() expects an sf object.")
  }
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  geom_types <- as.character(sf::st_geometry_type(x, by_geometry = TRUE))
  
  if (any(geom_types == "GEOMETRYCOLLECTION")) {
    x <- suppressWarnings(
      sf::st_collection_extract(x, "POINT", warn = FALSE)
    )
  }
  
  geom_types <- as.character(sf::st_geometry_type(x, by_geometry = TRUE))
  
  if (any(geom_types == "MULTIPOINT")) {
    x <- suppressWarnings(sf::st_cast(x, "POINT", warn = FALSE))
  }
  
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  geom_types <- as.character(sf::st_geometry_type(x, by_geometry = TRUE))
  
  if (!all(geom_types == "POINT")) {
    stop(
      "Point indicator contains non-point geometry after cleaning: ",
      paste(unique(geom_types), collapse = ", ")
    )
  }
  
  standardise_geometry_column(x)
}


infer_data_type <- function(path, data_type = "auto") {
  data_type <- stringr::str_to_lower(data_type)
  
  if (data_type %in% c("vector", "raster")) {
    return(data_type)
  }
  
  ext <- stringr::str_to_lower(tools::file_ext(path))
  
  if (ext %in% c("shp", "gpkg", "geojson", "json")) {
    return("vector")
  }
  
  if (ext %in% c("vrt", "tif", "tiff", "img", "grd", "nc")) {
    return("raster")
  }
  
  stop("Could not infer data_type for: ", path)
}


infer_measure_type_from_sf <- function(x) {
  geom_types <- unique(
    as.character(sf::st_geometry_type(x, by_geometry = TRUE))
  )
  
  if (all(geom_types %in% c("POINT", "MULTIPOINT"))) {
    return("points")
  }
  
  if (any(geom_types %in% c("POLYGON", "MULTIPOLYGON", "GEOMETRYCOLLECTION"))) {
    return("area")
  }
  
  stop(
    "Could not infer measure_type from geometry types: ",
    paste(geom_types, collapse = ", ")
  )
}


apply_optional_filter <- function(x, filter_expr, indicator) {
  no_filter <- is.null(filter_expr) ||
    length(filter_expr) == 0 ||
    is.na(filter_expr) ||
    !nzchar(stringr::str_squish(filter_expr)) ||
    stringr::str_squish(filter_expr) == "TRUE"
  
  if (no_filter) {
    return(x)
  }
  
  n_before <- nrow(x)
  
  message("Applying summary filter for ", indicator, ": ", filter_expr)
  
  expr <- tryCatch(
    rlang::parse_expr(filter_expr),
    error = function(e) {
      stop(
        "Could not parse filter_expr for '", indicator, "':\n",
        filter_expr,
        "\nOriginal error: ", conditionMessage(e)
      )
    }
  )
  
  out <- tryCatch(
    dplyr::filter(x, !!expr),
    error = function(e) {
      stop(
        "Could not apply filter_expr for '", indicator, "':\n",
        filter_expr,
        "\n\nAvailable fields:\n",
        paste(names(x), collapse = ", "),
        "\n\nOriginal error:\n",
        conditionMessage(e)
      )
    }
  )
  
  message(
    "Filter kept ", nrow(out), " of ", n_before,
    " rows for ", indicator
  )
  
  out
}


# Make a vector of names unique under SQLite/GeoPackage's
# case-insensitive field-name rules.
make_case_insensitive_unique <- function(x) {
  out <- x
  used <- character(0)
  
  for (i in seq_along(x)) {
    base <- x[[i]]
    candidate <- base
    suffix <- 1L
    
    while (tolower(candidate) %in% used) {
      suffix <- suffix + 1L
      candidate <- paste0(base, "_", suffix)
    }
    
    out[[i]] <- candidate
    used <- c(used, tolower(candidate))
  }
  
  out
}


prefix_non_geometry_fields <- function(x, prefix) {
  geom_col <- attr(x, "sf_column")
  old_names <- names(x)
  attr_idx <- which(old_names != geom_col)
  
  proposed <- paste0(prefix, old_names[attr_idx])
  proposed <- make_case_insensitive_unique(proposed)
  
  names(x)[attr_idx] <- proposed
  sf::st_geometry(x) <- geom_col
  
  x
}


assert_indicator_field_names_safe <- function(x, indicator) {
  geom_col <- attr(x, "sf_column")
  fields <- names(x)[names(x) != geom_col]
  lower_fields <- tolower(fields)
  
  duplicated_case <- duplicated(lower_fields) |
    duplicated(lower_fields, fromLast = TRUE)
  
  if (any(duplicated_case)) {
    stop(
      "Indicator '", indicator,
      "' contains field names that collide under GeoPackage/SQLite rules:\n",
      paste(fields[duplicated_case], collapse = ", "),
      "\nRename those source fields before running this script."
    )
  }
  
  invisible(TRUE)
}


crop_to_bbox <- function(x, bbox_vec) {
  bbox_poly <- sf::st_as_sfc(
    sf::st_bbox(
      c(
        xmin = bbox_vec[["xmin"]],
        xmax = bbox_vec[["xmax"]],
        ymin = bbox_vec[["ymin"]],
        ymax = bbox_vec[["ymax"]]
      ),
      crs = sf::st_crs(4326)
    )
  )
  
  bbox_poly <- sf::st_transform(bbox_poly, sf::st_crs(x))
  
  suppressWarnings(sf::st_intersection(x, bbox_poly))
}


subdivide_sf_preserve_attributes <- function(x, max_vertices = 512) {
  if (nrow(x) == 0) {
    return(x)
  }
  
  pieces <- vector("list", nrow(x))
  
  for (i in seq_len(nrow(x))) {
    one <- x[i, , drop = FALSE]
    one_geom <- sf::st_geometry(one)
    
    sub_geom <- lwgeom::st_subdivide(
      one_geom,
      max_vertices = max_vertices
    )
    
    sub_geom <- suppressWarnings(
      sf::st_collection_extract(sub_geom, "POLYGON", warn = FALSE)
    )
    
    sub_geom <- sub_geom[!sf::st_is_empty(sub_geom)]
    
    if (length(sub_geom) == 0) {
      pieces[[i]] <- NULL
      next
    }
    
    attrs <- sf::st_drop_geometry(one)
    attrs <- attrs[rep(1, length(sub_geom)), , drop = FALSE]
    
    pieces[[i]] <- sf::st_sf(
      attrs,
      geometry = sub_geom
    ) |>
      sf::st_set_crs(sf::st_crs(x))
  }
  
  pieces <- purrr::compact(pieces)
  
  if (length(pieces) == 0) {
    return(x[0, , drop = FALSE])
  }
  
  dplyr::bind_rows(pieces) |>
    standardise_geometry_column()
}


prepare_vector_indicator_unfiltered <- function(
    path,
    layer,
    indicator,
    requested_measure_type,
    target_crs,
    source_crs_if_missing = NA_character_) {
  
  x <- read_sf_any(path, layer)
  
  if (is.na(sf::st_crs(x))) {
    if (is.na(source_crs_if_missing)) {
      stop(
        "Indicator has missing CRS and no fallback was supplied: ",
        path
      )
    }
    
    message("Assigning missing CRS ", source_crs_if_missing, " to ", path)
    sf::st_crs(x) <- source_crs_if_missing
  }
  
  assert_indicator_field_names_safe(x, indicator)
  
  x <- x |>
    dplyr::mutate(
      ind_source_feature_id = dplyr::row_number(),
      ind_indicator = indicator,
      ind_source_file = basename(path)
    )
  
  if (requested_measure_type == "auto") {
    final_measure_type <- infer_measure_type_from_sf(x)
  } else {
    final_measure_type <- requested_measure_type
  }
  
  if (!final_measure_type %in% c("area", "points")) {
    stop("Unsupported measure_type: ", final_measure_type)
  }
  
  if (final_measure_type == "area") {
    x <- make_valid_polygonal(x)
  } else {
    x <- make_point_sf(x)
  }
  
  x <- sf::st_transform(x, target_crs)
  
  if (CLIP_VECTOR_INDICATORS_TO_WIO_BBOX) {
    x <- crop_to_bbox(x, WIO_BBOX)
    
    if (final_measure_type == "area") {
      x <- make_valid_polygonal(x)
    } else {
      x <- make_point_sf(x)
    }
  }
  
  # ind_record_id identifies each cleaned spatial record.
  # This is the ID used for distinct point counts.
  x <- x |>
    dplyr::mutate(ind_record_id = dplyr::row_number())
  
  if (
    final_measure_type == "area" &&
    SUBDIVIDE_COMPLEX_GEOMETRIES &&
    nrow(x) > 0
  ) {
    x <- subdivide_sf_preserve_attributes(
      x,
      max_vertices = SUBDIVIDE_MAX_VERTICES
    )
  }
  
  list(
    data = standardise_geometry_column(x),
    measure_type = final_measure_type
  )
}


clean_intersection_result <- function(x, measure_type) {
  if (nrow(x) == 0) {
    return(x)
  }
  
  if (measure_type == "area") {
    make_valid_polygonal(x)
  } else {
    make_point_sf(x)
  }
}


empty_combined_schema <- function(left_sf, right_sf) {
  left_attrs <- sf::st_drop_geometry(left_sf[0, , drop = FALSE])
  right_attrs <- sf::st_drop_geometry(right_sf[0, , drop = FALSE])
  
  attrs <- dplyr::bind_cols(left_attrs, right_attrs)
  
  sf::st_sf(
    attrs,
    geometry = sf::st_sfc(crs = sf::st_crs(left_sf))
  )
}


intersect_indicator_with_country_zones <- function(
    indicator_sf,
    zone_sf,
    zone_country_field,
    output_country_field,
    measure_type,
    label) {
  
  if (nrow(indicator_sf) == 0 || nrow(zone_sf) == 0) {
    return(indicator_sf[0, , drop = FALSE])
  }
  
  zone_use <- zone_sf |>
    dplyr::transmute(
      !!output_country_field := as.character(.data[[zone_country_field]])
    )
  
  hit <- sf::st_intersects(indicator_sf, zone_use, sparse = TRUE)
  keep <- lengths(hit) > 0
  
  if (!any(keep)) {
    out <- indicator_sf[0, , drop = FALSE]
    out[[output_country_field]] <- character(0)
    return(out)
  }
  
  message("Intersecting ", label, "...")
  
  out <- suppressWarnings(
    sf::st_intersection(
      indicator_sf[keep, , drop = FALSE],
      zone_use
    )
  )
  
  clean_intersection_result(out, measure_type)
}


find_country_field <- function(x, layer_name) {
  candidates <- c("sovereign_state", "analysis_sovereign_state")
  found <- candidates[candidates %in% names(x)]
  
  if (length(found) == 0) {
    stop(
      "Could not find a sovereign-state field in layer '",
      layer_name,
      "'. Available fields:\n",
      paste(names(x), collapse = ", ")
    )
  }
  
  found[[1]]
}


intersect_indicator_eez_with_detailed_pa <- function(
    indicator_eez_sf,
    pa_sf,
    pa_country_field,
    pa_prefix,
    measure_type,
    label) {
  
  pa_prefixed <- prefix_non_geometry_fields(pa_sf, pa_prefix)
  prefixed_country_field <- paste0(pa_prefix, pa_country_field)
  
  if (nrow(indicator_eez_sf) == 0 || nrow(pa_prefixed) == 0) {
    return(empty_combined_schema(indicator_eez_sf, pa_prefixed))
  }
  
  countries <- intersect(
    unique(as.character(indicator_eez_sf$eez_sovereign_state)),
    unique(as.character(pa_prefixed[[prefixed_country_field]]))
  )
  
  countries <- countries[!is.na(countries) & nzchar(countries)]
  
  if (length(countries) == 0) {
    return(empty_combined_schema(indicator_eez_sf, pa_prefixed))
  }
  
  results <- vector("list", length(countries))
  
  for (i in seq_along(countries)) {
    country <- countries[[i]]
    
    message(label, " - ", country)
    
    ind_sub <- indicator_eez_sf |>
      dplyr::filter(eez_sovereign_state == country)
    
    pa_sub <- pa_prefixed |>
      dplyr::filter(.data[[prefixed_country_field]] == country)
    
    if (nrow(ind_sub) == 0 || nrow(pa_sub) == 0) {
      results[[i]] <- NULL
      next
    }
    
    hit <- sf::st_intersects(ind_sub, pa_sub, sparse = TRUE)
    keep <- lengths(hit) > 0
    
    if (!any(keep)) {
      results[[i]] <- NULL
      next
    }
    
    inter <- suppressWarnings(
      sf::st_intersection(
        ind_sub[keep, , drop = FALSE],
        pa_sub
      )
    )
    
    if (nrow(inter) == 0) {
      results[[i]] <- NULL
      next
    }
    
    results[[i]] <- clean_intersection_result(inter, measure_type)
  }
  
  results <- purrr::compact(results)
  
  if (length(results) == 0) {
    return(empty_combined_schema(indicator_eez_sf, pa_prefixed))
  }
  
  dplyr::bind_rows(results) |>
    standardise_geometry_column()
}


write_gpkg_layer <- function(x, gpkg, layer) {
  if (nrow(x) == 0) {
    message("Layer is empty; not writing GPKG layer: ", layer)
    return(invisible(FALSE))
  }
  
  message("Writing spatial layer: ", layer)
  
  suppressWarnings(
    sf::st_write(
      x,
      dsn = gpkg,
      layer = layer,
      append = FALSE,
      delete_layer = TRUE,
      quiet = TRUE
    )
  )
  
  invisible(TRUE)
}


file_bundle_info <- function(path) {
  ext <- tolower(tools::file_ext(path))
  
  if (ext == "shp") {
    stem <- tools::file_path_sans_ext(path)
    candidates <- paste0(
      stem,
      c(".shp", ".dbf", ".shx", ".prj", ".cpg", ".qpj")
    )
    files <- candidates[file.exists(candidates)]
  } else {
    files <- path
  }
  
  info <- file.info(files)
  
  tibble::tibble(
    file = normalizePath(files, winslash = "/", mustWork = FALSE),
    size = info$size,
    mtime = as.character(info$mtime)
  )
}


spatial_cache_key <- function(path, indicator, measure_type) {
  digest::digest(
    list(
      indicator_files = file_bundle_info(path),
      protection_gpkg = file_bundle_info(PROTECTION_GPKG),
      indicator = indicator,
      measure_type = measure_type,
      spatial_cache_version = SPATIAL_CACHE_VERSION,
      clip_bbox = CLIP_VECTOR_INDICATORS_TO_WIO_BBOX,
      bbox = WIO_BBOX,
      subdivide = SUBDIVIDE_COMPLEX_GEOMETRIES,
      subdivide_vertices = SUBDIVIDE_MAX_VERTICES
    )
  )
}


summary_cache_key <- function(
    spatial_key,
    filter_expr,
    indicator,
    measure_type,
    data_type) {
  
  digest::digest(
    list(
      spatial_key = spatial_key,
      filter_expr = filter_expr,
      indicator = indicator,
      measure_type = measure_type,
      data_type = data_type,
      summary_cache_version = SUMMARY_CACHE_VERSION,
      avoid_internal_double_counting = AVOID_INTERNAL_INDICATOR_DOUBLE_COUNTING,
      raster_presence_rule = RASTER_PRESENCE_RULE,
      raster_layer_index = RASTER_LAYER_INDEX
    )
  )
}


read_cache_metadata <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  
  readr::read_csv(path, show_col_types = FALSE)
}


write_cache_metadata <- function(
    path,
    cache_key,
    indicator,
    measure_type,
    n_prepared,
    n_eez,
    n_protected,
    n_mpa,
    n_lmma) {
  
  readr::write_csv(
    tibble::tibble(
      cache_key = cache_key,
      indicator = indicator,
      measure_type = measure_type,
      n_prepared = n_prepared,
      n_eez = n_eez,
      n_protected = n_protected,
      n_mpa = n_mpa,
      n_lmma = n_lmma,
      completed = TRUE,
      completed_time = as.character(Sys.time())
    ),
    path
  )
}


# ============================================================
# 5. LOAD ELEMENT 1 INTERMEDIATE LAYERS
# ============================================================

message("\n============================================================")
message("Loading Element 1 reusable protection layers")
message("============================================================")

zone_eez <- timer(
  "Load EEZ by country",
  read_required_gpkg_layer(PROTECTION_GPKG, EEZ_LAYER)
)

if (!("sovereign_state" %in% names(zone_eez))) {
  if ("analysis_sovereign_state" %in% names(zone_eez)) {
    zone_eez <- zone_eez |>
      dplyr::mutate(sovereign_state = analysis_sovereign_state)
  } else {
    stop("EEZ layer contains no sovereign_state field.")
  }
}

ANALYSIS_CRS <- sf::st_crs(zone_eez)

if (is.na(ANALYSIS_CRS)) {
  stop("Element 1 EEZ layer has missing CRS.")
}

if (!("eez_area_km2" %in% names(zone_eez))) {
  zone_eez$eez_area_km2 <- as.numeric(sf::st_area(zone_eez)) / 1e6
}

eez_table <- zone_eez |>
  sf::st_drop_geometry() |>
  dplyr::select(sovereign_state, eez_area_km2)

zone_protected <- timer(
  "Load unique combined MPA + LMMA footprint",
  read_required_gpkg_layer(PROTECTION_GPKG, PROTECTED_UNIQUE_LAYER) |>
    sf::st_transform(ANALYSIS_CRS)
)

if (!("sovereign_state" %in% names(zone_protected))) {
  zone_protected <- zone_protected |>
    dplyr::mutate(sovereign_state = analysis_sovereign_state)
}

zone_mpa_unique <- timer(
  "Load unique MPA footprint",
  read_required_gpkg_layer(PROTECTION_GPKG, MPA_UNIQUE_LAYER) |>
    sf::st_transform(ANALYSIS_CRS)
)

if (!("sovereign_state" %in% names(zone_mpa_unique))) {
  zone_mpa_unique <- zone_mpa_unique |>
    dplyr::mutate(sovereign_state = analysis_sovereign_state)
}

zone_lmma_unique <- timer(
  "Load unique LMMA footprint",
  read_required_gpkg_layer(PROTECTION_GPKG, LMMA_UNIQUE_LAYER) |>
    sf::st_transform(ANALYSIS_CRS)
)

if (!("sovereign_state" %in% names(zone_lmma_unique))) {
  zone_lmma_unique <- zone_lmma_unique |>
    dplyr::mutate(sovereign_state = analysis_sovereign_state)
}

mpa_detail <- timer(
  "Load full-attribute MPA x EEZ layer",
  read_required_gpkg_layer(PROTECTION_GPKG, MPA_DETAIL_LAYER) |>
    sf::st_transform(ANALYSIS_CRS)
)

lmma_detail <- timer(
  "Load full-attribute LMMA x EEZ layer",
  read_required_gpkg_layer(PROTECTION_GPKG, LMMA_DETAIL_LAYER) |>
    sf::st_transform(ANALYSIS_CRS)
)

mpa_country_field <- find_country_field(mpa_detail, MPA_DETAIL_LAYER)
lmma_country_field <- find_country_field(lmma_detail, LMMA_DETAIL_LAYER)

zone_eez <- zone_eez |>
  dplyr::select(sovereign_state)

zone_protected <- zone_protected |>
  dplyr::select(sovereign_state)

zone_mpa_unique <- zone_mpa_unique |>
  dplyr::select(sovereign_state)

zone_lmma_unique <- zone_lmma_unique |>
  dplyr::select(sovereign_state)

message("\nLoaded analysis zones:")
message("  EEZ countries:             ", nrow(zone_eez))
message("  Combined protected zones:  ", nrow(zone_protected))
message("  Unique MPA zones:          ", nrow(zone_mpa_unique))
message("  Unique LMMA zones:         ", nrow(zone_lmma_unique))
message("  Detailed MPA x EEZ rows:   ", nrow(mpa_detail))
message("  Detailed LMMA x EEZ rows:  ", nrow(lmma_detail))


# ============================================================
# 6. OPTIONAL QA MAP
# ============================================================

if (MAKE_CHECK_MAP) {
  world <- rnaturalearth::ne_countries(
    scale = "medium",
    returnclass = "sf"
  )
  
  wio_map <- ggplot() +
    geom_sf(
      data = world,
      fill = "grey90",
      colour = "white",
      linewidth = 0.2
    ) +
    geom_sf(
      data = sf::st_transform(zone_eez, 4326),
      fill = "lightblue",
      colour = "grey40",
      alpha = 0.25,
      linewidth = 0.25
    ) +
    geom_sf(
      data = sf::st_transform(zone_protected, 4326),
      fill = "darkgreen",
      colour = NA,
      alpha = 0.5
    ) +
    coord_sf(
      xlim = c(WIO_BBOX[["xmin"]], WIO_BBOX[["xmax"]]),
      ylim = c(WIO_BBOX[["ymin"]], WIO_BBOX[["ymax"]]),
      expand = FALSE
    ) +
    labs(
      title = "Element 3 analysis zones",
      subtitle = "Loaded directly from Element 1 reusable GeoPackage",
      x = "Longitude",
      y = "Latitude"
    ) +
    theme_minimal()
  
  print(wio_map)
  
  ggsave(
    filename = file.path(out_dir, "element3_zone_check_map.png"),
    plot = wio_map,
    width = 10,
    height = 7,
    dpi = 300
  )
}


# ============================================================
# 7. VECTOR SPATIAL CACHE
# ============================================================

determine_vector_measure_type <- function(path, layer, requested_measure_type) {
  if (requested_measure_type %in% c("area", "points")) {
    return(requested_measure_type)
  }
  
  probe <- read_sf_any(path, layer)
  infer_measure_type_from_sf(probe)
}


build_or_load_vector_intersections <- function(
    path,
    layer,
    indicator,
    requested_measure_type) {
  
  indicator_slug <- clean_filename(indicator)
  
  gpkg <- file.path(
    intersection_dir,
    paste0(indicator_slug, "_intersections.gpkg")
  )
  
  metadata_file <- file.path(
    intersection_dir,
    paste0(indicator_slug, "_spatial_cache_metadata.csv")
  )
  
  # Determine the final measure type without doing the expensive
  # geometry preparation. If the spatial cache is valid, the raw
  # indicator therefore does not need to be repaired/subdivided again.
  final_measure_type <- determine_vector_measure_type(
    path = path,
    layer = layer,
    requested_measure_type = requested_measure_type
  )
  
  key <- spatial_cache_key(
    path = path,
    indicator = indicator,
    measure_type = final_measure_type
  )
  
  metadata <- read_cache_metadata(metadata_file)
  
  cache_valid <- FALSE
  
  if (
    !FORCE_RERUN_SPATIAL &&
    file.exists(gpkg) &&
    !is.null(metadata) &&
    nrow(metadata) > 0 &&
    identical(as.character(metadata$cache_key[[1]]), as.character(key)) &&
    isTRUE(metadata$completed[[1]])
  ) {
    available_layers <- sf::st_layers(gpkg)$name
    
    cache_valid <- "indicator_prepared_unfiltered" %in% available_layers
    
    if (cache_valid && metadata$n_eez[[1]] > 0) {
      cache_valid <- "indicator_x_eez" %in% available_layers
    }
    
    if (cache_valid && metadata$n_protected[[1]] > 0) {
      cache_valid <- "indicator_x_protected_unique" %in% available_layers
    }
    
    if (cache_valid && metadata$n_mpa[[1]] > 0) {
      cache_valid <- "indicator_x_mpa_full" %in% available_layers
    }
    
    if (cache_valid && metadata$n_lmma[[1]] > 0) {
      cache_valid <- "indicator_x_lmma_full" %in% available_layers
    }
  }
  
  if (cache_valid) {
    message("\nReusing saved spatial intersections for: ", indicator)
    
    available_layers <- sf::st_layers(gpkg)$name
    
    prepared <- sf::st_read(
      gpkg,
      layer = "indicator_prepared_unfiltered",
      quiet = FALSE
    )
    
    if ("indicator_x_eez" %in% available_layers) {
      x_eez <- sf::st_read(
        gpkg,
        layer = "indicator_x_eez",
        quiet = FALSE
      )
    } else {
      x_eez <- prepared[0, , drop = FALSE]
      x_eez$eez_sovereign_state <- character(0)
    }
    
    if ("indicator_x_protected_unique" %in% available_layers) {
      x_protected <- sf::st_read(
        gpkg,
        layer = "indicator_x_protected_unique",
        quiet = FALSE
      )
    } else {
      x_protected <- x_eez[0, , drop = FALSE]
    }
    
    if ("indicator_x_mpa_full" %in% available_layers) {
      x_mpa <- sf::st_read(
        gpkg,
        layer = "indicator_x_mpa_full",
        quiet = FALSE
      )
    } else {
      x_mpa <- x_eez[0, , drop = FALSE]
    }
    
    if ("indicator_x_lmma_full" %in% available_layers) {
      x_lmma <- sf::st_read(
        gpkg,
        layer = "indicator_x_lmma_full",
        quiet = FALSE
      )
    } else {
      x_lmma <- x_eez[0, , drop = FALSE]
    }
    
    return(
      list(
        prepared = prepared,
        x_eez = x_eez,
        x_protected = x_protected,
        x_mpa = x_mpa,
        x_lmma = x_lmma,
        measure_type = final_measure_type,
        spatial_key = key,
        gpkg = gpkg
      )
    )
  }
  
  message("\n============================================================")
  message("BUILDING SPATIAL CACHE: ", indicator)
  message("============================================================")
  
  prepared_result <- prepare_vector_indicator_unfiltered(
    path = path,
    layer = layer,
    indicator = indicator,
    requested_measure_type = final_measure_type,
    target_crs = ANALYSIS_CRS,
    source_crs_if_missing = SOURCE_INDICATOR_CRS_IF_MISSING
  )
  
  prepared <- prepared_result$data
  
  # Start fresh for this indicator if rebuilding.
  if (file.exists(gpkg)) {
    unlink(gpkg)
  }
  
  # Save unfiltered prepared indicator.
  write_gpkg_layer(
    prepared,
    gpkg,
    "indicator_prepared_unfiltered"
  )
  
  x_eez <- timer(
    paste0(indicator, ": unfiltered indicator x EEZ"),
    intersect_indicator_with_country_zones(
      indicator_sf = prepared,
      zone_sf = zone_eez,
      zone_country_field = "sovereign_state",
      output_country_field = "eez_sovereign_state",
      measure_type = final_measure_type,
      label = paste0(indicator, " x EEZ")
    )
  )
  
  write_gpkg_layer(
    x_eez,
    gpkg,
    "indicator_x_eez"
  )
  
  x_protected <- timer(
    paste0(indicator, ": unfiltered indicator x unique protected footprint"),
    intersect_indicator_with_country_zones(
      indicator_sf = prepared,
      zone_sf = zone_protected,
      zone_country_field = "sovereign_state",
      output_country_field = "eez_sovereign_state",
      measure_type = final_measure_type,
      label = paste0(indicator, " x protected unique")
    )
  )
  
  write_gpkg_layer(
    x_protected,
    gpkg,
    "indicator_x_protected_unique"
  )
  
  x_mpa <- timer(
    paste0(indicator, ": unfiltered indicator x FULL MPA attributes"),
    intersect_indicator_eez_with_detailed_pa(
      indicator_eez_sf = x_eez,
      pa_sf = mpa_detail,
      pa_country_field = mpa_country_field,
      pa_prefix = "mpa_",
      measure_type = final_measure_type,
      label = paste0(indicator, " x MPA")
    )
  )
  
  write_gpkg_layer(
    x_mpa,
    gpkg,
    "indicator_x_mpa_full"
  )
  
  x_lmma <- timer(
    paste0(indicator, ": unfiltered indicator x FULL LMMA attributes"),
    intersect_indicator_eez_with_detailed_pa(
      indicator_eez_sf = x_eez,
      pa_sf = lmma_detail,
      pa_country_field = lmma_country_field,
      pa_prefix = "lmma_",
      measure_type = final_measure_type,
      label = paste0(indicator, " x LMMA")
    )
  )
  
  write_gpkg_layer(
    x_lmma,
    gpkg,
    "indicator_x_lmma_full"
  )
  
  write_cache_metadata(
    path = metadata_file,
    cache_key = key,
    indicator = indicator,
    measure_type = final_measure_type,
    n_prepared = nrow(prepared),
    n_eez = nrow(x_eez),
    n_protected = nrow(x_protected),
    n_mpa = nrow(x_mpa),
    n_lmma = nrow(x_lmma)
  )
  
  list(
    prepared = prepared,
    x_eez = x_eez,
    x_protected = x_protected,
    x_mpa = x_mpa,
    x_lmma = x_lmma,
    measure_type = final_measure_type,
    spatial_key = key,
    gpkg = gpkg
  )
}


# ============================================================
# 8. SUMMARY HELPERS FROM SAVED VECTOR INTERSECTIONS
# ============================================================

area_from_intersection <- function(
    x,
    area_col,
    avoid_internal_double_counting = TRUE) {
  
  if (nrow(x) == 0) {
    out <- tibble::tibble(sovereign_state = character())
    out[[area_col]] <- numeric()
    return(out)
  }
  
  if (!("eez_sovereign_state" %in% names(x))) {
    stop("Saved intersection lacks eez_sovereign_state.")
  }
  
  if (avoid_internal_double_counting) {
    area_sf <- x |>
      dplyr::select(eez_sovereign_state) |>
      dplyr::group_by(eez_sovereign_state) |>
      dplyr::summarise(.groups = "drop") |>
      make_valid_polygonal()
    
    area_sf$.area_km2 <- as.numeric(sf::st_area(area_sf)) / 1e6
    
    out <- area_sf |>
      sf::st_drop_geometry() |>
      dplyr::transmute(
        sovereign_state = eez_sovereign_state,
        .area_km2 = .area_km2
      )
  } else {
    x$.area_km2 <- as.numeric(sf::st_area(x)) / 1e6
    
    out <- x |>
      sf::st_drop_geometry() |>
      dplyr::group_by(eez_sovereign_state) |>
      dplyr::summarise(
        .area_km2 = sum(.area_km2, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::transmute(
        sovereign_state = eez_sovereign_state,
        .area_km2 = .area_km2
      )
  }
  
  names(out)[names(out) == ".area_km2"] <- area_col
  out
}


count_points_from_intersection <- function(x, count_col) {
  if (nrow(x) == 0) {
    out <- tibble::tibble(sovereign_state = character())
    out[[count_col]] <- integer()
    return(out)
  }
  
  if (!("eez_sovereign_state" %in% names(x))) {
    stop("Saved point intersection lacks eez_sovereign_state.")
  }
  
  if (!("ind_record_id" %in% names(x))) {
    stop("Saved point intersection lacks ind_record_id.")
  }
  
  out <- x |>
    sf::st_drop_geometry() |>
    dplyr::distinct(eez_sovereign_state, ind_record_id) |>
    dplyr::count(eez_sovereign_state, name = count_col) |>
    dplyr::rename(sovereign_state = eez_sovereign_state)
  
  out[[count_col]] <- as.integer(out[[count_col]])
  out
}


join_result_tables <- function(base_table, ...) {
  out <- base_table
  tbls <- list(...)
  
  for (tbl in tbls) {
    out <- out |>
      dplyr::left_join(tbl, by = "sovereign_state")
  }
  
  out |>
    dplyr::mutate(
      dplyr::across(
        dplyr::ends_with("_km2"),
        ~ tidyr::replace_na(.x, 0)
      ),
      dplyr::across(
        dplyr::ends_with("_count"),
        ~ tidyr::replace_na(.x, 0L)
      )
    )
}


summarise_vector_indicator <- function(
    intersections,
    indicator,
    filter_expr) {
  
  measure_type <- intersections$measure_type
  
  # IMPORTANT:
  # Apply the indicator filter AFTER the expensive overlays.
  x_eez <- apply_optional_filter(
    intersections$x_eez,
    filter_expr,
    indicator
  )
  
  x_protected <- apply_optional_filter(
    intersections$x_protected,
    filter_expr,
    indicator
  )
  
  x_mpa <- apply_optional_filter(
    intersections$x_mpa,
    filter_expr,
    indicator
  )
  
  x_lmma <- apply_optional_filter(
    intersections$x_lmma,
    filter_expr,
    indicator
  )
  
  if (measure_type == "area") {
    indicator_tbl <- area_from_intersection(
      x_eez,
      "indicator_area_km2",
      AVOID_INTERNAL_INDICATOR_DOUBLE_COUNTING
    )
    
    protected_tbl <- area_from_intersection(
      x_protected,
      "protected_indicator_area_km2",
      AVOID_INTERNAL_INDICATOR_DOUBLE_COUNTING
    )
    
    mpa_tbl <- area_from_intersection(
      x_mpa,
      "mpa_indicator_area_km2",
      TRUE
    )
    
    lmma_tbl <- area_from_intersection(
      x_lmma,
      "lmma_indicator_area_km2",
      TRUE
    )
    
    out <- join_result_tables(
      eez_table,
      indicator_tbl,
      protected_tbl,
      mpa_tbl,
      lmma_tbl
    ) |>
      dplyr::mutate(
        indicator_point_count = NA_integer_,
        protected_indicator_point_count = NA_integer_,
        mpa_indicator_point_count = NA_integer_,
        lmma_indicator_point_count = NA_integer_
      )
    
  } else if (measure_type == "points") {
    indicator_tbl <- count_points_from_intersection(
      x_eez,
      "indicator_point_count"
    )
    
    protected_tbl <- count_points_from_intersection(
      x_protected,
      "protected_indicator_point_count"
    )
    
    mpa_tbl <- count_points_from_intersection(
      x_mpa,
      "mpa_indicator_point_count"
    )
    
    lmma_tbl <- count_points_from_intersection(
      x_lmma,
      "lmma_indicator_point_count"
    )
    
    out <- join_result_tables(
      eez_table,
      indicator_tbl,
      protected_tbl,
      mpa_tbl,
      lmma_tbl
    ) |>
      dplyr::mutate(
        indicator_area_km2 = NA_real_,
        protected_indicator_area_km2 = NA_real_,
        mpa_indicator_area_km2 = NA_real_,
        lmma_indicator_area_km2 = NA_real_
      )
    
  } else {
    stop("Unsupported measure type: ", measure_type)
  }
  
  if (measure_type == "area") {
    indicator_total_in_all_eezs_km2 <- sum(
      out$indicator_area_km2,
      na.rm = TRUE
    )
    
    indicator_total_points_in_all_eezs <- NA_integer_
    
    out <- out |>
      dplyr::mutate(
        percent_eez_covered_by_indicator =
          100 * safe_divide(indicator_area_km2, eez_area_km2),
        
        percent_of_indicator_in_all_eezs =
          100 * safe_divide(
            indicator_area_km2,
            indicator_total_in_all_eezs_km2
          ),
        
        percent_indicator_protected_total =
          100 * safe_divide(
            protected_indicator_area_km2,
            indicator_area_km2
          ),
        
        percent_indicator_protected_mpa =
          100 * safe_divide(
            mpa_indicator_area_km2,
            indicator_area_km2
          ),
        
        percent_indicator_protected_lmma =
          100 * safe_divide(
            lmma_indicator_area_km2,
            indicator_area_km2
          )
      )
    
  } else {
    indicator_total_in_all_eezs_km2 <- NA_real_
    
    indicator_total_points_in_all_eezs <- sum(
      out$indicator_point_count,
      na.rm = TRUE
    )
    
    out <- out |>
      dplyr::mutate(
        percent_eez_covered_by_indicator = NA_real_,
        
        percent_of_indicator_in_all_eezs =
          100 * safe_divide(
            indicator_point_count,
            indicator_total_points_in_all_eezs
          ),
        
        percent_indicator_protected_total =
          100 * safe_divide(
            protected_indicator_point_count,
            indicator_point_count
          ),
        
        percent_indicator_protected_mpa =
          100 * safe_divide(
            mpa_indicator_point_count,
            indicator_point_count
          ),
        
        percent_indicator_protected_lmma =
          100 * safe_divide(
            lmma_indicator_point_count,
            indicator_point_count
          )
      )
  }
  
  out |>
    dplyr::mutate(
      indicator = indicator,
      data_type = "vector",
      measure_type = measure_type,
      filter_expr_applied = ifelse(
        is.na(filter_expr) || !nzchar(stringr::str_squish(filter_expr)),
        NA_character_,
        filter_expr
      ),
      indicator_total_in_all_eezs_km2 = indicator_total_in_all_eezs_km2,
      indicator_total_points_in_all_eezs = indicator_total_points_in_all_eezs
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
      lmma_indicator_area_km2,
      indicator_point_count,
      protected_indicator_point_count,
      mpa_indicator_point_count,
      lmma_indicator_point_count,
      indicator_total_in_all_eezs_km2,
      indicator_total_points_in_all_eezs,
      percent_eez_covered_by_indicator,
      percent_of_indicator_in_all_eezs,
      percent_indicator_protected_total,
      percent_indicator_protected_mpa,
      percent_indicator_protected_lmma
    )
}


# ============================================================
# 9. RASTER HELPERS
# ============================================================

bbox_sf_4326 <- function(bbox_vec) {
  sf::st_sf(
    geometry = sf::st_as_sfc(
      sf::st_bbox(
        c(
          xmin = bbox_vec[["xmin"]],
          xmax = bbox_vec[["xmax"]],
          ymin = bbox_vec[["ymin"]],
          ymax = bbox_vec[["ymax"]]
        ),
        crs = sf::st_crs(4326)
      )
    )
  )
}


prepare_raster_area_layer <- function(
    path,
    bbox_vec,
    presence_rule = "nonzero",
    layer_index = 1,
    source_crs_if_missing = NA_character_) {
  
  r <- terra::rast(path)
  
  if (terra::nlyr(r) < layer_index) {
    stop(
      "Raster has fewer layers than requested. File: ", path,
      "; nlyr = ", terra::nlyr(r),
      "; requested layer = ", layer_index
    )
  }
  
  if (is.na(terra::crs(r)) || terra::crs(r) == "") {
    if (is.na(source_crs_if_missing)) {
      stop("Raster has missing CRS: ", path)
    }
    
    terra::crs(r) <- source_crs_if_missing
  }
  
  r <- r[[layer_index]]
  
  wio_box <- bbox_sf_4326(bbox_vec)
  wio_box <- sf::st_transform(wio_box, terra::crs(r))
  
  r <- terra::crop(r, terra::vect(wio_box))
  
  if (presence_rule == "nonzero") {
    presence <- terra::ifel(!is.na(r) & r != 0, 1, NA)
  } else if (presence_rule == "not_na") {
    presence <- terra::ifel(!is.na(r), 1, NA)
  } else {
    stop("Unknown RASTER_PRESENCE_RULE: ", presence_rule)
  }
  
  names(presence) <- "presence"
  
  cell_area_km2 <- terra::cellSize(presence, unit = "km")
  area_raster <- cell_area_km2 * presence
  names(area_raster) <- "indicator_area_km2"
  
  area_raster
}


raster_area_by_zone <- function(area_raster, zone_sf, area_col, label) {
  if (nrow(zone_sf) == 0) {
    out <- tibble::tibble(sovereign_state = character())
    out[[area_col]] <- numeric()
    return(out)
  }
  
  zone_sf <- zone_sf |>
    dplyr::mutate(.zone_id = dplyr::row_number()) |>
    dplyr::select(.zone_id, sovereign_state)
  
  zone_metadata <- zone_sf |>
    sf::st_drop_geometry()
  
  zone_vect <- zone_sf |>
    sf::st_transform(terra::crs(area_raster)) |>
    terra::vect()
  
  ex <- tryCatch(
    terra::extract(area_raster, zone_vect, exact = TRUE),
    error = function(e) {
      message("Raster extraction failed for ", label, ": ", conditionMessage(e))
      NULL
    }
  )
  
  if (is.null(ex) || nrow(ex) == 0) {
    out <- tibble::tibble(sovereign_state = character())
    out[[area_col]] <- numeric()
    return(out)
  }
  
  value_col <- names(area_raster)[[1]]
  
  fraction_col <- intersect(
    c("fraction", "coverage_fraction", "weight", "weights"),
    names(ex)
  )
  
  if (length(fraction_col) > 0) {
    fraction_col <- fraction_col[[1]]
    ex$.area_km2 <- ex[[value_col]] * ex[[fraction_col]]
  } else {
    ex$.area_km2 <- ex[[value_col]]
  }
  
  ex |>
    dplyr::left_join(
      zone_metadata,
      by = c("ID" = ".zone_id")
    ) |>
    dplyr::group_by(sovereign_state) |>
    dplyr::summarise(
      !!area_col := sum(.area_km2, na.rm = TRUE),
      .groups = "drop"
    )
}


summarise_raster_indicator <- function(path, indicator, filter_expr) {
  if (!is.na(filter_expr) && nzchar(stringr::str_squish(filter_expr))) {
    warning(
      "filter_expr is ignored for raster indicator '", indicator,
      "'. Raster filtering must be represented by the raster values/presence rule."
    )
  }
  
  area_raster <- timer(
    paste0(indicator, ": prepare raster area"),
    prepare_raster_area_layer(
      path = path,
      bbox_vec = WIO_BBOX,
      presence_rule = RASTER_PRESENCE_RULE,
      layer_index = RASTER_LAYER_INDEX,
      source_crs_if_missing = SOURCE_INDICATOR_CRS_IF_MISSING
    )
  )
  
  indicator_tbl <- timer(
    paste0(indicator, ": raster x EEZ"),
    raster_area_by_zone(
      area_raster,
      zone_eez,
      "indicator_area_km2",
      paste0(indicator, " raster x EEZ")
    )
  )
  
  protected_tbl <- timer(
    paste0(indicator, ": raster x protected unique"),
    raster_area_by_zone(
      area_raster,
      zone_protected,
      "protected_indicator_area_km2",
      paste0(indicator, " raster x protected unique")
    )
  )
  
  mpa_tbl <- timer(
    paste0(indicator, ": raster x MPA unique"),
    raster_area_by_zone(
      area_raster,
      zone_mpa_unique,
      "mpa_indicator_area_km2",
      paste0(indicator, " raster x MPA")
    )
  )
  
  lmma_tbl <- timer(
    paste0(indicator, ": raster x LMMA unique"),
    raster_area_by_zone(
      area_raster,
      zone_lmma_unique,
      "lmma_indicator_area_km2",
      paste0(indicator, " raster x LMMA")
    )
  )
  
  out <- join_result_tables(
    eez_table,
    indicator_tbl,
    protected_tbl,
    mpa_tbl,
    lmma_tbl
  ) |>
    dplyr::mutate(
      indicator_point_count = NA_integer_,
      protected_indicator_point_count = NA_integer_,
      mpa_indicator_point_count = NA_integer_,
      lmma_indicator_point_count = NA_integer_
    )
  
  total_area <- sum(out$indicator_area_km2, na.rm = TRUE)
  
  out |>
    dplyr::mutate(
      indicator = indicator,
      data_type = "raster",
      measure_type = "area",
      filter_expr_applied = NA_character_,
      indicator_total_in_all_eezs_km2 = total_area,
      indicator_total_points_in_all_eezs = NA_integer_,
      percent_eez_covered_by_indicator =
        100 * safe_divide(indicator_area_km2, eez_area_km2),
      percent_of_indicator_in_all_eezs =
        100 * safe_divide(indicator_area_km2, total_area),
      percent_indicator_protected_total =
        100 * safe_divide(protected_indicator_area_km2, indicator_area_km2),
      percent_indicator_protected_mpa =
        100 * safe_divide(mpa_indicator_area_km2, indicator_area_km2),
      percent_indicator_protected_lmma =
        100 * safe_divide(lmma_indicator_area_km2, indicator_area_km2)
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
      lmma_indicator_area_km2,
      indicator_point_count,
      protected_indicator_point_count,
      mpa_indicator_point_count,
      lmma_indicator_point_count,
      indicator_total_in_all_eezs_km2,
      indicator_total_points_in_all_eezs,
      percent_eez_covered_by_indicator,
      percent_of_indicator_in_all_eezs,
      percent_indicator_protected_total,
      percent_indicator_protected_mpa,
      percent_indicator_protected_lmma
    )
}


# ============================================================
# 10. PREPARE INDICATOR TABLE
# ============================================================

indicator_inputs <- indicator_inputs |>
  dplyr::mutate(
    data_type = purrr::map2_chr(path, data_type, infer_data_type),
    measure_type = stringr::str_to_lower(measure_type)
  )

message("\nIndicators to process:")
print(indicator_inputs)


# ============================================================
# 11. PROCESS ONE INDICATOR WITH RESTARTABLE CACHING
# ============================================================

process_one_indicator <- function(j) {
  path <- indicator_inputs$path[[j]]
  layer <- indicator_inputs$layer[[j]]
  indicator <- indicator_inputs$indicator[[j]]
  data_type <- indicator_inputs$data_type[[j]]
  requested_measure_type <- indicator_inputs$measure_type[[j]]
  filter_expr <- indicator_inputs$filter_expr[[j]]
  
  message("\n============================================================")
  message("PROCESSING ELEMENT 3 INDICATOR: ", indicator)
  message("============================================================")
  
  if (data_type == "vector") {
    intersections <- build_or_load_vector_intersections(
      path = path,
      layer = layer,
      indicator = indicator,
      requested_measure_type = requested_measure_type
    )
    
    final_measure_type <- intersections$measure_type
    spatial_key <- intersections$spatial_key
    
    summary_key <- summary_cache_key(
      spatial_key = spatial_key,
      filter_expr = filter_expr,
      indicator = indicator,
      measure_type = final_measure_type,
      data_type = data_type
    )
    
    summary_file <- file.path(
      summary_cache_dir,
      paste0(
        clean_filename(indicator),
        "_",
        substr(summary_key, 1, 12),
        ".csv"
      )
    )
    
    if (file.exists(summary_file) && !FORCE_RERUN_SUMMARY) {
      message("Reusing summary cache for: ", indicator)
      return(readr::read_csv(summary_file, show_col_types = FALSE))
    }
    
    result <- summarise_vector_indicator(
      intersections = intersections,
      indicator = indicator,
      filter_expr = filter_expr
    )
    
    readr::write_csv(result, summary_file)
    
    message("Summary cache saved: ", summary_file)
    message("Spatial intersections saved: ", intersections$gpkg)
    
    return(result)
  }
  
  if (data_type == "raster") {
    raster_key <- digest::digest(
      list(
        file_info = file_bundle_info(path),
        protection_gpkg = file_bundle_info(PROTECTION_GPKG),
        indicator = indicator,
        requested_measure_type = requested_measure_type,
        raster_presence_rule = RASTER_PRESENCE_RULE,
        raster_layer_index = RASTER_LAYER_INDEX,
        summary_cache_version = SUMMARY_CACHE_VERSION
      )
    )
    
    summary_file <- file.path(
      summary_cache_dir,
      paste0(
        clean_filename(indicator),
        "_",
        substr(raster_key, 1, 12),
        ".csv"
      )
    )
    
    if (file.exists(summary_file) && !FORCE_RERUN_SUMMARY) {
      message("Reusing raster summary cache for: ", indicator)
      return(readr::read_csv(summary_file, show_col_types = FALSE))
    }
    
    result <- summarise_raster_indicator(
      path = path,
      indicator = indicator,
      filter_expr = filter_expr
    )
    
    readr::write_csv(result, summary_file)
    
    message("Raster summary cache saved: ", summary_file)
    
    return(result)
  }
  
  stop("Unsupported data_type: ", data_type)
}


# ============================================================
# 12. RUN INDICATORS
# ============================================================
#
# Deliberately sequential.
#
# The detailed polygon overlays can be very memory intensive.
# Each indicator is saved as soon as it finishes, so the script
# can be restarted without losing completed work.
# ============================================================

indicator_results <- vector("list", nrow(indicator_inputs))

for (j in seq_len(nrow(indicator_inputs))) {
  indicator_results[[j]] <- process_one_indicator(j)
}


# ============================================================
# 13. COMBINE COUNTRY RESULTS
# ============================================================

final_summary <- dplyr::bind_rows(indicator_results) |>
  dplyr::arrange(indicator, sovereign_state)


# ============================================================
# 14. ADD WIO REGIONAL ROW
# ============================================================
#
# Regional percentages are calculated from regional totals.
# Country percentages are NOT averaged.
# ============================================================

wio_rows <- final_summary |>
  dplyr::filter(sovereign_state != "WIO") |>
  dplyr::group_by(
    indicator,
    data_type,
    measure_type,
    filter_expr_applied
  ) |>
  dplyr::summarise(
    sovereign_state = "WIO",
    eez_area_km2 = sum_or_na(eez_area_km2),
    indicator_area_km2 = sum_or_na(indicator_area_km2),
    protected_indicator_area_km2 = sum_or_na(protected_indicator_area_km2),
    mpa_indicator_area_km2 = sum_or_na(mpa_indicator_area_km2),
    lmma_indicator_area_km2 = sum_or_na(lmma_indicator_area_km2),
    indicator_point_count = sum_int_or_na(indicator_point_count),
    protected_indicator_point_count = sum_int_or_na(protected_indicator_point_count),
    mpa_indicator_point_count = sum_int_or_na(mpa_indicator_point_count),
    lmma_indicator_point_count = sum_int_or_na(lmma_indicator_point_count),
    indicator_total_in_all_eezs_km2 =
      dplyr::first(indicator_total_in_all_eezs_km2),
    indicator_total_points_in_all_eezs =
      dplyr::first(indicator_total_points_in_all_eezs),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    percent_eez_covered_by_indicator = dplyr::case_when(
      measure_type == "area" ~
        100 * safe_divide(indicator_area_km2, eez_area_km2),
      TRUE ~ NA_real_
    ),
    
    percent_of_indicator_in_all_eezs = dplyr::case_when(
      measure_type == "area" ~
        100 * safe_divide(
          indicator_area_km2,
          indicator_total_in_all_eezs_km2
        ),
      measure_type == "points" ~
        100 * safe_divide(
          indicator_point_count,
          indicator_total_points_in_all_eezs
        ),
      TRUE ~ NA_real_
    ),
    
    percent_indicator_protected_total = dplyr::case_when(
      measure_type == "area" ~
        100 * safe_divide(
          protected_indicator_area_km2,
          indicator_area_km2
        ),
      measure_type == "points" ~
        100 * safe_divide(
          protected_indicator_point_count,
          indicator_point_count
        ),
      TRUE ~ NA_real_
    ),
    
    percent_indicator_protected_mpa = dplyr::case_when(
      measure_type == "area" ~
        100 * safe_divide(
          mpa_indicator_area_km2,
          indicator_area_km2
        ),
      measure_type == "points" ~
        100 * safe_divide(
          mpa_indicator_point_count,
          indicator_point_count
        ),
      TRUE ~ NA_real_
    ),
    
    percent_indicator_protected_lmma = dplyr::case_when(
      measure_type == "area" ~
        100 * safe_divide(
          lmma_indicator_area_km2,
          indicator_area_km2
        ),
      measure_type == "points" ~
        100 * safe_divide(
          lmma_indicator_point_count,
          indicator_point_count
        ),
      TRUE ~ NA_real_
    )
  ) |>
  dplyr::select(names(final_summary))

final_summary <- final_summary |>
  dplyr::filter(sovereign_state != "WIO") |>
  dplyr::bind_rows(wio_rows) |>
  dplyr::arrange(indicator, sovereign_state)


# ============================================================
# 15. QA CHECKS
# ============================================================

message("\nRunning QA checks...")

qa_protected_exceeds_total <- final_summary |>
  dplyr::filter(sovereign_state != "WIO") |>
  dplyr::filter(
    (measure_type == "area" &
       protected_indicator_area_km2 > indicator_area_km2 + 0.001) |
      (measure_type == "points" &
         protected_indicator_point_count > indicator_point_count)
  )

if (nrow(qa_protected_exceeds_total) > 0) {
  warning("Some protected indicator values exceed total indicator values.")
  print(qa_protected_exceeds_total)
}

qa_combined_vs_types <- final_summary |>
  dplyr::filter(sovereign_state != "WIO") |>
  dplyr::filter(
    (measure_type == "area" &
       protected_indicator_area_km2 >
       mpa_indicator_area_km2 + lmma_indicator_area_km2 + 0.001) |
      (measure_type == "points" &
         protected_indicator_point_count >
         mpa_indicator_point_count + lmma_indicator_point_count)
  )

if (nrow(qa_combined_vs_types) > 0) {
  warning(
    "Combined unique protection unexpectedly exceeds MPA + LMMA protection."
  )
  print(qa_combined_vs_types)
}

qa_percent <- final_summary |>
  dplyr::filter(
    !is.na(percent_indicator_protected_total),
    percent_indicator_protected_total < -0.001 |
      percent_indicator_protected_total > 100.001
  )

if (nrow(qa_percent) > 0) {
  warning("Some total protection percentages fall outside 0-100.")
  print(qa_percent)
}


# ============================================================
# 16. SAVE FINAL SUMMARY
# ============================================================

out_csv <- file.path(
  out_dir,
  "wio_element3_indicator_protection_by_sovereign.csv"
)

readr::write_csv(final_summary, out_csv)

message("\n============================================================")
message("ELEMENT 3 COMPLETE")
message("============================================================")
message("Final summary CSV: ", normalizePath(out_csv))
message("Spatial intersection folder: ", normalizePath(intersection_dir))

print(final_summary, n = Inf)


# ============================================================
# 17. LIST SPATIAL CACHE OUTPUTS
# ============================================================

message("\nSaved vector intersection GeoPackages:")
print(
  list.files(
    intersection_dir,
    pattern = "_intersections\\.gpkg$",
    full.names = TRUE
  )
)

message("\nDone.")