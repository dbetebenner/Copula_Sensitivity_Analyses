############################################################################
###
### SGP configuration for dataset 3: ELA, Span 1 Year
### Years 2013-2017, Grades 3-8
### Note: Content area unified to ELA (formerly READING pre-2015)
###
############################################################################

ELA_2014.config <- list(
  ELA_2014 = list(
    sgp.content.areas = rep("ELA", 2),
    sgp.panel.years = c("2013", "2014"),
    sgp.grade.sequences = list(
      c("3", "4"),
      c("4", "5"),
      c("5", "6"),
      c("6", "7"),
      c("7", "8")
    )
  )
)

ELA_2015.config <- list(
  ELA_2015 = list(
    sgp.content.areas = rep("ELA", 3),
    sgp.panel.years = c("2013", "2014", "2015"),
    sgp.grade.sequences = list(
      c("3", "4"),
      c("3", "4", "5"),
      c("4", "5", "6"),
      c("5", "6", "7"),
      c("6", "7", "8")
    )
  )
)

ELA_2016.config <- list(
  ELA_2016 = list(
    sgp.content.areas = rep("ELA", 3),
    sgp.panel.years = c("2014", "2015", "2016"),
    sgp.grade.sequences = list(
      c("3", "4"),
      c("3", "4", "5"),
      c("4", "5", "6"),
      c("5", "6", "7"),
      c("6", "7", "8")
    )
  )
)

ELA_2017.config <- list(
  ELA_2017 = list(
    sgp.content.areas = rep("ELA", 3),
    sgp.panel.years = c("2015", "2016", "2017"),
    sgp.grade.sequences = list(
      c("3", "4"),
      c("3", "4", "5"),
      c("4", "5", "6"),
      c("5", "6", "7"),
      c("6", "7", "8")
    )
  )
)
