############################################################################
###
### SGP configuration for dataset 2: MATHEMATICS, Span 3 Years
### Note: Maximum ending grade is 8 for span 3 (no G9)
###
############################################################################

MATHEMATICS_2010.config <- list(
    MATHEMATICS_2010 = list(
        sgp.content.areas=rep("MATHEMATICS", 2),
        sgp.panel.years=c("2007", "2010"),
        sgp.grade.sequences=list(
            c("3", "6"), c("4", "7"), c("5", "8"), c("7", "10")
        )
    )
)

MATHEMATICS_2011.config <- list(
    MATHEMATICS_2011 = list(
        sgp.content.areas=rep("MATHEMATICS", 3),
        sgp.panel.years=c("2007", "2008", "2011"),
        sgp.grade.sequences=list(
            c("3", "6"), c("3", "4", "7"), c("4", "5", "8"), c("6", "7", "10")
        )
    )
)

MATHEMATICS_2012.config <- list(
    MATHEMATICS_2012 = list(
        sgp.content.areas=rep("MATHEMATICS", 3),
        sgp.panel.years=c("2008", "2009", "2012"),
        sgp.grade.sequences=list(
            c("3", "6"), c("3", "4", "7"), c("4", "5", "8"), c("6", "7", "10")
        )
    )
)

MATHEMATICS_2013.config <- list(
    MATHEMATICS_2013 = list(
        sgp.content.areas=rep("MATHEMATICS", 3),
        sgp.panel.years=c("2009", "2010", "2013"),
        sgp.grade.sequences=list(
            c("3", "6"), c("3", "4", "7"), c("4", "5", "8"), c("6", "7", "10")
        )
    )
)

MATHEMATICS_2014.config <- list(
    MATHEMATICS_2014 = list(
        sgp.content.areas=rep("MATHEMATICS", 3),
        sgp.panel.years=c("2010", "2011", "2014"),
        sgp.grade.sequences=list(
            c("3", "6"), c("3", "4", "7"), c("4", "5", "8"), c("6", "7", "10")
        )
    )
)
