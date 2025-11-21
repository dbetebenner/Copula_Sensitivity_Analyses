# ==============================================================================
# Multi-Format Plot Export Utility
# ==============================================================================
#
# Purpose:
#   Simplify the workflow for exporting R plots to multiple formats (PDF, SVG, 
#   PNG) with a single function call. This eliminates code duplication and makes
#   it easy for AI assistants to generate multi-format exports.
#
# Features:
#   - Export to PDF (print quality), SVG (web/vector), and PNG (retina raster)
#   - Template-based filename generation with full path support
#   - Font embedding for SVG (Noto Sans by default)
#   - Transparent background support
#   - Customizable dimensions, resolution, and device parameters
#   - Robust error handling with cleanup
#
# Author: Generated for Betebenner-Braun project
# Date: 2025-11-12
# ==============================================================================

#' Export Plot to Multiple Formats (PDF, SVG, PNG)
#'
#' This function exports a plot to three high-quality formats with a single
#' call, eliminating code duplication. The plot code is executed once per
#' format, ensuring consistency across outputs.
#'
#' @param plot_expr A function or expression containing the plot code.
#'   Can be a function (e.g., `my_plot_function`) or an inline expression.
#' @param base_filename Character string for the base filename or full path.
#'   - Simple name: "figure" → "figure.pdf", "figure.svg", "figure@2x.png"
#'   - Full path: "/path/to/figure" → "/path/to/figure.pdf", etc.
#'   Default: "figure"
#' @param width Numeric. Plot width in inches. Default: 7
#' @param height Numeric. Plot height in inches. Default: 7
#' @param formats Character vector. Formats to export. Options: "pdf", "svg", "png".
#'   Default: c("pdf", "svg", "png")
#' @param bg_transparent Logical. Use transparent background? Default: TRUE
#' @param bg_color Character or rgb(). Background color if not transparent.
#'   Default: "white"
#' @param svg_fonts Named list. Font mappings for SVG export via svglite.
#'   Default: list(sans = "Noto Sans", serif = "Noto Sans", mono = "Noto Sans")
#'   Set to NULL to use system defaults.
#' @param png_res Numeric. PNG resolution in DPI. Default: 200
#' @param png_scale Numeric. PNG scale multiplier for retina displays.
#'   Default: 2 (creates @2x images)
#' @param png_suffix Character. Suffix for PNG filename. Default: "@2x"
#' @param verbose Logical. Print status messages? Default: TRUE
#' @param ... Additional arguments passed to device functions
#'
#' @return Invisibly returns a named list of output file paths
#'
#' @examples
#' \dontrun{
#' # Minimal usage with default settings
#' export_plot_multi_format(
#'   plot_expr = function() plot(1:10, main = "Simple Plot"),
#'   base_filename = "my_plot"
#' )
#'
#' # Custom path with specific formats
#' export_plot_multi_format(
#'   plot_expr = my_complex_plot_function,
#'   base_filename = "/Users/me/figures/analysis_2024",
#'   formats = c("svg", "png")
#' )
#'
#' # Advanced: customize all parameters
#' export_plot_multi_format(
#'   plot_expr = function() {
#'     par(mar = c(4, 4, 2, 1))
#'     plot(rnorm(100), pch = 19, col = "steelblue")
#'   },
#'   base_filename = "scatter",
#'   width = 8,
#'   height = 6,
#'   bg_transparent = FALSE,
#'   bg_color = "#F5F5F5",
#'   png_res = 300,
#'   png_scale = 3
#' )
#' }
#'
#' @section AI Assistant Usage:
#'   This function is designed to be AI-friendly. To generate multi-format
#'   exports, the AI should:
#'   1. Define plot code in a function
#'   2. Call this function once with desired parameters
#'   3. All three formats will be created automatically
#'
#' @export
export_plot_multi_format <- function(
  plot_expr,
  base_filename = "figure",
  width = 7,
  height = 7,
  formats = c("pdf", "svg", "png"),
  bg_transparent = TRUE,
  bg_color = "white",
  svg_fonts = list(sans = "Noto Sans", serif = "Noto Sans", mono = "Noto Sans"),
  png_res = 200,
  png_scale = 2,
  png_suffix = "@2x",
  verbose = TRUE,
  ...
) {
  
  # Validate required packages
  validate_export_packages(formats)
  
  # Validate formats
  valid_formats <- c("pdf", "svg", "png")
  formats <- match.arg(formats, valid_formats, several.ok = TRUE)
  
  # Parse filename and build output paths
  file_info <- parse_filename_template(base_filename)
  output_paths <- build_output_paths(
    dir = file_info$dir,
    base = file_info$base,
    formats = formats,
    png_suffix = png_suffix
  )
  
  # Prepare background setting
  if (bg_transparent) {
    bg_setting <- rgb(1, 1, 1, alpha = 0.0)
  } else {
    bg_setting <- bg_color
  }
  
  # Export to each format
  for (fmt in formats) {
    if (verbose) {
      message(sprintf("Exporting to %s: %s", toupper(fmt), output_paths[[fmt]]))
    }
    
    # Open the appropriate device
    tryCatch({
      
      if (fmt == "pdf") {
        pdf(
          file = output_paths$pdf,
          width = width,
          height = height,
          bg = bg_setting,
          ...
        )
      } else if (fmt == "svg") {
        # Check if svg_fonts should be passed
        if (!is.null(svg_fonts)) {
          svglite::svglite(
            file = output_paths$svg,
            width = width,
            height = height,
            bg = bg_setting,
            system_fonts = svg_fonts,
            ...
          )
        } else {
          svglite::svglite(
            file = output_paths$svg,
            width = width,
            height = height,
            bg = bg_setting,
            ...
          )
        }
      } else if (fmt == "png") {
        # Calculate pixel dimensions: inches * dpi * scale
        width_px <- width * png_res * png_scale / png_res  # Simplifies to: width * png_scale
        height_px <- height * png_res * png_scale / png_res  # Simplifies to: height * png_scale
        
        ragg::agg_png(
          filename = output_paths$png,
          width = width_px,
          height = height_px,
          units = "in",
          res = png_res * png_scale,
          background = bg_setting,
          ...
        )
      }
      
      # Execute the plot code
      if (is.function(plot_expr)) {
        plot_expr()
      } else {
        eval(plot_expr)
      }
      
      # Close the device
      dev.off()
      
    }, error = function(e) {
      # Ensure device is closed even on error
      if (dev.cur() > 1) dev.off()
      stop(sprintf("Error exporting to %s: %s", fmt, e$message))
    })
  }
  
  if (verbose) {
    message(sprintf("\nSuccessfully exported to %d format(s):", length(formats)))
    for (fmt in formats) {
      message(sprintf("  - %s", output_paths[[fmt]]))
    }
  }
  
  # Return paths invisibly
  invisible(output_paths)
}


#' Export ggplot2 Object to Multiple Formats (PDF, SVG, PNG)
#'
#' ggplot2-compatible wrapper for multi-format export. Uses ggsave() internally
#' for each format, maintaining the same API as export_plot_multi_format().
#'
#' @param plot_obj A ggplot object to export
#' @param base_filename Character string for the base filename or full path.
#'   - Simple name: "figure" → "figure.pdf", "figure.svg", "figure@2x.png"
#'   - Full path: "/path/to/figure" → "/path/to/figure.pdf", etc.
#' @param width Numeric. Plot width in inches. Default: 8
#' @param height Numeric. Plot height in inches. Default: 7
#' @param formats Character vector. Formats to export. Options: "pdf", "svg", "png".
#'   Default: c("pdf", "svg", "png")
#' @param png_suffix Character. Suffix for PNG filename. Default: "@2x"
#' @param png_scale Numeric. PNG scale multiplier for retina displays. Default: 2
#' @param dpi Numeric. Base resolution for raster output. Default: 300
#' @param verbose Logical. Print status messages? Default: TRUE
#' @param ... Additional arguments passed to ggsave()
#'
#' @return Invisibly returns a named list of output file paths
#'
#' @examples
#' \dontrun{
#' # Create a ggplot object
#' library(ggplot2)
#' p <- ggplot(mtcars, aes(mpg, hp)) +
#'   geom_point(color = "steelblue") +
#'   theme_minimal() +
#'   labs(title = "MPG vs Horsepower")
#'
#' # Export to all formats
#' export_ggplot_multi_format(
#'   plot_obj = p,
#'   base_filename = "scatter_plot"
#' )
#'
#' # Custom path and selective formats
#' export_ggplot_multi_format(
#'   plot_obj = p,
#'   base_filename = "/path/to/figures/analysis",
#'   formats = c("svg", "png")
#' )
#'
#' # High-resolution for publication
#' export_ggplot_multi_format(
#'   plot_obj = p,
#'   base_filename = "publication_figure",
#'   width = 8,
#'   height = 6,
#'   dpi = 600,
#'   png_scale = 3,
#'   png_suffix = "@3x"
#' )
#' }
#'
#' @section Usage with Copula Plots:
#'   This function is designed for ggplot2 objects created by copula visualization
#'   functions. It enables consistent multi-format export across all copula plots:
#'   contour plots, uncertainty visualizations, comparison plots, etc.
#'
#' @export
export_ggplot_multi_format <- function(
  plot_obj,
  base_filename,
  width = 8,
  height = 7,
  formats = c("pdf", "svg", "png"),
  png_suffix = "@2x",
  png_scale = 2,
  dpi = 300,
  verbose = TRUE,
  ...
) {
  
  # Validate that ggplot2 is available
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required. Install with: install.packages('ggplot2')")
  }
  
  # Validate that plot_obj is a ggplot object
  if (!inherits(plot_obj, "ggplot")) {
    stop("plot_obj must be a ggplot object. Use export_plot_multi_format() for base R plots.")
  }
  
  # Validate required packages for requested formats
  validate_export_packages(formats)
  
  # Validate formats
  valid_formats <- c("pdf", "svg", "png")
  formats <- match.arg(formats, valid_formats, several.ok = TRUE)
  
  # Parse filename and build output paths
  file_info <- parse_filename_template(base_filename)
  output_paths <- build_output_paths(
    dir = file_info$dir,
    base = file_info$base,
    formats = formats,
    png_suffix = png_suffix
  )
  
  # Export to each format
  for (fmt in formats) {
    if (verbose) {
      message(sprintf("Exporting ggplot to %s: %s", toupper(fmt), output_paths[[fmt]]))
    }
    
    tryCatch({
      
      if (fmt == "pdf") {
        ggplot2::ggsave(
          filename = output_paths$pdf,
          plot = plot_obj,
          width = width,
          height = height,
          device = "pdf",
          ...
        )
      } else if (fmt == "svg") {
        ggplot2::ggsave(
          filename = output_paths$svg,
          plot = plot_obj,
          width = width,
          height = height,
          device = svglite::svglite,
          bg = "transparent",
          ...
        )
      } else if (fmt == "png") {
        # For PNG: use scaled dimensions and high DPI
        ggplot2::ggsave(
          filename = output_paths$png,
          plot = plot_obj,
          width = width,
          height = height,
          units = "in",
          dpi = dpi * png_scale,
          device = ragg::agg_png,
          ...
        )
      }
      
    }, error = function(e) {
      stop(sprintf("Error exporting ggplot to %s: %s", fmt, e$message))
    })
  }
  
  if (verbose) {
    message(sprintf("Successfully exported ggplot to %d format(s)", length(formats)))
  }
  
  # Return paths invisibly
  invisible(output_paths)
}


#' Validate Required Packages for Export
#'
#' Internal helper to check if required packages are installed
#'
#' @param formats Character vector of formats to check
#' @keywords internal
validate_export_packages <- function(formats) {
  missing_pkgs <- character(0)
  
  if ("svg" %in% formats && !requireNamespace("svglite", quietly = TRUE)) {
    missing_pkgs <- c(missing_pkgs, "svglite")
  }
  
  if ("png" %in% formats && !requireNamespace("ragg", quietly = TRUE)) {
    missing_pkgs <- c(missing_pkgs, "ragg")
  }
  
  if (length(missing_pkgs) > 0) {
    stop(
      sprintf(
        "Required package(s) not installed: %s\nInstall with: install.packages(c('%s'))",
        paste(missing_pkgs, collapse = ", "),
        paste(missing_pkgs, collapse = "', '")
      )
    )
  }
  
  invisible(TRUE)
}


#' Parse Filename Template into Directory and Basename
#'
#' Internal helper to extract directory and basename from a path
#'
#' @param filename Character string (full path or simple name)
#' @return List with `dir` (directory path or "") and `base` (basename)
#' @keywords internal
parse_filename_template <- function(filename) {
  # Normalize path
  filename <- path.expand(filename)
  
  # Check if it contains directory separators
  if (grepl("/", filename)) {
    dir_part <- dirname(filename)
    base_part <- basename(filename)
  } else {
    dir_part <- ""
    base_part <- filename
  }
  
  # Remove any existing extension from basename
  base_part <- sub("\\.[a-zA-Z]+$", "", base_part)
  
  list(dir = dir_part, base = base_part)
}


#' Build Output Paths for All Formats
#'
#' Internal helper to construct output file paths
#'
#' @param dir Character string. Directory path (empty string for current dir)
#' @param base Character string. Base filename without extension
#' @param formats Character vector. Formats to generate paths for
#' @param png_suffix Character. Suffix for PNG files (e.g., "@2x")
#' @return Named list of file paths
#' @keywords internal
build_output_paths <- function(dir, base, formats, png_suffix = "@2x") {
  paths <- list()
  
  # Helper to construct full path
  make_path <- function(filename) {
    if (dir == "") {
      filename
    } else {
      file.path(dir, filename)
    }
  }
  
  # Build paths for each format
  if ("pdf" %in% formats) {
    paths$pdf <- make_path(paste0(base, ".pdf"))
  }
  
  if ("svg" %in% formats) {
    paths$svg <- make_path(paste0(base, ".svg"))
  }
  
  if ("png" %in% formats) {
    paths$png <- make_path(paste0(base, png_suffix, ".png"))
  }
  
  paths
}


# ==============================================================================
# Usage Examples
# ==============================================================================
#
# Example 1: Minimal usage (defaults to all formats)
# --------------------------------------------------
# source("export_plot_utils.R")
#
# simple_plot <- function() {
#   plot(1:10, type = "b", pch = 19, col = "steelblue",
#        main = "Simple Line Plot", xlab = "X", ylab = "Y")
# }
#
# export_plot_multi_format(
#   plot_expr = simple_plot,
#   base_filename = "simple_plot"
# )
#
#
# Example 2: Custom path and selective formats
# ---------------------------------------------
# export_plot_multi_format(
#   plot_expr = simple_plot,
#   base_filename = "/Users/me/Documents/figures/my_analysis",
#   formats = c("svg", "png")  # Only SVG and PNG
# )
#
#
# Example 3: Advanced customization
# ----------------------------------
# complex_plot <- function() {
#   par(mar = c(5, 5, 3, 2), bg = "#FAFAFA")
#   x <- seq(0, 2*pi, length.out = 100)
#   plot(x, sin(x), type = "l", lwd = 2, col = "#E74C3C",
#        main = "Sine Wave", xlab = "x", ylab = "sin(x)")
#   grid(col = "grey80", lty = 2)
# }
#
# export_plot_multi_format(
#   plot_expr = complex_plot,
#   base_filename = "sine_wave",
#   width = 8,
#   height = 6,
#   bg_transparent = FALSE,
#   bg_color = "#FAFAFA",
#   png_res = 300,
#   png_scale = 3,  # 3x retina
#   png_suffix = "@3x"
# )
#
#
# Example 4: Using inline expression
# -----------------------------------
# export_plot_multi_format(
#   plot_expr = {
#     hist(rnorm(1000), col = "lightblue", border = "white",
#          main = "Normal Distribution", xlab = "Value")
#   },
#   base_filename = "histogram"
# )
#
#
# Example 5: AI-friendly pattern for complex plots
# -------------------------------------------------
# create_scatter_plot <- function() {
#   set.seed(42)
#   x <- rnorm(100)
#   y <- 2*x + rnorm(100, sd = 0.5)
#   
#   plot(x, y, pch = 19, col = rgb(0, 0, 1, 0.5),
#        main = "Scatter Plot with Regression",
#        xlab = "Predictor", ylab = "Response")
#   abline(lm(y ~ x), col = "red", lwd = 2)
#   grid(col = "grey90")
#   legend("topleft", legend = c("Data", "Fit"),
#          pch = c(19, NA), lty = c(NA, 1),
#          col = c(rgb(0, 0, 1, 0.5), "red"), lwd = c(NA, 2))
# }
#
# export_plot_multi_format(
#   plot_expr = create_scatter_plot,
#   base_filename = "scatter_analysis",
#   width = 7,
#   height = 7
# )
#
# ==============================================================================

