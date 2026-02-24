############################################################################
###
### STEP 3 Publication Style Bridge
###
### Reuses STEP 2 visual conventions (Zissou1 palette, theme_publication,
### save_plot_multi) and defines STEP 3-specific semantic colour mappings.
###
### Author: dataimago
### Date: February 2026
### Project: Copula Sensitivity Analyses — STEP 3 (LIwLD)
###
############################################################################

require(ggplot2)
require(wesanderson)

############################################################################
### Palette: Zissou1 base (shared with STEP 1 and STEP 2)
############################################################################

ZISSOU1_BASE <- wes_palette("Zissou1")
ZISSOU1_RAMP <- colorRampPalette(ZISSOU1_BASE)

############################################################################
### STEP 3 semantic colour assignments
############################################################################

STEP3_COLORS <- list(
  observed     = "grey30",
  predicted    = ZISSOU1_BASE[1],   # teal   (#3B9AB2)
  inferred     = ZISSOU1_BASE[1],   # teal
  actual       = ZISSOU1_BASE[4],   # amber  (#E1AF00)
  residual_pos = ZISSOU1_BASE[5],   # red    (#F21A00)
  residual_neg = ZISSOU1_BASE[1],   # teal
  bootstrap    = ZISSOU1_BASE[1],   # teal
  true_value   = ZISSOU1_BASE[4],   # amber
  point_est    = ZISSOU1_BASE[1],   # teal
  ci_line      = "grey50",
  reference    = "grey50",
  loess_trend  = ZISSOU1_BASE[5]    # red
)

REGIME_FAMILY_COLORS <- c(
  beta      = ZISSOU1_BASE[1],   # teal
  truncexp  = ZISSOU1_BASE[4],   # amber
  truncunif = ZISSOU1_BASE[3]    # gold (#EBCC2A)
)

REGIME_FAMILY_LINETYPES <- c(
  beta      = "solid",
  truncexp  = "dashed",
  truncunif = "dotdash"
)

UNCERTAINTY_COLORS <- c(
  "Sampling"  = ZISSOU1_BASE[4],   # amber
  "Copula"    = ZISSOU1_BASE[1],   # teal
  "Family"    = ZISSOU1_BASE[3]    # gold
)

############################################################################
### Publication theme (identical to STEP 2)
############################################################################

theme_publication <- function(base_size = 10) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title       = element_text(face = "bold", size = base_size + 4, hjust = 0),
      plot.subtitle    = element_text(size = base_size + 1, color = "gray30"),
      axis.title       = element_text(face = "bold", size = base_size + 1),
      axis.text        = element_text(size = base_size),
      legend.title     = element_text(face = "bold", size = base_size),
      legend.text      = element_text(size = base_size - 1),
      legend.position  = "right",
      legend.background = element_rect(fill = alpha("white", 0.85),
                                        color = "gray60", linewidth = 0.5),
      panel.grid.minor = element_blank(),
      panel.border     = element_rect(fill = NA, color = "gray80"),
      strip.text       = element_text(face = "bold", size = base_size),
      strip.background = element_rect(fill = "gray95", color = "gray80")
    )
}

############################################################################
### Standard panel dimensions (matching STEP 2)
############################################################################

PLOT_WIDTH  <- 10
PLOT_HEIGHT <- 7
PLOT_DPI    <- 300

############################################################################
### Multi-format save (mirrors STEP 2's save_plot_multi)
############################################################################

save_plot_multi <- function(plot, name, dir,
                             width = PLOT_WIDTH,
                             height = PLOT_HEIGHT,
                             dpi = PLOT_DPI) {

  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)

  for (fmt in c("pdf", "svg", "png")) {
    filepath <- file.path(dir, paste0(name, ".", fmt))

    device <- if (fmt == "pdf" && capabilities("cairo")) cairo_pdf else fmt

    ggsave(
      filename = filepath,
      plot     = plot,
      width    = width,
      height   = height,
      dpi      = dpi,
      device   = device
    )
    cat(sprintf("  Saved: %s\n", filepath))
  }
}

############################################################################
### Reference line helpers
############################################################################

geom_ref_hline <- function(yintercept, ...) {
  geom_hline(yintercept = yintercept, linetype = "dashed",
             color = "gray50", linewidth = 0.5, ...)
}

geom_ref_vline <- function(xintercept, ...) {
  geom_vline(xintercept = xintercept, linetype = "dashed",
             color = "gray50", linewidth = 0.5, ...)
}


cat("STEP 3 step3_publication_style.R loaded.\n")
cat("  theme_publication(), save_plot_multi(), STEP3_COLORS, REGIME_FAMILY_COLORS\n")
