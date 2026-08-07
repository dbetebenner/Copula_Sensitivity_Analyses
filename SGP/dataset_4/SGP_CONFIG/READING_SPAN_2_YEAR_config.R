############################################################################
###
### SGP configuration for dataset 4: 2-year span of mathematics data
###
############################################################################

READING_2018.config <- list(
  READING_2018 = list(
    sgp.content.areas = rep("READING", 2),
    sgp.panel.years = c("2016", "2018"),
    sgp.grade.sequences = list(
      c("3", "5"),
      c("4", "6"),
      c("5", "7"),
      c("6", "8")
    )
  )
)

READING_2019.config <- list(
  READING_2019 = list(
    sgp.content.areas = rep("READING", 2),
    sgp.panel.years = c("2016", "2017", "2019"),
    sgp.grade.sequences = list(
      c("3", "5"),
      c("3", "4", "6"),
      c("4", "5", "7"),
      c("5", "6", "8")
    )
  )
)

READING_2021.config <- list(
  READING_2021 = list(
    sgp.content.areas = rep("READING", 3),
    sgp.panel.years = c("2018", "2019", "2021"),
    sgp.grade.sequences = list(
      c("3", "5"),
      c("3", "4", "6"),
      c("4", "5", "7"),
      c("5", "6", "8")
    )
  )
)

# NOTE: No 2 year span for 2022 as no testing in 2020

READING_2023.config <- list(
  READING_2023 = list(
    sgp.content.areas = rep("READING", 2),
    sgp.panel.years = c("2021", "2023"),
    sgp.grade.sequences = list(
      c("3", "5"),
      c("4", "6"),
      c("5", "7"),
      c("6", "8")
    )
  )
)

READING_2024.config <- list(
  READING_2024 = list(
    sgp.content.areas = rep("READING", 3),
    sgp.panel.years = c("2021", "2022", "2024"),
    sgp.grade.sequences = list(
      c("3", "5"),
      c("3", "4", "6"),
      c("4", "5", "7"),
      c("5", "6", "8")
    )
  )
)

READING_2025.config <- list(
  READING_2025 = list(
    sgp.content.areas = rep("READING", 3),
    sgp.panel.years = c("2022", "2023", "2025"),
    sgp.grade.sequences = list(
      c("3", "5"),
      c("3", "4", "6"),
      c("4", "5", "7"),
      c("5", "6", "8")
    )
  )
)
