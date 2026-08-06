# ================================================================
# CREATE A VIRTUAL MOSAIC OF THE GLOBAL SEAGRASS TILES
# ================================================================
rm(list = ls())

library(terra)

# Folder containing all original GlobalSeagrass GeoTIFF tiles.
seagrass_tile_dir <- "indicators/GlobalSeagrass2023_2024"

# Find all TIFF files, including any in subfolders.
seagrass_files <- list.files(
  path       = seagrass_tile_dir,
  pattern    = "\\.tif$",
  full.names = TRUE,
  recursive  = TRUE,
  ignore.case = TRUE
)

if (length(seagrass_files) == 0) {
  stop("No GeoTIFF files were found in: ", seagrass_tile_dir)
}

message("Number of seagrass tiles found: ", length(seagrass_files))

# Path for the virtual raster.
vrt_file <- file.path(
  seagrass_tile_dir,
  "GlobalSeagrass2023_2024_global.vrt"
)

# Create the virtual mosaic.
#
# This does not copy or merge the underlying pixel data.
# The original TIFF files must remain in their current locations.
seagrass_vrt <- terra::vrt(
  x         = seagrass_files,
  filename  = vrt_file,
  overwrite = TRUE
)

print(seagrass_vrt)

# Check raster properties.
print(terra::crs(seagrass_vrt))
print(terra::res(seagrass_vrt))
print(terra::ext(seagrass_vrt))
print(terra::datatype(seagrass_vrt))
print(terra::nlyr(seagrass_vrt))
