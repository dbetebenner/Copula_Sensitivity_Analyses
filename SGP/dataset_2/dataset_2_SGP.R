############################################################################
###
### SGP script to calculate SGPs for dataset 2
###
############################################################################

# Load libraries
require(data.table)
require(SGP)

# Load dataset 1
load("../../data/Copula_Sensitivity_Data_Set_2.Rdata")

# Create knots and boundaries for dataset 1
dataset_2_knots_boundaries <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_2)

# Embed knots and boundaries into SGPstateData
SGPstateData[["DATASET_2"]][["Achievement"]][["Knots_Boundaries"]] <- dataset_2_knots_boundaries

# Source SGP configurations
source("SGP_CONFIG/MATHEMATICS_config.R")
source("SGP_CONFIG/READING_config.R")
dataset_2_sgp_config <- c(
    MATHEMATICS_2008.config, READING_2008.config,
    MATHEMATICS_2009.config, READING_2009.config,
    MATHEMATICS_2010.config, READING_2010.config,
    MATHEMATICS_2011.config, READING_2011.config,
    MATHEMATICS_2012.config, READING_2012.config,
    MATHEMATICS_2013.config, READING_2013.config,
    MATHEMATICS_2014.config, READING_2014.config)

# Parameters
### Parallel processing configuration
### Enabled for production runs (4 workers per task)
parallel.config <- list(BACKEND = "PARALLEL", WORKERS = list( PERCENTILES = 8))

# Create SGP object
dataset_2_SGP_Object <- abcSGP(
                sgp_object = Copula_Sensitivity_Data_Set_2,
                steps = c("prepareSGP", "analyzeSGP", "combineSGP"),
                state = "DATASET_2",
                sgp.config = dataset_2_sgp_config,
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
variables.to.save <- setdiff(names(dataset_2_SGP_Object@Data), c("SCALE_SCORE_PRIOR_STANDARDIZED", "SGP_NORM_GROUP"))
Copula_Sensitivity_Data_Set_2_SGP <- dataset_2_SGP_Object@Data[, variables.to.save, with = FALSE]
save(Copula_Sensitivity_Data_Set_2_SGP, file="../../data/Copula_Sensitivity_Data_Set_2_SGP.Rdata")