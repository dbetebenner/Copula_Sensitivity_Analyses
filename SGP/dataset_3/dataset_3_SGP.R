############################################################################
###
### SGP script to calculate SGPs for dataset 3
### Multi-year span version (1, 2, 3, 4 year priors)
### Years 2013-2017, Grades 3-8, Content Areas: MATHEMATICS, ELA
### Note: ELA content area was unified (formerly READING pre-2015)
###
############################################################################

# Load libraries
require(data.table)
require(SGP)

# Load dataset 3
load("../../Data/Copula_Sensitivity_Data_Set_3.Rdata")
Copula_Sensitivity_Data_Set_3_SGP <- copy(Copula_Sensitivity_Data_Set_3)


# Create knots and boundaries for dataset 3
dataset_3_knots_boundaries <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_3)
dataset_3_knots_boundaries_ELA_2014 <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_3[CONTENT_AREA == "ELA" & YEAR <= 2014])
dataset_3_knots_boundaries_ELA_2017 <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_3[CONTENT_AREA == "ELA" & YEAR > 2014 & YEAR <= 2017])
dataset_3_knots_boundaries[['ELA']] <- dataset_3_knots_boundaries_ELA_2014[['ELA']]
dataset_3_knots_boundaries[['ELA.2015']] <- dataset_3_knots_boundaries_ELA_2017[['ELA']]

# Embed knots and boundaries into SGPstateData
SGPstateData[["DATASET_3"]][["Achievement"]][["Knots_Boundaries"]] <- dataset_3_knots_boundaries
SGPstateData[["DATASET_3"]][["SGP_Configuration"]][['print.other.gp']] <- TRUE
SGPstateData[["DATASET_3"]][["SGP_Configuration"]][['print.sgp.order']] <- TRUE


# Source SGP 1 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_1_YEAR_config.R")
source("SGP_CONFIG/ELA_SPAN_1_YEAR_config.R")
dataset_3_span_1_year_sgp_config <- c(
    MATHEMATICS_2014.config, ELA_2014.config,
    MATHEMATICS_2015.config, ELA_2015.config,
    MATHEMATICS_2016.config, ELA_2016.config,
    MATHEMATICS_2017.config, ELA_2017.config)

# Source SGP 2 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_2_YEAR_config.R")
source("SGP_CONFIG/ELA_SPAN_2_YEAR_config.R")
dataset_3_span_2_year_sgp_config <- c(
    MATHEMATICS_2015.config, ELA_2015.config,
    MATHEMATICS_2016.config, ELA_2016.config,
    MATHEMATICS_2017.config, ELA_2017.config)

# Source SGP 3 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_3_YEAR_config.R")
source("SGP_CONFIG/ELA_SPAN_3_YEAR_config.R")
dataset_3_span_3_year_sgp_config <- c(
    MATHEMATICS_2016.config, ELA_2016.config,
    MATHEMATICS_2017.config, ELA_2017.config)

# Source SGP 4 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_4_YEAR_config.R")
source("SGP_CONFIG/ELA_SPAN_4_YEAR_config.R")
dataset_3_span_4_year_sgp_config <- c(
    MATHEMATICS_2017.config, ELA_2017.config)

dataset_3_config <- list(
    dataset_3_span_1_year_sgp_config,
    dataset_3_span_2_year_sgp_config,
    dataset_3_span_3_year_sgp_config,
    dataset_3_span_4_year_sgp_config)

# Parameters
### Parallel processing configuration
### Enabled for production runs (8 workers per task)
parallel.config <- list(BACKEND = "PARALLEL", WORKERS = list(PERCENTILES = 8))
#parallel.config <- NULL

# Loop over time span configurations
for (span_config in seq_along(dataset_3_config)) {
    dataset_3_SGP_Object <- abcSGP(
                sgp_object = Copula_Sensitivity_Data_Set_3,
                steps = c("prepareSGP", "analyzeSGP", "combineSGP"),
                state = "DATASET_3",
                sgp.config = dataset_3_config[[span_config]],
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
    Copula_Sensitivity_Data_Set_3_SGP[, (variables.to.save) := dataset_3_SGP_Object@Data[, (variables.to.save), with = FALSE]]
    setnames(Copula_Sensitivity_Data_Set_3_SGP, variables.to.save, paste0(variables.to.save, "_SPAN_", span_config, "_YEAR"))
} # End loop over time span configurations

# Save SGP results
save(Copula_Sensitivity_Data_Set_3_SGP, file="../../Data/Copula_Sensitivity_Data_Set_3_SGP.Rdata")
