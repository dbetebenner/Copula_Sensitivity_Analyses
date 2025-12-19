############################################################################
###
### SGP configuration for dataset 4
###
############################################################################

READING_2017.config <- list(
    READING_2017 = list(
        sgp.content.areas=rep("READING", 2),
        sgp.panel.years=c("2016", "2017"),
        sgp.grade.sequences=list(
            c("3", "4"), c("4", "5"), c("5", "6"), c("6", "7"), c("7", "8")
        )
    )
)

READING_2018.config <- list(
    READING_2018 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2016", "2017", "2018"),
        sgp.grade.sequences=list(
            c("3", "4"), c("3", "4", "5"), c("4", "5", "6"), c("5", "6", "7"), c("6", "7", "8")
        )
    )
)

READING_2019.config <- list(
    READING_2019 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2017", "2018", "2019"),
        sgp.grade.sequences=list(
            c("3", "4"), c("3", "4", "5"), c("4", "5", "6"), c("5", "6", "7"), c("6", "7", "8")
        )
    )
)

READING_2019.g11.config <- list(
    READING_2019_g11 = list(
        sgp.content.areas=rep("READING", 2),
        sgp.panel.years=c("2016", "2019"),
        sgp.grade.sequences=list(
            c("8", "11")
        )
    )
)

READING_2021.config <- list(
    READING_2021 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2018", "2019", "2021"),
        sgp.grade.sequences=list(
            c("3", "5"), c("3", "4", "6"), c("4", "5", "7"), c("5", "6", "8")
        )
    )
)

READING_2021.g11.config <- list(
    READING_2021_g11 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2017", "2018", "2021"),
        sgp.grade.sequences=list(
            c("7", "8", "11")
        )
    )
)

READING_2022.config <- list(
    READING_2022 = list(
        sgp.content.areas=rep("READING", 2),
        sgp.panel.years=c("2021", "2022"),
        sgp.grade.sequences=list(
            c("3", "4"), c("4", "5"), c("5", "6"), c("6", "7"), c("7", "8")
        )
    )
)

READING_2022.g11.config <- list(
    READING_2022_g11 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2018", "2019", "2022"),
        sgp.grade.sequences=list(
            c("7", "8", "11")
        )
    )
)

READING_2023.config <- list(
    READING_2023 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2021", "2022", "2023"),
        sgp.grade.sequences=list(
            c("3", "4"), c("3", "4", "5"), c("4", "5", "6"), c("5", "6", "7"), c("6", "7", "8")
        )
    )
)

## NOTE: No Grade 11 analyses in 2023 (no 8th grade prior in 2020)

READING_2024.config <- list(
    READING_2024 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2022", "2023", "2024"),
        sgp.grade.sequences=list(
            c("3", "4"), c("3", "4", "5"), c("4", "5", "6"), c("5", "6", "7"), c("6", "7", "8")
        )
    )
)

READING_2024.g11.config <- list(
    READING_2024_g11 = list(
        sgp.content.areas=rep("READING", 2),
        sgp.panel.years=c("2021", "2024"),
        sgp.grade.sequences=list(
            c("8", "11")
        )
    )
)

READING_2025.config <- list(
    READING_2025 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2023", "2024", "2025"),
        sgp.grade.sequences=list(
            c("3", "4"), c("3", "4", "5"), c("4", "5", "6"), c("5", "6", "7"), c("6", "7", "8")
        )
    )
)

READING_2025.g11.config <- list(
    READING_2025_g11 = list(
        sgp.content.areas=rep("READING", 3),
        sgp.panel.years=c("2021", "2022", "2025"),
        sgp.grade.sequences=list(
            c("7", "8", "11")
        )
    )
)
