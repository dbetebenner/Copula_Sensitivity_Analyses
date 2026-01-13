############################################################################
###
### SGP script to calculate SGPs for dataset 1
### Multi-year span version (1, 2, 3, 4 year priors)
###
############################################################################

# Load libraries
require(data.table)
require(SGP)

# Load dataset 1
load("../../data/Copula_Sensitivity_Data_Set_1.Rdata")
Copula_Sensitivity_Data_Set_1_SGP <- copy(Copula_Sensitivity_Data_Set_1)


# Create knots and boundaries for dataset 1
dataset_1_knots_boundaries <- SGP::createKnotsBoundaries(Copula_Sensitivity_Data_Set_1)

# Embed knots and boundaries into SGPstateData
SGPstateData[["DATASET_1"]][["Achievement"]][["Knots_Boundaries"]] <- dataset_1_knots_boundaries
SGPstateData[["DATASET_1"]][["SGP_Configuration"]][['print.other.gp']] <- TRUE
SGPstateData[["DATASET_1"]][["SGP_Configuration"]][['print.sgp.order']] <- TRUE


# Source SGP 1 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_1_YEAR_config.R")
source("SGP_CONFIG/READING_SPAN_1_YEAR_config.R")
source("SGP_CONFIG/WRITING_SPAN_1_YEAR_config.R")
dataset_1_span_1_year_sgp_config <- c(
    MATHEMATICS_2006.config, READING_2006.config, WRITING_2006.config,
    MATHEMATICS_2007.config, READING_2007.config, WRITING_2007.config,
    MATHEMATICS_2008.config, READING_2008.config, WRITING_2008.config,
    MATHEMATICS_2009.config, READING_2009.config, WRITING_2009.config,
    MATHEMATICS_2010.config, READING_2010.config, WRITING_2010.config,
    MATHEMATICS_2011.config, READING_2011.config, WRITING_2011.config,
    MATHEMATICS_2012.config, READING_2012.config, WRITING_2012.config,
    MATHEMATICS_2013.config, READING_2013.config, WRITING_2013.config,
    MATHEMATICS_2014.config, READING_2014.config, WRITING_2014.config)

# Source SGP 2 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_2_YEAR_config.R")
source("SGP_CONFIG/READING_SPAN_2_YEAR_config.R")
source("SGP_CONFIG/WRITING_SPAN_2_YEAR_config.R")
dataset_1_span_2_year_sgp_config <- c(
    MATHEMATICS_2007.config, READING_2007.config, WRITING_2007.config,
    MATHEMATICS_2008.config, READING_2008.config, WRITING_2008.config,
    MATHEMATICS_2009.config, READING_2009.config, WRITING_2009.config,
    MATHEMATICS_2010.config, READING_2010.config, WRITING_2010.config,
    MATHEMATICS_2011.config, READING_2011.config, WRITING_2011.config,
    MATHEMATICS_2012.config, READING_2012.config, WRITING_2012.config,
    MATHEMATICS_2013.config, READING_2013.config, WRITING_2013.config,
    MATHEMATICS_2014.config, READING_2014.config, WRITING_2014.config)

# Source SGP 3 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_3_YEAR_config.R")
source("SGP_CONFIG/READING_SPAN_3_YEAR_config.R")
source("SGP_CONFIG/WRITING_SPAN_3_YEAR_config.R")
dataset_1_span_3_year_sgp_config <- c(
    MATHEMATICS_2008.config, READING_2008.config, WRITING_2008.config,
    MATHEMATICS_2009.config, READING_2009.config, WRITING_2009.config,
    MATHEMATICS_2010.config, READING_2010.config, WRITING_2010.config,
    MATHEMATICS_2011.config, READING_2011.config, WRITING_2011.config,
    MATHEMATICS_2012.config, READING_2012.config, WRITING_2012.config,
    MATHEMATICS_2013.config, READING_2013.config, WRITING_2013.config,
    MATHEMATICS_2014.config, READING_2014.config, WRITING_2014.config)

# Source SGP 4 year span configurations
source("SGP_CONFIG/MATHEMATICS_SPAN_4_YEAR_config.R")
source("SGP_CONFIG/READING_SPAN_4_YEAR_config.R")
source("SGP_CONFIG/WRITING_SPAN_4_YEAR_config.R")
dataset_1_span_4_year_sgp_config <- c(
    MATHEMATICS_2009.config, READING_2009.config, WRITING_2009.config,
    MATHEMATICS_2010.config, READING_2010.config, WRITING_2010.config,
    MATHEMATICS_2011.config, READING_2011.config, WRITING_2011.config,
    MATHEMATICS_2012.config, READING_2012.config, WRITING_2012.config,
    MATHEMATICS_2013.config, READING_2013.config, WRITING_2013.config,
    MATHEMATICS_2014.config, READING_2014.config, WRITING_2014.config)

dataset_1_config <- list(
    dataset_1_span_1_year_sgp_config,
    dataset_1_span_2_year_sgp_config,
    dataset_1_span_3_year_sgp_config,
    dataset_1_span_4_year_sgp_config)

# Parameters
### Parallel processing configuration
### Enabled for production runs (8 workers per task)
parallel.config <- list(BACKEND = "PARALLEL", WORKERS = list(PERCENTILES = 8))

# Loop over time span configurations
for (span_config in seq_along(dataset_1_config)) {
    dataset_1_SGP_Object <- abcSGP(
                sgp_object = Copula_Sensitivity_Data_Set_1,
                steps = c("prepareSGP", "analyzeSGP", "combineSGP"),
                state = "DATASET_1",
                sgp.config = dataset_1_config[[span_config]],
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
    Copula_Sensitivity_Data_Set_1_SGP[, (variables.to.save) := dataset_1_SGP_Object@Data[, (variables.to.save), with = FALSE]]
    setnames(Copula_Sensitivity_Data_Set_1_SGP, variables.to.save, paste0(variables.to.save, "_SPAN_", span_config, "_YEAR"))
} # End loop over time span configurations

# Save SGP results
save(Copula_Sensitivity_Data_Set_1_SGP, file="../../data/Copula_Sensitivity_Data_Set_1_SGP.Rdata")
