############################################################################
###
### SGP configuration for dataset 3: ELA, Span 2 Years
### Years 2013-2017, Grades 3-8
### Note: Content area unified to ELA (formerly READING pre-2015)
###
############################################################################

ELA_2015.config <- list(
    ELA_2015 = list(
        sgp.content.areas=rep("ELA", 2),
        sgp.panel.years=c("2013", "2015"),
        sgp.grade.sequences=list(
            c("3", "5"), c("4", "6"), c("5", "7"), c("6", "8")
        )
    )
)

ELA_2016.config <- list(
    ELA_2016 = list(
        sgp.content.areas=rep("ELA", 3),
        sgp.panel.years=c("2013", "2014", "2016"),
        sgp.grade.sequences=list(
            c("3", "5"), c("3", "4", "6"), c("4", "5", "7"), c("5", "6", "8")
        )
    )
)

ELA_2017.config <- list(
    ELA_2017 = list(
        sgp.content.areas=rep("ELA", 3),
        sgp.panel.years=c("2014", "2015", "2017"),
        sgp.grade.sequences=list(
            c("3", "5"), c("3", "4", "6"), c("4", "5", "7"), c("5", "6", "8")
        )
    )
)
