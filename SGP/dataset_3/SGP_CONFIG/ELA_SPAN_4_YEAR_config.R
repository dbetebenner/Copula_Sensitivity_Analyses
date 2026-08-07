############################################################################
###
### SGP configuration for dataset 3: ELA, Span 4 Years
### Years 2013-2017, Grades 3-8 (only 2017 has 4-year prior available)
### Note: Content area unified to ELA (formerly READING pre-2015)
###
############################################################################

ELA_2017.config <- list(
  ELA_2017 = list(
    sgp.content.areas = rep("ELA", 2),
    sgp.panel.years = c("2013", "2017"),
    sgp.grade.sequences = list(
      c("3", "7"),
      c("4", "8")
    )
  )
)
