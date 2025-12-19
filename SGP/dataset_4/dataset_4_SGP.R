############################################################################
###
### SGP script to calculate SGPs for dataset 4
###
############################################################################

# Load libraries
require(data.table)
require(SGP)

# Load dataset 1
load("../../data/Copula_Sensitivity_Data_Set_4.Rdata")

# Create knots and boundaries for dataset 1
dataset_4_knots_boundaries <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_4)

# Embed knots and boundaries into SGPstateData
SGPstateData[["dataset_4"]][["Achievement"]][["Knots_Boundaries"]] <- dataset_4_knots_boundaries
SGPstateData[["dataset_4"]][["SGP_Configuration"]][['print.other.gp']] <- TRUE
SGPstateData[["dataset_4"]][["SGP_Configuration"]][['print.sgp.order']] <- TRUE


# Source SGP configurations
source("SGP_CONFIG/MATHEMATICS_config.R")
source("SGP_CONFIG/READING_config.R")
dataset_4_sgp_config <- c(
    MATHEMATICS_2017.config, READING_2017.config,
    MATHEMATICS_2018.config, READING_2018.config,
    MATHEMATICS_2019.config, MATHEMATICS_2019.g11.config, READING_2019.config, READING_2019.g11.config,
    MATHEMATICS_2021.config, MATHEMATICS_2021.g11.config, READING_2021.config, READING_2021.g11.config,
    MATHEMATICS_2022.config, MATHEMATICS_2022.g11.config, READING_2022.config, READING_2022.g11.config,
    MATHEMATICS_2023.config, READING_2023.config,
    MATHEMATICS_2024.config, MATHEMATICS_2024.g11.config, READING_2024.config, READING_2024.g11.config,
    MATHEMATICS_2025.config, MATHEMATICS_2025.g11.config, READING_2025.config, READING_2025.g11.config)

# Parameters
### Parallel processing configuration
### Enabled for production runs (4 workers per task)
parallel.config <- list(BACKEND = "PARALLEL", WORKERS = list( PERCENTILES = 8))

# Create SGP object
dataset_4_SGP_Object <- abcSGP(
                sgp_object = Copula_Sensitivity_Data_Set_4,
                steps = c("prepareSGP", "analyzeSGP", "combineSGP"),
                state = "dataset_4",
                sgp.config = dataset_4_sgp_config,
                sgp.percentiles = TRUE,
                sgp.projections = FALSE,
                sgp.projections.lagged = FALSE,
                sgp.percentiles.baseline = FALSE,
                sgp.projections.baseline = FALSE,
                sgp.projections.lagged.baseline = FALSE,
                prepareSGP.create.additional.variables = FALSE,
                parallel.config = parallel.config
)

# Save SGP results
variables.to.save <- setdiff(names(dataset_4_SGP_Object@Data), c("SCALE_SCORE_PRIOR_STANDARDIZED", "SGP_NORM_GROUP"))
Copula_Sensitivity_Data_Set_4_SGP <- dataset_4_SGP_Object@Data[, variables.to.save, with = FALSE]
save(Copula_Sensitivity_Data_Set_4_SGP, file="../../data/Copula_Sensitivity_Data_Set_4_SGP.Rdata")
