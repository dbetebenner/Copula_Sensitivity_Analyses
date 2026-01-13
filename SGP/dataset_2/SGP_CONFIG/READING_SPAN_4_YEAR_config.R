############################################################################
###
### SGP configuration for dataset 2: READING, Span 4 Years
### Note: Limited grade sequences due to grade 8 maximum (no G9)
###
############################################################################

READING_2011.config <- list(
    READING_2011 = list(
        sgp.content.areas=rep("READING", 2),
        sgp.panel.years=c("2007", "2011"),
        sgp.grade.sequences=list(
            c("3", "7"), c("4", "8")
        )
    )
)

READING_2012.config <- list(
    READING_2012 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2007", "2008", "2012"),
        sgp.grade.sequences=list(
            c("3", "7"), c("3", "4", "8")
        )
    )
)

READING_2013.config <- list(
    READING_2013 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2008", "2009", "2013"),
        sgp.grade.sequences=list(
            c("3", "7"), c("3", "4", "8")
        )
    )
)

READING_2014.config <- list(
    READING_2014 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2009", "2010", "2014"),
        sgp.grade.sequences=list(
            c("3", "7"), c("3", "4", "8")
        )
    )
)
