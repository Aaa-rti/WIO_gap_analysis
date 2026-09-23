# WIO GAP ANALYSIS

## Overview

This repository contains R scripts used to assess gaps in marine protection across the Western Indian Ocean (WIO). The analyses are organised into five elements:

- Overall marine protection
- Ecological representativeness of habitats
- Areas of biodiversity importance
- Ecological connectivity
- Conservation sustainability

Sovereign Exclusive Economic Zones (EEZs) are used as the main reporting units. Ecological indicators and spatial features are assessed against Marine Protected Areas (MPAs) and Other Effective Area-Based Conservation Measures (OECMs).

Raw spatial datasets are not stored in this repository. Publicly available data sources are listed below where available.


## Input data

### Element 1 — EEZs and protected areas

- WIO EEZs: data source to be added
- Marine Protected Areas: data source to be added
- OECM / LMMA data: data source to be added


### Element 2 — Habitat representativeness

- Coral reefs:
  UNEP-WCMC Global Distribution of Coral Reefs  
  https://data-gis.unep-wcmc.org/server/rest/services/HabitatsAndBiotopes/Global_Distribution_of_Coral_Reefs/FeatureServer

- Allen Coral Atlas

- Seagrass:  
  https://doi.org/10.5281/zenodo.18612240

- Mangroves:  
  https://doi.org/10.3390/rs14153657

- Seamounts: data source to be added


### Element 3 — Areas of biodiversity importance

- Key Biodiversity Areas (KBAs): data source to be added
- Important Bird Areas (IBAs): data source to be added

- Turtle nesting sites:  
  State of the World's Sea Turtles (SWOT) / OBIS-SEAMAP  
  https://seamap.env.duke.edu/swot

- Ecologically or Biologically Significant Marine Areas (EBSAs):  
  Convention on Biological Diversity EBSA Repository  
  https://www.cbd.int/ebsa/repository

- Fish larval dispersal connectivity: data source to be added


### Element 4 — Connectivity

- Marine migration connections (MiCO):  
  https://doi.org/10.5281/zenodo.14873514


### Element 5 — Larval sources and sinks

- Fish larval dispersal connectivity: data source to be added


## Repository workflow

1. Element1_protection.R  
   Creates the WIO EEZ and protected-area spatial database.

2. Element2_habitat.R  
   Assesses ecological representativeness of habitats within protected areas.

3. Element2_plots.R and Element2_giniplot.R  
   Produce publication figures from the Element 2 outputs.

4. Element3_important_areas.R  
   Assesses the representation of areas of particular importance for biodiversity and ecosystem functions and services.

5. Element3_plots  
   Produces the Element 3 summary figure.

6. Element4_migratory_connectivity  
   Assesses the representation of migratory connectivity using MiCO connections.

7. Element5_sustainability.R  
   Assesses the protection of important larval sources and sinks.

8. Element4_5_combined_plots  
   Combines the Element 4 and Element 5 connectivity results into summary figures.


## Final outputs

The finalised_tables_and_figures folder contains the final outputs used for reporting and publication.
