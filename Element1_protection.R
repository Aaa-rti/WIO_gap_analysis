# ============================================================
# ELEMENT 1
# WIO EEZ x MPA / OECM protected-area database
# FULL-ATTRIBUTE + FILTERED + REUSABLE INTERSECTION 
# ============================================================
#
# FILTERING RULES
# ---------------
# MPA:
#   Keep only records where STATUS == "Working"
#
# OECM:
#   1. Remove decision == "drop_candidate".
#   2. If status_new contains an informative current status, it is treated
#      as the CURRENT status: keep only status_new == "Active".
#   3. If status_new is missing/blank OR "Unknown", fall back to status_old:
#        keep only status_old == "Working".
#
# IMPORTANT
# ---------
#
# All intersections, dissolved footprints, and area calculations use ONLY
# the filtered MPA/OECM features.
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
  "readr",
  "ggplot2",
  "rnaturalearth"
)

missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_pkgs) > 0) {
  install.packages(missing_pkgs)
}

invisible(lapply(pkgs, library, character.only = TRUE))

sf::sf_use_s2(FALSE)

# ------------------------------------------------------------
# 2. User settings
# ------------------------------------------------------------

EEZ_PATH <- "WIO_EEZ_1Jun2022/wio_eez_no_islands.shp"
EEZ_LAYER <- NA_character_
EEZ_SOVEREIGN_COL <- "Sovereign"
SOURCE_EEZ_CRS_IF_MISSING <- "ESRI:102022"

MPA_PATH <- "wio_mpa/Wio_mpa.shp"
MPA_LAYER <- NA_character_
MPA_STATUS_COL <- "STATUS"


OECM_PATH <- "WIO_lmma_Aaarti_cleaned/lmma_merged_clean.gpkg"
OECM_LAYER <- NA_character_
OECM_DECISION_COL <- "decision"
OECM_STATUS_OLD_COL <- "status_old"
OECM_STATUS_NEW_COL <- "status_new"


OECM_NEW_STATUS_UNKNOWN_VALUES <- c("Unknown")

OECM_NEW_STATUS_OVERRIDES_OLD <- TRUE

AREA_CRS <- "ESRI:102022"
PLOT_CRS <- 4326

WIO_BBOX <- c(
  xmin = 20,
  xmax = 85,
  ymin = -40,
  ymax = 20
)

out_dir <- "outputs"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

out_gpkg <- file.path(out_dir, "wio_protected_area_spatial_database.gpkg")
out_csv <- file.path(out_dir, "wio_eez_protected_area_summary.csv")
out_map <- file.path(out_dir, "wio_layer_check_map.png")
out_filter_audit <- file.path(out_dir, "wio_pa_filter_audit.csv")


OVERWRITE_MASTER_GPKG <- FALSE

# ------------------------------------------------------------
# 3. Helper functions
# ------------------------------------------------------------

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
  
  if (any(geom_types == "GEOMETRYCOLLECTION")) {
    x <- suppressWarnings(
      sf::st_collection_extract(x, "POLYGON", warn = FALSE)
    )
  }
  
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  
  if (nrow(x) == 0) {
    return(x)
  }
  
  geom_types <- as.character(sf::st_geometry_type(x, by_geometry = TRUE))
  keep <- geom_types %in% c("POLYGON", "MULTIPOLYGON")
  x <- x[keep, , drop = FALSE]
  
  standardise_geometry_column(x)
}

safe_divide <- function(num, den) {
  ifelse(!is.na(den) & den > 0, num / den, NA_real_)
}


normalise_text <- function(x) {
  y <- as.character(x)
  y <- stringr::str_squish(y)
  y <- stringr::str_to_lower(y)
  
  y[y %in% c("", "na", "n/a", "null", "none")] <- NA_character_
  y
}


normalise_token <- function(x) {
  y <- normalise_text(x)
  y <- stringr::str_replace_all(y, "[[:space:]-]+", "_")
  y
}

prepare_pa_source <- function(path, layer, pa_type, target_crs = AREA_CRS) {
  x <- read_sf_any(path, layer)
  
  if (is.na(sf::st_crs(x))) {
    stop(pa_type, " layer has no CRS: ", path)
  }
  
  pa_type_value <- pa_type
  source_file_value <- basename(path)
  
  x <- x |>
    dplyr::mutate(
      analysis_source_feature_id = dplyr::row_number(),
      analysis_pa_type = .env$pa_type_value,
      analysis_pa_id = paste0(
        .env$pa_type_value,
        "_",
        sprintf("%06d", analysis_source_feature_id)
      ),
      analysis_source_file = .env$source_file_value
    ) |>
    standardise_geometry_column() |>
    make_valid_polygonal() |>
    sf::st_transform(target_crs) |>
    standardise_geometry_column()
  
  x
}

# ------------------------------------------------------------
# MPA filtering
# ------------------------------------------------------------

apply_mpa_filter <- function(x, status_col = MPA_STATUS_COL) {
  if (!(status_col %in% names(x))) {
    stop(
      "MPA status field not found: ", status_col,
      "\nAvailable fields:\n",
      paste(names(x), collapse = ", ")
    )
  }
  
  status_norm <- normalise_text(x[[status_col]])
  
  x |>
    dplyr::mutate(
      analysis_status_normalised = status_norm,
      analysis_keep = !is.na(analysis_status_normalised) &
        analysis_status_normalised == "working",
      analysis_filter_reason = dplyr::case_when(
        analysis_keep ~ "keep_status_working",
        is.na(analysis_status_normalised) ~ "exclude_status_missing",
        TRUE ~ paste0("exclude_status_", analysis_status_normalised)
      )
    )
}

# ------------------------------------------------------------
# OECM filtering
# ------------------------------------------------------------

apply_oecm_filter <- function(
    x,
    decision_col = OECM_DECISION_COL,
    status_old_col = OECM_STATUS_OLD_COL,
    status_new_col = OECM_STATUS_NEW_COL,
    new_status_overrides_old = OECM_NEW_STATUS_OVERRIDES_OLD,
    new_status_unknown_values = OECM_NEW_STATUS_UNKNOWN_VALUES) {
  
  required_cols <- c(decision_col, status_old_col, status_new_col)
  missing_cols <- setdiff(required_cols, names(x))
  
  if (length(missing_cols) > 0) {
    stop(
      "OECM filtering fields not found: ",
      paste(missing_cols, collapse = ", "),
      "\nAvailable fields:\n",
      paste(names(x), collapse = ", ")
    )
  }
  
  decision_norm <- normalise_token(x[[decision_col]])
  status_old_norm <- normalise_text(x[[status_old_col]])
  status_new_norm <- normalise_text(x[[status_new_col]])
  unknown_values_norm <- normalise_text(new_status_unknown_values)
  unknown_values_norm <- unknown_values_norm[!is.na(unknown_values_norm)]
  
  x <- x |>
    dplyr::mutate(
      analysis_decision_normalised = decision_norm,
      analysis_status_old_normalised = status_old_norm,
      analysis_status_new_normalised = status_new_norm,
      
     
      analysis_status_new_uninformative =
        is.na(analysis_status_new_normalised) |
        analysis_status_new_normalised %in% unknown_values_norm,
      
     
      analysis_status_conflict =
        analysis_status_old_normalised == "working" &
        !analysis_status_new_uninformative &
        analysis_status_new_normalised != "active",
      
      analysis_effective_status_source = dplyr::case_when(
        !analysis_status_new_uninformative ~ "status_new",
        !is.na(analysis_status_old_normalised) ~ "status_old_fallback",
        TRUE ~ NA_character_
      ),
      
      analysis_effective_status = dplyr::case_when(
        !analysis_status_new_uninformative ~ analysis_status_new_normalised,
        TRUE ~ analysis_status_old_normalised
      )
    )
  
  if (new_status_overrides_old) {
    x <- x |>
      dplyr::mutate(
        analysis_keep =
          (is.na(analysis_decision_normalised) |
             analysis_decision_normalised != "drop_candidate") &
          (
            (!analysis_status_new_uninformative &
               analysis_status_new_normalised == "active") |
              (analysis_status_new_uninformative &
                 analysis_status_old_normalised == "working")
          ),
        
        analysis_filter_reason = dplyr::case_when(
          analysis_decision_normalised == "drop_candidate" ~
            "exclude_drop_candidate",
          
          !analysis_status_new_uninformative &
            analysis_status_new_normalised == "active" ~
            "keep_new_active",
          
          !analysis_status_new_uninformative &
            analysis_status_new_normalised != "active" ~
            paste0(
              "exclude_new_status_",
              stringr::str_replace_all(
                analysis_status_new_normalised,
                "[^a-z0-9]+",
                "_"
              )
            ),
          
          is.na(analysis_status_new_normalised) &
            analysis_status_old_normalised == "working" ~
            "keep_old_working_no_new_status",
          
          analysis_status_new_normalised %in% unknown_values_norm &
            analysis_status_old_normalised == "working" ~
            "keep_old_working_new_unknown",
          
          analysis_status_new_uninformative &
            is.na(analysis_status_old_normalised) ~
            "exclude_no_usable_status",
          
          analysis_status_new_normalised %in% unknown_values_norm ~
            paste0(
              "exclude_old_status_",
              stringr::str_replace_all(
                dplyr::coalesce(analysis_status_old_normalised, "missing"),
                "[^a-z0-9]+",
                "_"
              ),
              "_new_unknown"
            ),
          
          TRUE ~
            paste0(
              "exclude_old_status_",
              stringr::str_replace_all(
                dplyr::coalesce(analysis_status_old_normalised, "missing"),
                "[^a-z0-9]+",
                "_"
              )
            )
        )
      )
    
  } else {

    x <- x |>
      dplyr::mutate(
        analysis_keep =
          (is.na(analysis_decision_normalised) |
             analysis_decision_normalised != "drop_candidate") &
          (
            analysis_status_old_normalised == "working" |
              analysis_status_new_normalised == "active"
          ),
        
        analysis_filter_reason = dplyr::case_when(
          analysis_decision_normalised == "drop_candidate" ~
            "exclude_drop_candidate",
          analysis_status_new_normalised == "active" ~
            "keep_new_active",
          analysis_status_old_normalised == "working" ~
            "keep_old_working",
          TRUE ~
            "exclude_not_working_or_active"
        )
      )
  }
  

  x$analysis_keep[is.na(x$analysis_keep)] <- FALSE
  x$analysis_status_conflict[is.na(x$analysis_status_conflict)] <- FALSE
  
  x
}

prepare_for_flexible_bind <- function(x) {
  geom <- sf::st_geometry(x)
  
  attrs <- x |>
    sf::st_drop_geometry() |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character))
  
  sf::st_sf(attrs, geometry = geom) |>
    standardise_geometry_column()
}

bind_sf_flexible <- function(x, y) {
  x2 <- prepare_for_flexible_bind(x)
  y2 <- prepare_for_flexible_bind(y)
  
  dplyr::bind_rows(x2, y2) |>
    standardise_geometry_column()
}

intersect_pa_with_eez <- function(pa_sf, eez_sf, pa_label) {
  eez_zones <- eez_sf |>
    dplyr::select(analysis_sovereign_state)
  
  pieces <- vector("list", nrow(eez_zones))
  
  for (i in seq_len(nrow(eez_zones))) {
    this_eez <- eez_zones[i, , drop = FALSE]
    this_country <- this_eez$analysis_sovereign_state[[1]]
    
    message(pa_label, " x ", this_country)
    
    hits <- sf::st_intersects(pa_sf, this_eez, sparse = TRUE)
    keep <- lengths(hits) > 0
    
    if (!any(keep)) {
      next
    }
    
    pa_subset <- pa_sf[keep, , drop = FALSE]
    
    inter <- suppressWarnings(
      sf::st_intersection(pa_subset, this_eez)
    )
    
    if (nrow(inter) == 0) {
      next
    }
    
    inter <- make_valid_polygonal(inter)
    
    if (nrow(inter) == 0) {
      next
    }
    
    inter <- inter |>
      dplyr::mutate(
        sovereign_state = analysis_sovereign_state,
        analysis_country_pa_id = paste(
          analysis_sovereign_state,
          analysis_pa_id,
          sep = "__"
        )
      )
    
    inter$pa_piece_area_km2 <- as.numeric(sf::st_area(inter)) / 1e6
    pieces[[i]] <- inter
  }
  
  pieces <- purrr::compact(pieces)
  
  if (length(pieces) == 0) {
    stop("No ", pa_label, " features intersected the EEZ layer.")
  }
  
  dplyr::bind_rows(pieces) |>
    standardise_geometry_column()
}

make_unique_by_country <- function(x, area_col) {
  out <- x |>
    dplyr::select(analysis_sovereign_state) |>
    dplyr::group_by(analysis_sovereign_state) |>
    dplyr::summarise(.groups = "drop") |>
    make_valid_polygonal() |>
    dplyr::mutate(sovereign_state = analysis_sovereign_state)
  
  out[[area_col]] <- as.numeric(sf::st_area(out)) / 1e6
  out
}

make_wio_union <- function(x, union_type) {
  geom <- sf::st_union(sf::st_geometry(x))
  
  out <- sf::st_sf(
    union_type = union_type,
    geometry = geom
  ) |>
    make_valid_polygonal()
  
  out$area_km2 <- as.numeric(sf::st_area(out)) / 1e6
  out
}

make_gpkg_safe_field_names <- function(x, layer, gpkg) {
  old_names <- names(x)
  new_names <- old_names
  used_lower <- character(0)
  
  for (i in seq_along(old_names)) {
    base_name <- old_names[i]
    candidate <- base_name
    suffix <- 1
    
    while (tolower(candidate) %in% used_lower) {
      suffix <- suffix + 1
      candidate <- paste0(base_name, "_", suffix)
    }
    
    new_names[i] <- candidate
    used_lower <- c(used_lower, tolower(candidate))
  }
  
  changed <- old_names != new_names
  
  if (any(changed)) {
    message("Renaming duplicate/case-conflicting fields in layer: ", layer)
    
    rename_table <- tibble::tibble(
      layer = layer,
      original_field = old_names[changed],
      gpkg_field = new_names[changed]
    )
    
    print(rename_table)
    
    rename_csv <- file.path(
      dirname(gpkg),
      paste0(layer, "_field_name_mapping.csv")
    )
    
    readr::write_csv(rename_table, rename_csv)
    message("Field-name mapping saved to: ", rename_csv)
  }
  
  old_geometry_col <- attr(x, "sf_column")
  names(x) <- new_names
  
  geometry_position <- match(old_geometry_col, old_names)
  
  if (!is.na(geometry_position)) {
    new_geometry_col <- new_names[geometry_position]
    sf::st_geometry(x) <- new_geometry_col
  }
  
  x
}

write_gpkg_layer <- function(x, gpkg, layer) {
  message("Writing layer: ", layer)
  
  x_write <- make_gpkg_safe_field_names(
    x = x,
    layer = layer,
    gpkg = gpkg
  )
  
  sf::st_write(
    x_write,
    dsn = gpkg,
    layer = layer,
    append = FALSE,
    delete_layer = TRUE,
    quiet = TRUE
  )
  
  message("Finished writing: ", layer)
  invisible(TRUE)
}

# ------------------------------------------------------------
# 4. Start fresh output GeoPackage
# ------------------------------------------------------------

if (file.exists(out_gpkg) && OVERWRITE_MASTER_GPKG) {
  unlink(out_gpkg)
}

# ------------------------------------------------------------
# 5. Read and prepare EEZ
# ------------------------------------------------------------

eez_raw <- read_sf_any(EEZ_PATH, EEZ_LAYER)

if (is.na(sf::st_crs(eez_raw))) {
  message("Assigning missing EEZ CRS: ", SOURCE_EEZ_CRS_IF_MISSING)
  sf::st_crs(eez_raw) <- SOURCE_EEZ_CRS_IF_MISSING
}

if (!(EEZ_SOVEREIGN_COL %in% names(eez_raw))) {
  stop(
    "EEZ sovereign column not found: ",
    EEZ_SOVEREIGN_COL,
    "\nAvailable columns: ",
    paste(names(eez_raw), collapse = ", ")
  )
}

eez_clean <- eez_raw |>
  standardise_geometry_column() |>
  dplyr::mutate(
    analysis_sovereign_state = stringr::str_squish(
      as.character(.data[[EEZ_SOVEREIGN_COL]])
    )
  ) |>
  dplyr::filter(
    !is.na(analysis_sovereign_state),
    analysis_sovereign_state != ""
  ) |>
  make_valid_polygonal() |>
  sf::st_transform(AREA_CRS)

# ------------------------------------------------------------
# 6. Dissolve EEZ by sovereign state
# ------------------------------------------------------------

eez_by_country <- eez_clean |>
  dplyr::select(analysis_sovereign_state) |>
  dplyr::group_by(analysis_sovereign_state) |>
  dplyr::summarise(.groups = "drop") |>
  make_valid_polygonal() |>
  dplyr::mutate(sovereign_state = analysis_sovereign_state)

eez_by_country$eez_area_km2 <- as.numeric(sf::st_area(eez_by_country)) / 1e6

message("EEZ countries: ", nrow(eez_by_country))

# ------------------------------------------------------------
# 7. Read MPA and OECM with ALL original attributes
# ------------------------------------------------------------

mpa_source_full <- prepare_pa_source(
  path = MPA_PATH,
  layer = MPA_LAYER,
  pa_type = "MPA",
  target_crs = AREA_CRS
)

oecm_source_full <- prepare_pa_source(
  path = OECM_PATH,
  layer = OECM_LAYER,
  pa_type = "OECM",
  target_crs = AREA_CRS
)

message("MPA source features: ", nrow(mpa_source_full))
message("OECM source features: ", nrow(oecm_source_full))

# ------------------------------------------------------------
# 8. Apply MPA / OECM filters and retain audit fields
# ------------------------------------------------------------

mpa_source_full <- apply_mpa_filter(
  mpa_source_full,
  status_col = MPA_STATUS_COL
)

oecm_source_full <- apply_oecm_filter(
  oecm_source_full,
  decision_col = OECM_DECISION_COL,
  status_old_col = OECM_STATUS_OLD_COL,
  status_new_col = OECM_STATUS_NEW_COL,
  new_status_overrides_old = OECM_NEW_STATUS_OVERRIDES_OLD
)


message("\nMPA filter summary:")
print(
  mpa_source_full |>
    sf::st_drop_geometry() |>
    dplyr::count(analysis_keep, analysis_filter_reason, sort = TRUE)
)

message("\nOECM filter summary:")
print(
  oecm_source_full |>
    sf::st_drop_geometry() |>
    dplyr::count(analysis_keep, analysis_filter_reason, sort = TRUE)
)

message("\nOECM backwards-status conflicts (old Working, new non-Active): ")
message(sum(oecm_source_full$analysis_status_conflict, na.rm = TRUE))


filter_audit <- dplyr::bind_rows(
  mpa_source_full |>
    sf::st_drop_geometry() |>
    dplyr::count(analysis_keep, analysis_filter_reason, name = "n") |>
    dplyr::mutate(dataset = "MPA"),
  
  oecm_source_full |>
    sf::st_drop_geometry() |>
    dplyr::count(analysis_keep, analysis_filter_reason, name = "n") |>
    dplyr::mutate(dataset = "OECM")
) |>
  dplyr::select(dataset, analysis_keep, analysis_filter_reason, n)

readr::write_csv(filter_audit, out_filter_audit)

# Retained features used in all subsequent spatial calculations.
mpa_filtered_full <- mpa_source_full |>
  dplyr::filter(analysis_keep)

oecm_filtered_full <- oecm_source_full |>
  dplyr::filter(analysis_keep)


oecm_status_conflicts <- oecm_source_full |>
  dplyr::filter(analysis_status_conflict)

message("\nMPA retained: ", nrow(mpa_filtered_full), " / ", nrow(mpa_source_full))
message("OECM retained: ", nrow(oecm_filtered_full), " / ", nrow(oecm_source_full))

if (nrow(mpa_filtered_full) == 0) {
  stop("MPA filtering removed every feature. Check STATUS values.")
}

if (nrow(oecm_filtered_full) == 0) {
  stop("OECM filtering removed every feature. Check decision/status values.")
}

# ------------------------------------------------------------
# 9. Combined source-level protection layers
# ------------------------------------------------------------

protected_features_full <- bind_sf_flexible(
  mpa_source_full,
  oecm_source_full
)

protected_features_filtered <- bind_sf_flexible(
  mpa_filtered_full,
  oecm_filtered_full
)

# ------------------------------------------------------------
# 10. Full-attribute FILTERED MPA x EEZ intersection
# ------------------------------------------------------------

mpa_by_country_individual <- intersect_pa_with_eez(
  pa_sf = mpa_filtered_full,
  eez_sf = eez_by_country,
  pa_label = "MPA"
)

message("MPA x EEZ pieces: ", nrow(mpa_by_country_individual))

# ------------------------------------------------------------
# 11. Full-attribute FILTERED OECM x EEZ intersection
# ------------------------------------------------------------

oecm_by_country_individual <- intersect_pa_with_eez(
  pa_sf = oecm_filtered_full,
  eez_sf = eez_by_country,
  pa_label = "OECM"
)

message("OECM x EEZ pieces: ", nrow(oecm_by_country_individual))

# ------------------------------------------------------------
# 12. Combined full-attribute FILTERED PA x EEZ layer
# ------------------------------------------------------------

protected_by_country_full <- bind_sf_flexible(
  mpa_by_country_individual,
  oecm_by_country_individual
)

# ------------------------------------------------------------
# 13. Unique FILTERED MPA footprint by country
# ------------------------------------------------------------

mpa_unique_by_country <- make_unique_by_country(
  mpa_by_country_individual,
  "mpa_area_km2"
)

# ------------------------------------------------------------
# 14. Unique FILTERED OECM footprint by country
# ------------------------------------------------------------

oecm_unique_by_country <- make_unique_by_country(
  oecm_by_country_individual,
  "oecm_area_km2"
)

# ------------------------------------------------------------
# 15. Unique combined FILTERED MPA + OECM footprint by country
# ------------------------------------------------------------

protected_country_parts <- dplyr::bind_rows(
  mpa_by_country_individual |>
    dplyr::select(analysis_sovereign_state),
  oecm_by_country_individual |>
    dplyr::select(analysis_sovereign_state)
)

protected_unique_by_country <- protected_country_parts |>
  dplyr::group_by(analysis_sovereign_state) |>
  dplyr::summarise(.groups = "drop") |>
  make_valid_polygonal() |>
  dplyr::mutate(sovereign_state = analysis_sovereign_state)

protected_unique_by_country$protected_area_km2 <-
  as.numeric(sf::st_area(protected_unique_by_country)) / 1e6

# ------------------------------------------------------------
# 16. Regional WIO union layers
# ------------------------------------------------------------

mpa_union_wio <- make_wio_union(mpa_unique_by_country, "MPA")
oecm_union_wio <- make_wio_union(oecm_unique_by_country, "OECM")
protected_union_wio <- make_wio_union(protected_unique_by_country, "MPA_OECM")

# ------------------------------------------------------------
# 17. Element 1 summary table
# ------------------------------------------------------------

eez_table <- eez_by_country |>
  sf::st_drop_geometry() |>
  dplyr::select(sovereign_state, eez_area_km2)

mpa_table <- mpa_unique_by_country |>
  sf::st_drop_geometry() |>
  dplyr::select(sovereign_state, mpa_area_km2)

oecm_table <- oecm_unique_by_country |>
  sf::st_drop_geometry() |>
  dplyr::select(sovereign_state, oecm_area_km2)

protected_table <- protected_unique_by_country |>
  sf::st_drop_geometry() |>
  dplyr::select(sovereign_state, protected_area_km2)

country_summary <- eez_table |>
  dplyr::left_join(protected_table, by = "sovereign_state") |>
  dplyr::left_join(mpa_table, by = "sovereign_state") |>
  dplyr::left_join(oecm_table, by = "sovereign_state") |>
  dplyr::mutate(
    protected_area_km2 = tidyr::replace_na(protected_area_km2, 0),
    mpa_area_km2 = tidyr::replace_na(mpa_area_km2, 0),
    oecm_area_km2 = tidyr::replace_na(oecm_area_km2, 0),
    percent_protected_total = 100 * safe_divide(protected_area_km2, eez_area_km2),
    percent_protected_mpa = 100 * safe_divide(mpa_area_km2, eez_area_km2),
    percent_protected_oecm = 100 * safe_divide(oecm_area_km2, eez_area_km2)
  ) |>
  dplyr::arrange(sovereign_state)

wio_row <- country_summary |>
  dplyr::summarise(
    sovereign_state = "WIO",
    eez_area_km2 = sum(eez_area_km2, na.rm = TRUE),
    protected_area_km2 = sum(protected_area_km2, na.rm = TRUE),
    mpa_area_km2 = sum(mpa_area_km2, na.rm = TRUE),
    oecm_area_km2 = sum(oecm_area_km2, na.rm = TRUE)
  ) |>
  dplyr::mutate(
    percent_protected_total = 100 * safe_divide(protected_area_km2, eez_area_km2),
    percent_protected_mpa = 100 * safe_divide(mpa_area_km2, eez_area_km2),
    percent_protected_oecm = 100 * safe_divide(oecm_area_km2, eez_area_km2)
  )

final_summary <- dplyr::bind_rows(country_summary, wio_row)

# ------------------------------------------------------------
# 18. QA checks
# ------------------------------------------------------------

# qa_protection_exceeds_eez <- final_summary |>
#   dplyr::filter(
#     sovereign_state != "WIO",
#     protected_area_km2 > eez_area_km2 + 0.001
#   )
# 
# if (nrow(qa_protection_exceeds_eez) > 0) {
#   warning("Some combined protected areas exceed EEZ area.")
#   print(qa_protection_exceeds_eez)
# }
# 
# qa_combined_vs_types <- final_summary |>
#   dplyr::filter(
#     sovereign_state != "WIO",
#     protected_area_km2 > (mpa_area_km2 + oecm_area_km2) + 0.001
#   )
# 
# if (nrow(qa_combined_vs_types) > 0) {
#   warning("Combined unique protection exceeds MPA + OECM area unexpectedly.")
#   print(qa_combined_vs_types)
# }

# ------------------------------------------------------------
# 19. QA map
# ------------------------------------------------------------

# world <- rnaturalearth::ne_countries(
#   scale = "medium",
#   returnclass = "sf"
# )
# 
# eez_plot <- sf::st_transform(eez_by_country, PLOT_CRS)
# protected_plot <- sf::st_transform(protected_unique_by_country, PLOT_CRS)
# 
# wio_map <- ggplot2::ggplot() +
#   ggplot2::geom_sf(
#     data = world,
#     fill = "grey90",
#     colour = "white",
#     linewidth = 0.2
#   ) +
#   ggplot2::geom_sf(
#     data = eez_plot,
#     fill = "lightblue",
#     colour = "grey40",
#     alpha = 0.25,
#     linewidth = 0.25
#   ) +
#   ggplot2::geom_sf(
#     data = protected_plot,
#     fill = "darkgreen",
#     colour = NA,
#     alpha = 0.5
#   ) +
#   ggplot2::coord_sf(
#     xlim = c(WIO_BBOX[["xmin"]], WIO_BBOX[["xmax"]]),
#     ylim = c(WIO_BBOX[["ymin"]], WIO_BBOX[["ymax"]]),
#     expand = FALSE
#   ) +
#   ggplot2::labs(
#     title = "WIO EEZ and filtered MPA + OECM protection",
#     subtitle = "MPA STATUS = Working; OECM Active, or old Working when new status is missing/Unknown",
#     x = "Longitude",
#     y = "Latitude"
#   ) +
#   ggplot2::theme_minimal()
# 
# print(wio_map)
# 
# ggplot2::ggsave(
#   filename = out_map,
#   plot = wio_map,
#   width = 10,
#   height = 7,
#   dpi = 300
# )

# ------------------------------------------------------------
# 20. Write master GeoPackage
# ------------------------------------------------------------

write_gpkg_layer(eez_by_country, out_gpkg, "eez_by_country")

# Unfiltered source features WITH audit/filter fields.
write_gpkg_layer(mpa_source_full, out_gpkg, "mpa_source_full")
write_gpkg_layer(oecm_source_full, out_gpkg, "oecm_source_full")
write_gpkg_layer(protected_features_full, out_gpkg, "protected_features_full")

# Filtered source features used in analysis.
write_gpkg_layer(mpa_filtered_full, out_gpkg, "mpa_filtered_full")
write_gpkg_layer(oecm_filtered_full, out_gpkg, "oecm_filtered_full")
write_gpkg_layer(protected_features_filtered, out_gpkg, "protected_features_filtered")

# Backwards-status OECMs for manual review.
if (nrow(oecm_status_conflicts) > 0) {
  write_gpkg_layer(oecm_status_conflicts, out_gpkg, "oecm_status_conflicts")
}

# Full-attribute FILTERED EEZ intersections.
write_gpkg_layer(mpa_by_country_individual, out_gpkg, "mpa_by_country_individual")
write_gpkg_layer(oecm_by_country_individual, out_gpkg, "oecm_by_country_individual")
write_gpkg_layer(protected_by_country_full, out_gpkg, "protected_by_country_full")

# Dissolved unique FILTERED footprints.
write_gpkg_layer(mpa_unique_by_country, out_gpkg, "mpa_unique_by_country")
write_gpkg_layer(oecm_unique_by_country, out_gpkg, "oecm_unique_by_country")
write_gpkg_layer(protected_unique_by_country, out_gpkg, "protected_unique_by_country")

# Regional dissolved FILTERED footprints.
write_gpkg_layer(mpa_union_wio, out_gpkg, "mpa_union_wio")
write_gpkg_layer(oecm_union_wio, out_gpkg, "oecm_union_wio")
write_gpkg_layer(protected_union_wio, out_gpkg, "protected_union_wio")

# ------------------------------------------------------------
# 21. Save CSV and print useful checks
# ------------------------------------------------------------

readr::write_csv(final_summary, out_csv)

print(final_summary, n = Inf)

message("\nSaved GeoPackage layers:")
print(sf::st_layers(out_gpkg)$name)

message("\nMPA filter reasons:")
print(
  mpa_source_full |>
    sf::st_drop_geometry() |>
    dplyr::count(analysis_keep, analysis_filter_reason, sort = TRUE)
)

message("\nOECM filter reasons:")
print(
  oecm_source_full |>
    sf::st_drop_geometry() |>
    dplyr::count(analysis_keep, analysis_filter_reason, sort = TRUE)
)

if (nrow(oecm_status_conflicts) > 0) {
  message("\nOECM backwards-status conflicts saved: ", nrow(oecm_status_conflicts))
  
  print(
    oecm_status_conflicts |>
      sf::st_drop_geometry() |>
      dplyr::select(
        dplyr::any_of(c(
          "analysis_pa_id",
          OECM_DECISION_COL,
          OECM_STATUS_OLD_COL,
          OECM_STATUS_NEW_COL,
          "analysis_effective_status",
          "analysis_filter_reason"
        ))
      )
  )
}

message("\nMaster GeoPackage: ", normalizePath(out_gpkg))
message("Summary CSV: ", normalizePath(out_csv))
message("Filter audit CSV: ", normalizePath(out_filter_audit))
message("QA map: ", normalizePath(out_map))
message("Done.")
