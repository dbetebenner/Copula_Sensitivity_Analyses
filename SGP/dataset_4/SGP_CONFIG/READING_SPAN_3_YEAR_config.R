############################################################################
###
### SGP configuration for dataset 4: READING, Span 3 Years
###
############################################################################

READING_2019.config <- list(
    READING_2019 = list(
        sgp.content.areas=rep("READING", 2),
        sgp.panel.years=c("2016", "2019"),
        sgp.grade.sequences=list(
            c("3", "6"), c("4", "7"), c("5", "8"), c("8", "11")
        )
    )
)

READING_2021.config <- list(
    READING_2021 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2017", "2018", "2021"),
        sgp.grade.sequences=list(
            c("3", "6"), c("3", "4", "7"), c("4", "5", "8"), c("7", "8", "11")
        )
    )
)

READING_2022.config <- list(
    READING_2022 = list(
        sgp.content.areas=rep("READING", 2),
        sgp.panel.years=c("2018", "2019", "2022"),
        sgp.grade.sequences=list(
            c("3", "6"), c("3", "4", "7"), c("4", "5", "8"), c("7", "8", "11")
        )
    )
)

# NOTE: No 3 year span for 2023 as no testing in 2020

READING_2024.config <- list(
    READING_2024 = list(
        sgp.content.areas=rep("READING", 2),
        sgp.panel.years=c("2021", "2024"),
        sgp.grade.sequences=list(
            c("3", "6"), c("4", "7"), c("5", "8"), c("8", "11")
        )
    )
)

READING_2025.config <- list(
    READING_2025 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2021", "2022", "2025"),
        sgp.grade.sequences=list(
            c("3", "6"), c("3", "4", "7"), c("4", "5", "8"), c("7", "8", "11")
        )
    )
)