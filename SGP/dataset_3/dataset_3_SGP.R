############################################################################
###
### SGP script to calculate SGPs for dataset 3
###
############################################################################

# Load libraries
require(data.table)
require(SGP)

# Load dataset 1
load("../../data/Copula_Sensitivity_Data_Set_3.Rdata")

# Create knots and boundaries for dataset 1
dataset_3_knots_boundaries_1 <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_3[YEAR %in% 2013:2014])
dataset_3_knots_boundaries_2 <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_3[YEAR %in% 2015:2017])
names(dataset_3_knots_boundaries_2) <- paste(names(dataset_3_knots_boundaries_2), "2015", sep=".")

# Embed knots and boundaries into SGPstateData
SGPstateData[["DATASET_3"]][["Achievement"]][["Knots_Boundaries"]] <- c(dataset_3_knots_boundaries_1, dataset_3_knots_boundaries_2)

# Source SGP configurations
source("SGP_CONFIG/MATHEMATICS_config.R")
source("SGP_CONFIG/ELA_config.R")
dataset_3_sgp_config <- c(
    MATHEMATICS_2014.config, READING_2014.config,
    MATHEMATICS_2015.config, ELA_2015.config,
    MATHEMATICS_2016.config, ELA_2016.config,
    MATHEMATICS_2017.config, ELA_2017.config)

# Parameters
### Parallel processing configuration
### Enabled for production runs (4 workers per task)
parallel.config <- list(BACKEND = "PARALLEL", WORKERS = list( PERCENTILES = 8))

# Create SGP object
dataset_3_SGP_Object <- abcSGP(
                sgp_object = Copula_Sensitivity_Data_Set_3,
                steps = c("prepareSGP", "analyzeSGP", "combineSGP"),
                state = "DATASET_3",
                sgp.config = dataset_3_sgp_config,
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
variables.to.save <- setdiff(names(dataset_3_SGP_Object@Data), c("SCALE_SCORE_PRIOR_STANDARDIZED", "SGP_NORM_GROUP"))
Copula_Sensitivity_Data_Set_3_SGP <- dataset_3_SGP_Object@Data[, variables.to.save, with = FALSE]
save(Copula_Sensitivity_Data_Set_3_SGP, file="../../data/Copula_Sensitivity_Data_Set_3_SGP.Rdata")