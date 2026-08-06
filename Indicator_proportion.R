# ============================================================
# WIO indicator / habitat protection summary by sovereign EEZ
# ============================================================
#
# Aim:
#   For each indicator layer, e.g. mangroves, seagrass, KBAs:
#
#   1. Calculate indicator area inside each sovereign EEZ.
#   2. Calculate percentage of each sovereign EEZ covered by that indicator.
#   3. Calculate percentage of WIO EEZ-contained indicator area belonging
#      to each sovereign state.
#   4. Calculate how much of each indicator inside each sovereign EEZ is protected
#      by MPA + LMMA combined.
#   5. Calculate MPA and LMMA protection separately.
#
# Supports:
#   - Vector indicators: shapefile, GPKG, GeoJSON
#   - Raster indicators: VRT, TIF, TIFF
#
# Main output:
#   outputs/wio_indicator_protection_by_sovereign.csv
#
# Optional visual output:
#   outputs/wio_indicator_layer_check_map.png
#
# Important interpretation:
#   indicator_area_km2
#     = area of the indicator inside that sovereign EEZ.
#
#   protected_indicator_area_km2
#     = area of the indicator inside that sovereign EEZ that overlaps either
#       MPA or LMMA.
#     = MPA + LMMA dissolved together, so MPA/LMMA overlap is counted once.
#
#   mpa_indicator_area_km2 and lmma_indicator_area_km2
#     = type-specific protection areas.
#     = these can sum to more than protected_indicator_area_km2 if MPA and
#       LMMA polygons overlap each other.
#
# Important raster assumption:
#   Raster indicators are treated as presence/absence layers.
#   By default, cells are treated as present where:
#     !is.na(value) & value != 0
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
  "tibble",
  "purrr",
  "stringr",
  "ggplot2",
  "readr",
  "rnaturalearth",
  "future",
  "future.apply",
  "parallel"
)

missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_pkgs) > 0) {
  install.packages(missing_pkgs)
}

invisible(lapply(pkgs, library, character.only = TRUE))

# Use planar geometry operations.
# Vector area and overlay are done after transforming to an equal-area CRS.
sf::sf_use_s2(FALSE)


# ------------------------------------------------------------
# 2. User settings
# ------------------------------------------------------------

# -------------------------
# EEZ input
# -------------------------

eez_inputs <- tibble::tribble(
  ~path,                                       ~layer,          ~label,
  "WIO_EEZ_1Jun2022/wio_eez_no_islands.shp",   NA_character_,   "EEZ"
)

# Column identifying sovereign state in your EEZ file.
EEZ_SOVEREIGN_COL <- "Sovereign"

# Your EEZ file appears to have missing CRS metadata.
# This assigns the CRS to the raw coordinates if missing.
# It does NOT reproject them.
SOURCE_EEZ_CRS_IF_MISSING <- "ESRI:102022"


# -------------------------
# Protected-area inputs
# -------------------------

pa_inputs <- tibble::tribble(
  ~path,                                               ~layer,          ~label,
  "wio_mpa/Wio_mpa.shp",                               NA_character_,   "MPA",
  "WIO_lmma_Aaarti_cleaned/lmma_merged_clean.gpkg",     NA_character_,   "LMMA"
)

# If MPA and LMMA are in separate files, leave this as NA.
# If they are in one combined file, set this to the column containing MPA/LMMA labels.
PA_TYPE_COL <- NA_character_


# -------------------------
# Indicator / habitat inputs
# -------------------------
#
# data_type can be:
#   "auto"   = infer from file extension
#   "vector" = shapefile, GPKG, GeoJSON
#   "raster" = VRT, TIF, TIFF
#
# For raster indicators:
#   - layer is ignored
#   - only the raster band specified by RASTER_LAYER_INDEX is used
#   - non-NA and non-zero cells are treated as presence by default

indicator_inputs <- tibble::tribble(
  ~path,                                                        ~layer,          ~indicator,    ~data_type,
  "indicators/WIO_Mangroves_WCMC/WIO_Mangrove.shp",              NA_character_,   "Mangroves",  "auto",
  "indicators/WIO_Geomorphic/Seamounts.shp",                  NA_character_,   "Seamounts",  "auto",
  "indicators/KBA_wio/KBA_wio.shp",                              NA_character_,   "KBAs",       "auto",
  "indicators/IBA_wio/IBA_wio.shp",                              NA_character_,   "IBAs",       "auto",
  "indicators/WIO_nearshore_habitats/wio_coral_allen_africaalbers.shp", NA_character_,   "Coral",      "auto",
  "indicators/GlobalSeagrass2023_2024/GlobalSeagrass2023_2024_global.vrt", NA_character_,   "Seagrass",   "raster",
  "indicators/WIO_Turtles/wio_turtles.shp",                      NA_character_,   "Turtles",    "auto"
)

# If an indicator layer is missing CRS metadata, this fallback can be used.
# Keep as NA unless you are certain of the source CRS.
SOURCE_INDICATOR_CRS_IF_MISSING <- NA_character_

# Raster presence rule:
#   "nonzero" = present where value is not NA and not zero
#   "not_na"  = present where value is not NA, even if value is zero
RASTER_PRESENCE_RULE <- "nonzero"

# If a raster/VRT has multiple bands, this band is used.
RASTER_LAYER_INDEX <- 1


# -------------------------
# Spatial settings
# -------------------------

# Western Indian Ocean plotting / raster-cropping box.
WIO_BBOX <- c(
  xmin = 20,
  xmax = 85,
  ymin = -40,
  ymax = 20
)

# If TRUE, vector EEZ, PA and vector indicator layers are clipped to this WIO box.
# Raster indicators are always cropped to this WIO box for efficiency.
CLIP_TO_WIO_BBOX <- FALSE

# Equal-area CRS for vector area calculations.
# For this Africa/WIO workflow, this is suitable.
AREA_CRS <- "ESRI:102022"


# -------------------------
# Output settings
# -------------------------

out_dir <- "outputs"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)


# ------------------------------------------------------------
# 3. Parallel settings
# ------------------------------------------------------------

physical_cores <- parallel::detectCores(logical = FALSE)
logical_cores  <- parallel::detectCores(logical = TRUE)

if (is.na(physical_cores)) physical_cores <- logical_cores
if (is.na(logical_cores)) logical_cores <- 1

message("Physical cores detected: ", physical_cores)
message("Logical cores detected:  ", logical_cores)

CORES_TO_LEAVE_FREE <- 3
N_WORKERS <- max(1, logical_cores - CORES_TO_LEAVE_FREE)

message("Parallel workers being used: ", N_WORKERS)

# Increase if objects are large.
options(future.globals.maxSize = 6 * 1024^3)

future::plan(future::multisession, workers = N_WORKERS)


# ------------------------------------------------------------
# 4. Helper functions
# ------------------------------------------------------------

read_sf_any <- function(path, layer = NA_character_) {
  
  layer_missing <- is.null(layer) ||
    length(layer) == 0 ||
    is.na(layer) ||
    !nzchar(layer)
  
  if (!file.exists(path) && !stringr::str_starts(path, "/vsi")) {
    stop("File not found: ", path)
  }
  
  if (layer_missing) {
    sf::st_read(path, quiet = FALSE)
  } else {
    sf::st_read(path, layer = layer, quiet = FALSE)
  }
}


infer_data_type <- function(path, data_type = "auto") {
  
  data_type <- stringr::str_to_lower(data_type)
  
  if (data_type %in% c("vector", "raster")) {
    return(data_type)
  }
  
  ext <- stringr::str_to_lower(tools::file_ext(path))
  
  vector_exts <- c("shp", "gpkg", "geojson", "json")
  raster_exts <- c("vrt", "tif", "tiff", "img", "grd", "nc")
  
  if (ext %in% vector_exts) return("vector")
  if (ext %in% raster_exts) return("raster")
  
  stop("Could not infer data_type from file extension for: ", path)
}


polygonalise_sfc <- function(g) {
  
  g <- sf::st_make_valid(g)
  g <- g[!sf::st_is_empty(g)]
  
  if (length(g) == 0) {
    return(g)
  }
  
  geom_types <- unique(as.character(sf::st_geometry_type(g, by_geometry = TRUE)))
  polygonal_types <- c("POLYGON", "MULTIPOLYGON")
  
  # Only extract polygons if needed.
  # This avoids warnings when the object is already polygonal.
  if (!all(geom_types %in% polygonal_types)) {
    g <- sf::st_collection_extract(g, "POLYGON", warn = FALSE)
    g <- g[!sf::st_is_empty(g)]
  }
  
  g
}


make_valid_polygonal <- function(x) {
  
  if (!inherits(x, "sf")) {
    stop("make_valid_polygonal() expects an sf object.")
  }
  
  x <- sf::st_make_valid(x)
  
  geom_types <- unique(as.character(sf::st_geometry_type(x, by_geometry = TRUE)))
  polygonal_types <- c("POLYGON", "MULTIPOLYGON")
  
  # Only extract if needed.
  if (!all(geom_types %in% polygonal_types)) {
    x <- sf::st_collection_extract(x, "POLYGON", warn = FALSE)
  }
  
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  
  x
}


read_many_sf <- function(input_tbl,
                         target_crs = 4326,
                         keep_cols = character(0),
                         source_crs_if_missing = NA_character_) {
  
  if (nrow(input_tbl) == 0) {
    stop("Input table has no rows.")
  }
  
  pieces <- purrr::pmap(
    input_tbl,
    function(path, layer, label) {
      
      x <- read_sf_any(path = path, layer = layer)
      
      if (is.na(sf::st_crs(x))) {
        if (is.na(source_crs_if_missing)) {
          stop("Layer has missing CRS and no fallback CRS was provided: ", path)
        }
        
        message("Assigning missing CRS ", source_crs_if_missing, " to: ", path)
        sf::st_crs(x) <- source_crs_if_missing
      }
      
      if (length(keep_cols) > 0) {
        x <- dplyr::select(x, dplyr::any_of(keep_cols))
      } else {
        x <- sf::st_sf(geometry = sf::st_geometry(x))
      }
      
      x <- make_valid_polygonal(x)
      x <- sf::st_transform(x, target_crs)
      
      x |>
        dplyr::mutate(
          .source_file = basename(path),
          .source_label = label
        )
    }
  )
  
  dplyr::bind_rows(pieces)
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
  
  x <- suppressWarnings(sf::st_intersection(x, bbox_poly))
  x <- make_valid_polygonal(x)
  
  x
}


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


safe_divide <- function(num, den) {
  ifelse(!is.na(den) & den > 0, num / den, NA_real_)
}


area_km2_sfc <- function(g) {
  
  if (is.null(g) || length(g) == 0 || all(sf::st_is_empty(g))) {
    return(0)
  }
  
  g <- polygonalise_sfc(g)
  
  if (length(g) == 0 || all(sf::st_is_empty(g))) {
    return(0)
  }
  
  sum(as.numeric(sf::st_area(g)) / 1e6, na.rm = TRUE)
}


dissolve_to_single_sfc <- function(x, crs_use) {
  
  if (nrow(x) == 0) {
    return(sf::st_sfc(sf::st_geometrycollection(), crs = crs_use))
  }
  
  g <- sf::st_geometry(x)
  g <- polygonalise_sfc(g)
  
  if (length(g) == 0 || all(sf::st_is_empty(g))) {
    return(sf::st_sfc(sf::st_geometrycollection(), crs = crs_use))
  }
  
  g_union <- sf::st_union(g)
  g_union <- polygonalise_sfc(g_union)
  
  if (length(g_union) == 0 || all(sf::st_is_empty(g_union))) {
    return(sf::st_sfc(sf::st_geometrycollection(), crs = crs_use))
  }
  
  sf::st_set_crs(g_union, crs_use)
}


safe_intersection_sfc <- function(g1, g2, label = NA_character_) {
  
  if (length(g1) == 0 || all(sf::st_is_empty(g1))) {
    return(sf::st_sfc(sf::st_geometrycollection(), crs = sf::st_crs(g1)))
  }
  
  if (length(g2) == 0 || all(sf::st_is_empty(g2))) {
    return(sf::st_sfc(sf::st_geometrycollection(), crs = sf::st_crs(g1)))
  }
  
  out <- tryCatch(
    {
      suppressWarnings(sf::st_intersection(g1, g2))
    },
    error = function(e) {
      message("Intersection failed for ", label, ": ", conditionMessage(e))
      return(NULL)
    }
  )
  
  if (is.null(out) || length(out) == 0 || all(sf::st_is_empty(out))) {
    return(sf::st_sfc(sf::st_geometrycollection(), crs = sf::st_crs(g1)))
  }
  
  out <- polygonalise_sfc(out)
  
  if (length(out) == 0 || all(sf::st_is_empty(out))) {
    return(sf::st_sfc(sf::st_geometrycollection(), crs = sf::st_crs(g1)))
  }
  
  sf::st_set_crs(out, sf::st_crs(g1))
}


read_vector_indicator <- function(path,
                                  layer,
                                  indicator,
                                  target_crs = 4326,
                                  source_crs_if_missing = NA_character_) {
  
  x <- read_sf_any(path = path, layer = layer)
  
  if (is.na(sf::st_crs(x))) {
    if (is.na(source_crs_if_missing)) {
      stop("Indicator layer has missing CRS and no fallback CRS was provided: ", path)
    }
    
    message("Assigning missing CRS ", source_crs_if_missing, " to: ", path)
    sf::st_crs(x) <- source_crs_if_missing
  }
  
  x <- sf::st_sf(geometry = sf::st_geometry(x))
  x <- make_valid_polygonal(x)
  x <- sf::st_transform(x, target_crs)
  
  x |>
    dplyr::mutate(
      indicator = indicator,
      .source_file = basename(path)
    )
}


prepare_raster_area_layer <- function(path,
                                      indicator,
                                      bbox_vec,
                                      presence_rule = "nonzero",
                                      layer_index = 1,
                                      source_crs_if_missing = NA_character_) {
  
  if (!file.exists(path)) {
    stop("Raster file not found: ", path)
  }
  
  r <- terra::rast(path)
  
  if (terra::nlyr(r) < layer_index) {
    stop(
      "Raster has fewer layers than RASTER_LAYER_INDEX. File: ",
      path,
      "; nlyr = ",
      terra::nlyr(r),
      "; requested layer = ",
      layer_index
    )
  }
  
  if (is.na(terra::crs(r)) || terra::crs(r) == "") {
    if (is.na(source_crs_if_missing)) {
      stop("Raster indicator has missing CRS and no fallback CRS was provided: ", path)
    }
    
    message("Assigning missing CRS ", source_crs_if_missing, " to raster: ", path)
    terra::crs(r) <- source_crs_if_missing
  }
  
  # Use selected band only.
  r <- r[[layer_index]]
  
  # Crop raster to WIO box for efficiency.
  wio_box <- bbox_sf_4326(bbox_vec)
  wio_box_raster_crs <- sf::st_transform(wio_box, terra::crs(r))
  wio_box_vect <- terra::vect(wio_box_raster_crs)
  
  r <- terra::crop(r, wio_box_vect)
  
  # Convert raster values to presence/absence.
  if (presence_rule == "nonzero") {
    presence <- terra::ifel(!is.na(r) & r != 0, 1, NA)
  } else if (presence_rule == "not_na") {
    presence <- terra::ifel(!is.na(r), 1, NA)
  } else {
    stop("Unknown RASTER_PRESENCE_RULE: ", presence_rule)
  }
  
  names(presence) <- "presence"
  
  # Calculate cell area in km2 using the raster's native CRS/grid.
  cell_area_km2 <- terra::cellSize(presence, unit = "km")
  
  # Area raster:
  # each present cell stores its cell area in km2;
  # absent cells are NA.
  area_raster <- cell_area_km2 * presence
  names(area_raster) <- "indicator_area_km2"
  
  list(
    indicator = indicator,
    path = path,
    area_raster = area_raster
  )
}


raster_area_in_sfc <- function(area_raster,
                               polygon_sfc,
                               label = NA_character_) {
  
  if (length(polygon_sfc) == 0 || all(sf::st_is_empty(polygon_sfc))) {
    return(0)
  }
  
  # Union polygon pieces so cells are not accidentally counted twice.
  polygon_sfc <- sf::st_union(polygon_sfc)
  polygon_sfc <- polygonalise_sfc(polygon_sfc)
  
  if (length(polygon_sfc) == 0 || all(sf::st_is_empty(polygon_sfc))) {
    return(0)
  }
  
  polygon_sf <- sf::st_sf(geometry = polygon_sfc)
  polygon_sf <- sf::st_transform(polygon_sf, terra::crs(area_raster))
  
  polygon_vect <- terra::vect(polygon_sf)
  
  ex <- tryCatch(
    {
      terra::extract(area_raster, polygon_vect, exact = TRUE)
    },
    error = function(e) {
      message("Raster extraction failed for ", label, ": ", conditionMessage(e))
      return(NULL)
    }
  )
  
  if (is.null(ex) || nrow(ex) == 0) {
    return(0)
  }
  
  value_col <- names(area_raster)[1]
  
  fraction_col <- intersect(
    c("fraction", "coverage_fraction", "weight", "weights"),
    names(ex)
  )
  
  if (length(fraction_col) > 0) {
    fraction_col <- fraction_col[1]
    return(sum(ex[[value_col]] * ex[[fraction_col]], na.rm = TRUE))
  }
  
  # Fallback if terra version does not return a fraction column.
  sum(ex[[value_col]], na.rm = TRUE)
}


# ------------------------------------------------------------
# 5. Read and prepare EEZ layer
# ------------------------------------------------------------

eez_raw <- read_many_sf(
  input_tbl = eez_inputs,
  target_crs = 4326,
  keep_cols = EEZ_SOVEREIGN_COL,
  source_crs_if_missing = SOURCE_EEZ_CRS_IF_MISSING
)

if (!(EEZ_SOVEREIGN_COL %in% names(eez_raw))) {
  stop(
    "EEZ_SOVEREIGN_COL not found: ",
    EEZ_SOVEREIGN_COL,
    "\nAvailable columns are: ",
    paste(names(eez_raw), collapse = ", ")
  )
}

eez_clean <- eez_raw |>
  dplyr::mutate(
    sovereign_state = stringr::str_squish(
      as.character(.data[[EEZ_SOVEREIGN_COL]])
    )
  ) |>
  dplyr::filter(
    !is.na(sovereign_state),
    sovereign_state != ""
  ) |>
  dplyr::select(sovereign_state)

if (CLIP_TO_WIO_BBOX) {
  eez_clean <- crop_to_bbox(eez_clean, WIO_BBOX)
}

if (nrow(eez_clean) == 0) {
  stop("No EEZ polygons remain after cleaning/clipping.")
}


# ------------------------------------------------------------
# 6. Read and prepare protected areas
# ------------------------------------------------------------

pa_keep_cols <- if (!is.na(PA_TYPE_COL)) PA_TYPE_COL else character(0)

pa_raw <- read_many_sf(
  input_tbl = pa_inputs,
  target_crs = 4326,
  keep_cols = pa_keep_cols,
  source_crs_if_missing = NA_character_
)

if (!is.na(PA_TYPE_COL) && !(PA_TYPE_COL %in% names(pa_raw))) {
  stop(
    "PA_TYPE_COL not found: ",
    PA_TYPE_COL,
    "\nAvailable columns are: ",
    paste(names(pa_raw), collapse = ", ")
  )
}

if (!is.na(PA_TYPE_COL)) {
  pa_clean <- pa_raw |>
    dplyr::mutate(pa_type_raw = as.character(.data[[PA_TYPE_COL]]))
} else {
  pa_clean <- pa_raw |>
    dplyr::mutate(pa_type_raw = .source_label)
}

pa_clean <- pa_clean |>
  dplyr::mutate(
    pa_type_raw = stringr::str_squish(stringr::str_to_upper(pa_type_raw)),
    pa_type = dplyr::case_when(
      stringr::str_detect(pa_type_raw, "LMMA|LOCALLY MANAGED") ~ "LMMA",
      stringr::str_detect(pa_type_raw, "MPA|MARINE PROTECTED") ~ "MPA",
      pa_type_raw %in% c("MPA", "LMMA") ~ pa_type_raw,
      TRUE ~ pa_type_raw
    )
  ) |>
  dplyr::filter(pa_type %in% c("MPA", "LMMA")) |>
  dplyr::select(pa_type)

if (CLIP_TO_WIO_BBOX) {
  pa_clean <- crop_to_bbox(pa_clean, WIO_BBOX)
}

pa_clean <- make_valid_polygonal(pa_clean)

message("Detected protected-area types: ", paste(sort(unique(pa_clean$pa_type)), collapse = ", "))

if (nrow(pa_clean) == 0) {
  stop("No MPA or LMMA features remain after cleaning/clipping.")
}


# ------------------------------------------------------------
# 7. Split indicator inputs into vector and raster rows
# ------------------------------------------------------------

indicator_inputs <- indicator_inputs |>
  dplyr::mutate(
    data_type = purrr::map2_chr(path, data_type, infer_data_type)
  )

vector_indicator_inputs <- indicator_inputs |>
  dplyr::filter(data_type == "vector")

raster_indicator_inputs <- indicator_inputs |>
  dplyr::filter(data_type == "raster")

message(
  "Vector indicators: ",
  paste(vector_indicator_inputs$indicator, collapse = ", ")
)

message(
  "Raster indicators: ",
  paste(raster_indicator_inputs$indicator, collapse = ", ")
)


# ------------------------------------------------------------
# 8. Visual check map
# ------------------------------------------------------------

world <- rnaturalearth::ne_countries(
  scale = "medium",
  returnclass = "sf"
)

# Read vector indicators for plotting only.
# Raster/VRT indicators are not plotted as polygons here.
# Their calculations are handled later using terra.
indicator_for_plot <- NULL

if (nrow(vector_indicator_inputs) > 0) {
  
  indicator_for_plot <- purrr::pmap_dfr(
    vector_indicator_inputs,
    function(path, layer, indicator, data_type) {
      read_vector_indicator(
        path = path,
        layer = layer,
        indicator = indicator,
        target_crs = 4326,
        source_crs_if_missing = SOURCE_INDICATOR_CRS_IF_MISSING
      )
    }
  ) |>
    dplyr::group_by(indicator) |>
    dplyr::summarise(.groups = "drop") |>
    make_valid_polygonal()
  
  if (CLIP_TO_WIO_BBOX) {
    indicator_for_plot <- crop_to_bbox(indicator_for_plot, WIO_BBOX)
  }
}

wio_map <- ggplot() +
  geom_sf(
    data = world,
    fill = "grey90",
    colour = "white",
    linewidth = 0.2
  ) +
  geom_sf(
    data = eez_clean,
    fill = "lightblue",
    colour = "grey40",
    alpha = 0.25,
    linewidth = 0.25
  ) +
  geom_sf(
    data = pa_clean,
    aes(fill = pa_type),
    colour = "black",
    alpha = 0.45,
    linewidth = 0.15
  ) +
  coord_sf(
    xlim = c(WIO_BBOX[["xmin"]], WIO_BBOX[["xmax"]]),
    ylim = c(WIO_BBOX[["ymin"]], WIO_BBOX[["ymax"]]),
    expand = FALSE
  ) +
  labs(
    title = "WIO EEZ, protected areas and vector indicator layers",
    subtitle = "Raster/VRT indicators are calculated with terra but not drawn here",
    x = "Longitude",
    y = "Latitude",
    fill = "Protected area"
  ) +
  theme_minimal()

if (!is.null(indicator_for_plot) && nrow(indicator_for_plot) > 0) {
  wio_map <- wio_map +
    geom_sf(
      data = indicator_for_plot,
      aes(colour = indicator),
      fill = NA,
      linewidth = 0.35
    ) +
    labs(colour = "Vector indicator")
}

print(wio_map)

ggsave(
  filename = file.path(out_dir, "wio_indicator_layer_check_map.png"),
  plot = wio_map,
  width = 10,
  height = 7,
  dpi = 300
)


# ------------------------------------------------------------
# 9. Transform EEZ and protected areas to equal-area CRS
# ------------------------------------------------------------

eez_area_crs <- eez_clean |>
  sf::st_transform(AREA_CRS) |>
  make_valid_polygonal()

pa_area_crs <- pa_clean |>
  sf::st_transform(AREA_CRS) |>
  make_valid_polygonal()


# ------------------------------------------------------------
# 10. Dissolve EEZs to sovereign state
# ------------------------------------------------------------

eez_dissolved <- eez_area_crs |>
  dplyr::group_by(sovereign_state) |>
  dplyr::summarise(.groups = "drop") |>
  make_valid_polygonal()

eez_dissolved$eez_area_km2 <- as.numeric(sf::st_area(eez_dissolved)) / 1e6

# Force clean sf geometry metadata.
eez_dissolved <- sf::st_as_sf(eez_dissolved)
sf::st_geometry(eez_dissolved) <- "geometry"

# Union of all sovereign EEZs.
eez_all_unique_geom <- dissolve_to_single_sfc(
  x = eez_dissolved,
  crs_use = sf::st_crs(eez_dissolved)
)


# ------------------------------------------------------------
# 11. Dissolve protected areas
# ------------------------------------------------------------

# Total protected area:
# MPA + LMMA dissolved together so overlap is counted once.
pa_all_unique_geom <- dissolve_to_single_sfc(
  x = pa_area_crs,
  crs_use = sf::st_crs(pa_area_crs)
)

# MPA only, dissolved.
pa_mpa_geom <- dissolve_to_single_sfc(
  x = pa_area_crs |> dplyr::filter(pa_type == "MPA"),
  crs_use = sf::st_crs(pa_area_crs)
)

# LMMA only, dissolved.
pa_lmma_geom <- dissolve_to_single_sfc(
  x = pa_area_crs |> dplyr::filter(pa_type == "LMMA"),
  crs_use = sf::st_crs(pa_area_crs)
)


# ------------------------------------------------------------
# 12. Prepare plain EEZ geometry inputs for parallel workers
# ------------------------------------------------------------

eez_states <- eez_dissolved$sovereign_state
eez_areas  <- eez_dissolved$eez_area_km2

eez_geom_list <- lapply(
  seq_len(nrow(eez_dissolved)),
  function(i) {
    sf::st_sfc(
      sf::st_geometry(eez_dissolved)[[i]],
      crs = sf::st_crs(eez_dissolved)
    )
  }
)


# ------------------------------------------------------------
# 13. Per-indicator calculation function
# ------------------------------------------------------------

process_one_indicator <- function(path,
                                  layer,
                                  indicator,
                                  data_type) {
  
  message("Processing indicator: ", indicator, " [", data_type, "]")
  
  if (data_type == "vector") {
    
    indicator_sf <- read_vector_indicator(
      path = path,
      layer = layer,
      indicator = indicator,
      target_crs = 4326,
      source_crs_if_missing = SOURCE_INDICATOR_CRS_IF_MISSING
    )
    
    if (CLIP_TO_WIO_BBOX) {
      indicator_sf <- crop_to_bbox(indicator_sf, WIO_BBOX)
    }
    
    indicator_area_crs <- indicator_sf |>
      sf::st_transform(AREA_CRS) |>
      make_valid_polygonal()
    
    indicator_geom <- dissolve_to_single_sfc(
      x = indicator_area_crs,
      crs_use = sf::st_crs(indicator_area_crs)
    )
    
    # Denominator:
    # total indicator area inside the union of all WIO EEZs.
    indicator_in_all_eezs <- safe_intersection_sfc(
      g1 = indicator_geom,
      g2 = eez_all_unique_geom,
      label = paste0(indicator, " x all EEZs")
    )
    
    indicator_total_in_all_eezs_km2 <- area_km2_sfc(indicator_in_all_eezs)
    
    country_rows <- purrr::map_dfr(
      seq_along(eez_geom_list),
      function(i) {
        
        state_i    <- eez_states[[i]]
        eez_area_i <- eez_areas[[i]]
        eez_geom_i <- eez_geom_list[[i]]
        
        label_i <- paste0(indicator, " x ", state_i)
        
        # Indicator inside this sovereign EEZ.
        indicator_in_eez <- safe_intersection_sfc(
          g1 = indicator_geom,
          g2 = eez_geom_i,
          label = label_i
        )
        
        indicator_area_km2 <- area_km2_sfc(indicator_in_eez)
        
        # Indicator inside this sovereign EEZ and protected by MPA or LMMA.
        protected_indicator_geom <- safe_intersection_sfc(
          g1 = indicator_in_eez,
          g2 = pa_all_unique_geom,
          label = paste0(label_i, " x PA")
        )
        
        protected_indicator_area_km2 <- area_km2_sfc(protected_indicator_geom)
        
        # Indicator inside this sovereign EEZ and protected by MPA.
        mpa_indicator_geom <- safe_intersection_sfc(
          g1 = indicator_in_eez,
          g2 = pa_mpa_geom,
          label = paste0(label_i, " x MPA")
        )
        
        mpa_indicator_area_km2 <- area_km2_sfc(mpa_indicator_geom)
        
        # Indicator inside this sovereign EEZ and protected by LMMA.
        lmma_indicator_geom <- safe_intersection_sfc(
          g1 = indicator_in_eez,
          g2 = pa_lmma_geom,
          label = paste0(label_i, " x LMMA")
        )
        
        lmma_indicator_area_km2 <- area_km2_sfc(lmma_indicator_geom)
        
        tibble::tibble(
          sovereign_state = state_i,
          indicator = indicator,
          data_type = data_type,
          eez_area_km2 = eez_area_i,
          indicator_area_km2 = indicator_area_km2,
          indicator_total_in_all_eezs_km2 = indicator_total_in_all_eezs_km2,
          protected_indicator_area_km2 = protected_indicator_area_km2,
          mpa_indicator_area_km2 = mpa_indicator_area_km2,
          lmma_indicator_area_km2 = lmma_indicator_area_km2
        )
      }
    )
    
    return(country_rows)
  }
  
  
  if (data_type == "raster") {
    
    raster_obj <- prepare_raster_area_layer(
      path = path,
      indicator = indicator,
      bbox_vec = WIO_BBOX,
      presence_rule = RASTER_PRESENCE_RULE,
      layer_index = RASTER_LAYER_INDEX,
      source_crs_if_missing = SOURCE_INDICATOR_CRS_IF_MISSING
    )
    
    area_raster <- raster_obj$area_raster
    
    # Denominator:
    # raster indicator area inside the union of all WIO EEZs.
    indicator_total_in_all_eezs_km2 <- raster_area_in_sfc(
      area_raster = area_raster,
      polygon_sfc = eez_all_unique_geom,
      label = paste0(indicator, " raster x all EEZs")
    )
    
    country_rows <- purrr::map_dfr(
      seq_along(eez_geom_list),
      function(i) {
        
        state_i    <- eez_states[[i]]
        eez_area_i <- eez_areas[[i]]
        eez_geom_i <- eez_geom_list[[i]]
        
        label_i <- paste0(indicator, " raster x ", state_i)
        
        # Indicator raster area inside this sovereign EEZ.
        indicator_area_km2 <- raster_area_in_sfc(
          area_raster = area_raster,
          polygon_sfc = eez_geom_i,
          label = label_i
        )
        
        # EEZ area protected by total PA.
        eez_pa_geom <- safe_intersection_sfc(
          g1 = eez_geom_i,
          g2 = pa_all_unique_geom,
          label = paste0(state_i, " x total PA")
        )
        
        protected_indicator_area_km2 <- raster_area_in_sfc(
          area_raster = area_raster,
          polygon_sfc = eez_pa_geom,
          label = paste0(label_i, " x PA")
        )
        
        # EEZ area protected by MPA.
        eez_mpa_geom <- safe_intersection_sfc(
          g1 = eez_geom_i,
          g2 = pa_mpa_geom,
          label = paste0(state_i, " x MPA")
        )
        
        mpa_indicator_area_km2 <- raster_area_in_sfc(
          area_raster = area_raster,
          polygon_sfc = eez_mpa_geom,
          label = paste0(label_i, " x MPA")
        )
        
        # EEZ area protected by LMMA.
        eez_lmma_geom <- safe_intersection_sfc(
          g1 = eez_geom_i,
          g2 = pa_lmma_geom,
          label = paste0(state_i, " x LMMA")
        )
        
        lmma_indicator_area_km2 <- raster_area_in_sfc(
          area_raster = area_raster,
          polygon_sfc = eez_lmma_geom,
          label = paste0(label_i, " x LMMA")
        )
        
        tibble::tibble(
          sovereign_state = state_i,
          indicator = indicator,
          data_type = data_type,
          eez_area_km2 = eez_area_i,
          indicator_area_km2 = indicator_area_km2,
          indicator_total_in_all_eezs_km2 = indicator_total_in_all_eezs_km2,
          protected_indicator_area_km2 = protected_indicator_area_km2,
          mpa_indicator_area_km2 = mpa_indicator_area_km2,
          lmma_indicator_area_km2 = lmma_indicator_area_km2
        )
      }
    )
    
    return(country_rows)
  }
  
  stop("Unsupported data_type: ", data_type)
}


# ------------------------------------------------------------
# 14. Indicator x sovereign EEZ calculations
# ------------------------------------------------------------

message("Calculating indicator overlap and protection summaries in parallel...")

indicator_results <- future.apply::future_lapply(
  X = seq_len(nrow(indicator_inputs)),
  FUN = function(j) {
    
    process_one_indicator(
      path = indicator_inputs$path[[j]],
      layer = indicator_inputs$layer[[j]],
      indicator = indicator_inputs$indicator[[j]],
      data_type = indicator_inputs$data_type[[j]]
    )
  },
  future.seed = TRUE
)


# ------------------------------------------------------------
# 15. Build final country-level summary
# ------------------------------------------------------------

final_summary <- dplyr::bind_rows(indicator_results) |>
  dplyr::mutate(
    # How much of each country's EEZ is covered by this indicator?
    percent_eez_covered_by_indicator =
      100 * safe_divide(indicator_area_km2, eez_area_km2),
    
    # How much of the WIO EEZ-contained indicator area is in this country?
    percent_of_indicator_in_all_eezs =
      100 * safe_divide(indicator_area_km2, indicator_total_in_all_eezs_km2),
    
    # How much of this country's indicator area is protected by MPA or LMMA?
    percent_indicator_protected_total =
      100 * safe_divide(protected_indicator_area_km2, indicator_area_km2),
    
    # How much of this country's indicator area is protected by MPA?
    percent_indicator_protected_mpa =
      100 * safe_divide(mpa_indicator_area_km2, indicator_area_km2),
    
    # How much of this country's indicator area is protected by LMMA?
    percent_indicator_protected_lmma =
      100 * safe_divide(lmma_indicator_area_km2, indicator_area_km2)
  ) |>
  dplyr::select(
    sovereign_state,
    indicator,
    data_type,
    eez_area_km2,
    indicator_area_km2,
    indicator_total_in_all_eezs_km2,
    protected_indicator_area_km2,
    mpa_indicator_area_km2,
    lmma_indicator_area_km2,
    percent_eez_covered_by_indicator,
    percent_of_indicator_in_all_eezs,
    percent_indicator_protected_total,
    percent_indicator_protected_mpa,
    percent_indicator_protected_lmma
  ) |>
  dplyr::arrange(indicator, sovereign_state)


# ------------------------------------------------------------
# 16. Add WIO regional row for each indicator
# ------------------------------------------------------------

wio_rows <- final_summary |>
  dplyr::group_by(indicator, data_type) |>
  dplyr::summarise(
    sovereign_state = "WIO",
    eez_area_km2 = sum(eez_area_km2, na.rm = TRUE),
    indicator_area_km2 = sum(indicator_area_km2, na.rm = TRUE),
    indicator_total_in_all_eezs_km2 = dplyr::first(indicator_total_in_all_eezs_km2),
    protected_indicator_area_km2 = sum(protected_indicator_area_km2, na.rm = TRUE),
    mpa_indicator_area_km2 = sum(mpa_indicator_area_km2, na.rm = TRUE),
    lmma_indicator_area_km2 = sum(lmma_indicator_area_km2, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    percent_eez_covered_by_indicator =
      100 * safe_divide(indicator_area_km2, eez_area_km2),
    
    percent_of_indicator_in_all_eezs =
      100 * safe_divide(indicator_area_km2, indicator_total_in_all_eezs_km2),
    
    percent_indicator_protected_total =
      100 * safe_divide(protected_indicator_area_km2, indicator_area_km2),
    
    percent_indicator_protected_mpa =
      100 * safe_divide(mpa_indicator_area_km2, indicator_area_km2),
    
    percent_indicator_protected_lmma =
      100 * safe_divide(lmma_indicator_area_km2, indicator_area_km2)
  ) |>
  dplyr::select(names(final_summary))

final_summary <- dplyr::bind_rows(
  final_summary,
  wio_rows
) |>
  dplyr::arrange(indicator, sovereign_state)


# ------------------------------------------------------------
# 17. Save final CSV
# ------------------------------------------------------------

out_csv <- file.path(out_dir, "wio_indicator_protection_by_sovereign.csv")

readr::write_csv(final_summary, out_csv)

message("Final CSV saved to: ", normalizePath(out_csv))

print(final_summary)


# ------------------------------------------------------------
# 18. Shut down parallel workers
# ------------------------------------------------------------

future::plan(future::sequential)

message("Done.")