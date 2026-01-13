############################################################################
###
### SGP configuration for dataset 4: MATHEMATICS, Span 4 Years
###
############################################################################

MATHEMATICS_2021.config <- list(
    MATHEMATICS_2021 = list(
        sgp.content.areas=rep("MATHEMATICS", 3),
        sgp.panel.years=c("2016", "2017", "2021"),
        sgp.grade.sequences=list(
            c("3", "7"), c("3", "4", "8"), c("6", "7", "11")
        )
    )
)

MATHEMATICS_2022.config <- list(
    MATHEMATICS_2022 = list(
        sgp.content.areas=rep("MATHEMATICS", 3),
        sgp.panel.years=c("2017", "2018", "2022"),
        sgp.grade.sequences=list(
            c("3", "7"), c("3", "4", "8"), c("6", "7", "11")
        )
    )
)

MATHEMATICS_2023.config <- list(
    MATHEMATICS_2023 = list(
        sgp.content.areas=rep("MATHEMATICS", 3),
        sgp.panel.years=c("2018", "2019", "2023"),
        sgp.grade.sequences=list(
            c("3", "7"), c("3", "4", "8"), c("6", "7", "11")
        )
    )
)

## NOTE: No 2024 4 year span analyses as no 2020 data

MATHEMATICS_2025.config <- list(
    MATHEMATICS_2025 = list(
        sgp.content.areas=rep("MATHEMATICS", 2),
        sgp.panel.years=c("2021", "2025"),
        sgp.grade.sequences=list(
            c("3", "7"), c("4", "8"), c("7", "11")
        )
    )
)