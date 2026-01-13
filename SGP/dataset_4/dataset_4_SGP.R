############################################################################
###
### SGP script to calculate SGPs for dataset 4
###
############################################################################

# Load libraries
require(data.table)
require(SGP)

# Load dataset 4
load("../../Data/Copula_Sensitivity_Data_Set_4.Rdata")
Copula_Sensitivity_Data_Set_4_SGP <- copy(Copula_Sensitivity_Data_Set_4)


# Create knots and boundaries for dataset 1
dataset_4_knots_boundaries <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_4)

# Embed knots and boundaries into SGPstateData
SGPstateData[["dataset_4"]][["Achievement"]][["Knots_Boundaries"]] <- dataset_4_knots_boundaries
SGPstateData[["dataset_4"]][["SGP_Configuration"]][['print.other.gp']] <- TRUE
SGPstateData[["dataset_4"]][["SGP_Configuration"]][['print.sgp.order']] <- TRUE


# Source SGP 1 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_1_YEAR_config.R")
source("SGP_CONFIG/READING_SPAN_1_YEAR_config.R")
dataset_4_span_1_year_sgp_config <- c(
    MATHEMATICS_2017.config, READING_2017.config,
    MATHEMATICS_2018.config, READING_2018.config,
    MATHEMATICS_2019.config, READING_2019.config,
    MATHEMATICS_2022.config, READING_2022.config,
    MATHEMATICS_2023.config, READING_2023.config,
    MATHEMATICS_2024.config, READING_2024.config,
    MATHEMATICS_2025.config, READING_2025.config)

# Source SGP 2 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_2_YEAR_config.R")
source("SGP_CONFIG/READING_SPAN_2_YEAR_config.R")
dataset_4_span_2_year_sgp_config <- c(
    MATHEMATICS_2018.config, READING_2018.config,
    MATHEMATICS_2019.config, READING_2019.config,
    MATHEMATICS_2021.config, READING_2021.config,
    MATHEMATICS_2023.config, READING_2023.config,
    MATHEMATICS_2024.config, READING_2024.config,
    MATHEMATICS_2025.config, READING_2025.config)

# Source SGP 3 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_3_YEAR_config.R")
source("SGP_CONFIG/READING_SPAN_3_YEAR_config.R")
dataset_4_span_3_year_sgp_config <- c(
    MATHEMATICS_2019.config, READING_2019.config,
    MATHEMATICS_2021.config, READING_2021.config,
    MATHEMATICS_2022.config, READING_2022.config,
    MATHEMATICS_2024.config, READING_2024.config,
    MATHEMATICS_2025.config, READING_2025.config)

# Source SGP 4 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_4_YEAR_config.R")
source("SGP_CONFIG/READING_SPAN_4_YEAR_config.R")
dataset_4_span_4_year_sgp_config <- c(
    MATHEMATICS_2021.config, READING_2021.config,
    MATHEMATICS_2022.config, READING_2022.config,
    MATHEMATICS_2023.config, READING_2023.config,
    MATHEMATICS_2025.config, READING_2025.config)

dataset_4_config <- list(
    dataset_4_span_1_year_sgp_config,
    dataset_4_span_2_year_sgp_config,
    dataset_4_span_3_year_sgp_config,
    dataset_4_span_4_year_sgp_config)

# Parameters
### Parallel processing configuration
### Enabled for production runs (4 workers per task)
parallel.config <- list(BACKEND = "PARALLEL", WORKERS = list( PERCENTILES = 8))

# Loop over time span configurations
for (span_config in seq_along(dataset_4_config)) {
    dataset_4_SGP_Object <- abcSGP(
                sgp_object = Copula_Sensitivity_Data_Set_4,
                steps = c("prepareSGP", "analyzeSGP", "combineSGP"),
                state = "dataset_4",
                sgp.config = dataset_4_config[[span_config]],
                sgp.percentiles = TRUE,
                sgp.projections = FALSE,
                sgp.projections.lagged = FALSE,
                sgp.percentiles.baseline = FALSE,
                sgp.projections.baseline = FALSE,
                sgp.projections.lagged.baseline = FALSE,
                prepareSGP.create.additional.variables = FALSE,
                parallel.config = parallel.config
            )

    variables.to.save <- c("SGP", "SGP_ORDER_1", "SGP_ORDER_2", "SGP_ORDER", "SCALE_SCORE_PRIOR")
    Copula_Sensitivity_Data_Set_4_SGP[, (variables.to.save) := dataset_4_SGP_Object@Data[, (variables.to.save), with = FALSE]]
    setnames(Copula_Sensitivity_Data_Set_4_SGP, variables.to.save, paste0(variables.to.save, "_SPAN_", span_config, "_YEAR"))
} # End loop over time span configurations

# Save SGP results
save(Copula_Sensitivity_Data_Set_4_SGP, file="../../Data/Copula_Sensitivity_Data_Set_4_SGP.Rdata")
