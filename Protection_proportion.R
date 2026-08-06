# ============================================================
# WIO EEZ x MPA/LMMA protected-area summary
# ============================================================
#
# Purpose:
#   1. Load EEZ, MPA and LMMA shapefiles/GPKGs
#   2. Fix/standardise geometries
#   3. Ensure all layers use compatible CRS
#   4. Plot a WIO layer-check map against a world map
#   5. Dissolve EEZs to Sovereign State
#   6. Dissolve MPA and LMMA layers to avoid within-type double-counting
#   7. Dissolve MPA + LMMA together for total protected area
#   8. Calculate protected-area overlap within each sovereign EEZ in parallel
#   9. Save one final CSV
#
# Outputs:
#   outputs/wio_layer_check_map.png
#   outputs/wio_eez_protected_area_summary.csv
#
# Final CSV columns:
#   sovereign_state
#   eez_area_km2
#   protected_area_km2
#   mpa_area_km2
#   lmma_area_km2
#   percent_protected_total
#   percent_protected_mpa
#   percent_protected_lmma
#
# Important:
#   protected_area_km2 = unique MPA + LMMA area, with MPA/LMMA overlap counted once.
#   mpa_area_km2 = MPA area inside EEZ, with overlaps among MPA polygons dissolved.
#   lmma_area_km2 = LMMA area inside EEZ, with overlaps among LMMA polygons dissolved.
#
# Therefore:
#   mpa_area_km2 + lmma_area_km2 can be greater than protected_area_km2
#   if MPA and LMMA polygons overlap each other.
#
# ============================================================


rm(list = ls())


# ------------------------------------------------------------
# 1. Packages
# ------------------------------------------------------------

pkgs <- c(
  "sf",
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
# Area and overlay are done after transforming to an equal-area CRS.
sf::sf_use_s2(FALSE)


# ------------------------------------------------------------
# 2. User settings
# ------------------------------------------------------------

eez_inputs <- tibble::tribble(
  ~path,                                       ~layer,          ~label,
  "WIO_EEZ_1Jun2022/wio_eez_no_islands.shp",   NA_character_,   "EEZ"
)

pa_inputs <- tibble::tribble(
  ~path,                                               ~layer,          ~label,
  "wio_mpa/Wio_mpa.shp",                               NA_character_,   "MPA",
  "WIO_lmma_Aaarti_cleaned/lmma_merged_clean.gpkg",     NA_character_,   "LMMA"
)

# If MPA and LMMA are in separate files, leave this as NA.
# If they are in one combined file, set this to the column containing MPA/LMMA labels.
PA_TYPE_COL <- NA_character_

# EEZ column identifying sovereign state.
EEZ_SOVEREIGN_COL <- "Sovereign"

# WIO plotting extent.
WIO_BBOX <- c(
  xmin = 20,
  xmax = 85,
  ymin = -40,
  ymax = 20
)

# Your EEZ file appears to have missing CRS metadata.
# This assigns the CRS to the raw coordinates if missing.
# It does NOT reproject them.
SOURCE_EEZ_CRS_IF_MISSING <- "ESRI:102022"

# Equal-area CRS for area calculations.
# For this Africa/WIO workflow, this is fine.
AREA_CRS <- "ESRI:102022"

# Output folder.
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

# Leave a couple of cores free.
CORES_TO_LEAVE_FREE <- 3

N_WORKERS <- max(1, logical_cores - CORES_TO_LEAVE_FREE)

message("Parallel workers being used: ", N_WORKERS)

# Increase this if your dissolved PA geometries are very large.
# This avoids future failing because spatial objects are too big to export.
options(future.globals.maxSize = 4 * 1024^3)

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


polygonalise_sfc <- function(g) {
  # Repair geometry first.
  g <- sf::st_make_valid(g)
  
  # Remove empties early.
  g <- g[!sf::st_is_empty(g)]
  
  if (length(g) == 0) {
    return(g)
  }
  
  geom_types <- unique(as.character(sf::st_geometry_type(g, by_geometry = TRUE)))
  
  polygonal_types <- c("POLYGON", "MULTIPOLYGON")
  
  # Only extract polygons when genuinely needed.
  # This avoids the warning:
  #   "x is already of type POLYGON"
  if (!all(geom_types %in% polygonal_types)) {
    g <- sf::st_collection_extract(g, "POLYGON", warn = FALSE)
    g <- g[!sf::st_is_empty(g)]
  }
  
  g
}


make_valid_polygonal <- function(x) {
  # Works for sf objects.
  # Keeps attributes and replaces geometry with cleaned polygonal geometry.
  
  if (!inherits(x, "sf")) {
    stop("make_valid_polygonal() expects an sf object.")
  }
  
  g <- sf::st_geometry(x)
  g <- polygonalise_sfc(g)
  
  x <- x[!sf::st_is_empty(sf::st_geometry(x)), , drop = FALSE]
  
  # Re-run after subsetting to be safe.
  g <- sf::st_geometry(x)
  g <- polygonalise_sfc(g)
  
  sf::st_geometry(x) <- g
  
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


safe_divide <- function(num, den) {
  ifelse(!is.na(den) & den > 0, num / den, NA_real_)
}


dissolve_to_single_sfc <- function(x, crs_use) {
  # Dissolves all features in x to one sfc geometry.
  # Returns an sfc, not an sf object.
  # This avoids sf column metadata problems inside parallel workers.
  
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


intersection_area_km2 <- function(eez_geom, pa_geom, sovereign_state = NA_character_) {
  # eez_geom and pa_geom must both be sfc geometries.
  # This avoids the previous error:
  #   attr(obj, "sf_column") does not point to a geometry column
  
  if (length(eez_geom) == 0 || all(sf::st_is_empty(eez_geom))) {
    return(0)
  }
  
  if (length(pa_geom) == 0 || all(sf::st_is_empty(pa_geom))) {
    return(0)
  }
  
  inter <- tryCatch(
    {
      suppressWarnings(
        sf::st_intersection(eez_geom, pa_geom)
      )
    },
    error = function(e) {
      message(
        "Intersection failed for ",
        sovereign_state,
        ": ",
        conditionMessage(e)
      )
      return(NULL)
    }
  )
  
  if (is.null(inter) || length(inter) == 0 || all(sf::st_is_empty(inter))) {
    return(0)
  }
  
  inter <- polygonalise_sfc(inter)
  
  if (length(inter) == 0 || all(sf::st_is_empty(inter))) {
    return(0)
  }
  
  sum(as.numeric(sf::st_area(inter)) / 1e6, na.rm = TRUE)
}


# ------------------------------------------------------------
# 5. Read EEZ and protected-area layers
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

message("EEZ CRS after reading/transformation:")
print(sf::st_crs(eez_raw))

message("EEZ bounding box after transformation to lon/lat:")
print(sf::st_bbox(eez_raw))

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

pa_clean <- make_valid_polygonal(pa_clean)

message("Detected protected-area types: ", paste(sort(unique(pa_clean$pa_type)), collapse = ", "))

if (nrow(pa_clean) == 0) {
  stop("No MPA or LMMA features found.")
}


# ------------------------------------------------------------
# 6. Visual check plot
# ------------------------------------------------------------

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
    data = eez_clean,
    fill = "lightblue",
    colour = "grey40",
    alpha = 0.35,
    linewidth = 0.25
  ) +
  geom_sf(
    data = pa_clean,
    aes(fill = pa_type),
    colour = "black",
    alpha = 0.6,
    linewidth = 0.15
  ) +
  coord_sf(
    xlim = c(WIO_BBOX[["xmin"]], WIO_BBOX[["xmax"]]),
    ylim = c(WIO_BBOX[["ymin"]], WIO_BBOX[["ymax"]]),
    expand = FALSE
  ) +
  labs(
    title = "WIO EEZ and MPA/LMMA layer check",
    subtitle = "Check that layers align before area calculations",
    x = "Longitude",
    y = "Latitude",
    fill = "Protected area type"
  ) +
  theme_minimal()

print(wio_map)

ggsave(
  filename = file.path(out_dir, "wio_layer_check_map.png"),
  plot = wio_map,
  width = 10,
  height = 7,
  dpi = 300
)


# ------------------------------------------------------------
# 7. Transform to equal-area CRS for area calculations
# ------------------------------------------------------------

eez_area_crs <- eez_clean |>
  sf::st_transform(AREA_CRS) |>
  make_valid_polygonal()

pa_area_crs <- pa_clean |>
  sf::st_transform(AREA_CRS) |>
  make_valid_polygonal()


# ------------------------------------------------------------
# 8. Dissolve EEZs to sovereign state
# ------------------------------------------------------------

eez_dissolved <- eez_area_crs |>
  dplyr::group_by(sovereign_state) |>
  dplyr::summarise(.groups = "drop") |>
  make_valid_polygonal()

eez_dissolved$eez_area_km2 <- as.numeric(sf::st_area(eez_dissolved)) / 1e6

# Force a clean geometry column.
# This prevents the sf_column metadata issue in downstream code.
eez_dissolved <- sf::st_as_sf(eez_dissolved)
sf::st_geometry(eez_dissolved) <- "geometry"


# ------------------------------------------------------------
# 9. Dissolve protected areas
# ------------------------------------------------------------

# Unique total protected area:
# MPA + LMMA dissolved together, so MPA/LMMA overlaps are counted only once.
pa_all_unique_geom <- dissolve_to_single_sfc(
  x = pa_area_crs,
  crs_use = sf::st_crs(pa_area_crs)
)

# MPA dissolved to one geometry.
# Avoids double-counting overlaps among MPA polygons.
pa_mpa_geom <- dissolve_to_single_sfc(
  x = pa_area_crs |> dplyr::filter(pa_type == "MPA"),
  crs_use = sf::st_crs(pa_area_crs)
)

# LMMA dissolved to one geometry.
# Avoids double-counting overlaps among LMMA polygons.
pa_lmma_geom <- dissolve_to_single_sfc(
  x = pa_area_crs |> dplyr::filter(pa_type == "LMMA"),
  crs_use = sf::st_crs(pa_area_crs)
)


# ------------------------------------------------------------
# 10. Prepare plain geometry inputs for parallel workers
# ------------------------------------------------------------

# Do not pass sliced sf rows into future_lapply().
# That is what caused the previous:
#   attr(obj, "sf_column") does not point to a geometry column
#
# Instead, pass:
#   - sovereign_state vector
#   - EEZ area vector
#   - one sfc geometry per EEZ

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
# 11. Parallel EEZ-by-EEZ area calculations
# ------------------------------------------------------------

message("Calculating protected-area overlaps by sovereign state in parallel...")

results_list <- future.apply::future_lapply(
  X = seq_along(eez_geom_list),
  FUN = function(i) {
    
    eez_geom_i <- eez_geom_list[[i]]
    state_i    <- eez_states[[i]]
    eez_area_i <- eez_areas[[i]]
    
    total_pa_km2 <- intersection_area_km2(
      eez_geom = eez_geom_i,
      pa_geom = pa_all_unique_geom,
      sovereign_state = state_i
    )
    
    mpa_km2 <- intersection_area_km2(
      eez_geom = eez_geom_i,
      pa_geom = pa_mpa_geom,
      sovereign_state = state_i
    )
    
    lmma_km2 <- intersection_area_km2(
      eez_geom = eez_geom_i,
      pa_geom = pa_lmma_geom,
      sovereign_state = state_i
    )
    
    tibble::tibble(
      sovereign_state = state_i,
      eez_area_km2 = eez_area_i,
      protected_area_km2 = total_pa_km2,
      mpa_area_km2 = mpa_km2,
      lmma_area_km2 = lmma_km2
    )
  },
  future.seed = TRUE
)


# ------------------------------------------------------------
# 12. Final summary table
# ------------------------------------------------------------

final_summary <- dplyr::bind_rows(results_list) |>
  dplyr::mutate(
    percent_protected_total = 100 * safe_divide(protected_area_km2, eez_area_km2),
    percent_protected_mpa   = 100 * safe_divide(mpa_area_km2, eez_area_km2),
    percent_protected_lmma  = 100 * safe_divide(lmma_area_km2, eez_area_km2)
  ) |>
  dplyr::select(
    sovereign_state,
    eez_area_km2,
    protected_area_km2,
    mpa_area_km2,
    lmma_area_km2,
    percent_protected_total,
    percent_protected_mpa,
    percent_protected_lmma
  ) |>
  dplyr::arrange(sovereign_state)


# ------------------------------------------------------------
# 12b. Add regional WIO summary row
# ------------------------------------------------------------

# The WIO row sums the area columns across all sovereign states.
# The percentage columns are then recalculated from those summed areas.
#
# Important:
#   Do not sum percentage columns directly.
#   Percentages must be recalculated as:
#     summed protected area / summed EEZ area * 100

wio_row <- final_summary |>
  dplyr::summarise(
    sovereign_state = "WIO",
    eez_area_km2 = sum(eez_area_km2, na.rm = TRUE),
    protected_area_km2 = sum(protected_area_km2, na.rm = TRUE),
    mpa_area_km2 = sum(mpa_area_km2, na.rm = TRUE),
    lmma_area_km2 = sum(lmma_area_km2, na.rm = TRUE)
  ) |>
  dplyr::mutate(
    percent_protected_total = 100 * safe_divide(protected_area_km2, eez_area_km2),
    percent_protected_mpa   = 100 * safe_divide(mpa_area_km2, eez_area_km2),
    percent_protected_lmma  = 100 * safe_divide(lmma_area_km2, eez_area_km2)
  )

final_summary <- dplyr::bind_rows(
  final_summary,
  wio_row
)

# ------------------------------------------------------------
# 13. Save final CSV
# ------------------------------------------------------------

out_csv <- file.path(out_dir, "wio_eez_protected_area_summary.csv")

readr::write_csv(final_summary, out_csv)

message("Final CSV saved to: ", normalizePath(out_csv))

print(final_summary)


# ------------------------------------------------------------
# 14. Shut down parallel workers
# ------------------------------------------------------------

future::plan(future::sequential)

message("Done.")
