#!/bin/bash
###############################################################################
# Sync results from Copula_Sensitivity_Analyses to Paper_1
# Run after STEP_4 completes or when paper needs updated results
###############################################################################

set -e

PAPER_DIR="$HOME/Research/Papers/Betebenner_Braun/Paper_1"

if [ ! -d "$PAPER_DIR" ]; then
  echo "Error: Paper directory not found: $PAPER_DIR"
  echo "Expected: ~/Research/Papers/Betebenner_Braun/Paper_1/"
  exit 1
fi

echo "======================================================================"
echo "Syncing Copula_Sensitivity_Analyses -> Paper_1"
echo "======================================================================"

# Create target directories if needed
mkdir -p "$PAPER_DIR/Figures/from_analysis"
mkdir -p "$PAPER_DIR/Tables"

# Sync figures from all steps
echo "Copying figures..."

if [ -d "STEP_1_Family_Selection/results" ]; then
  rsync -av --update STEP_1_Family_Selection/results/*.pdf \
    "$PAPER_DIR/Figures/from_analysis/" 2>/dev/null || echo "  No STEP_1 PDFs found"
fi

if [ -d "STEP_2_Transformation_Validation/results/figures" ]; then
  rsync -av --update STEP_2_Transformation_Validation/results/figures/exp5_transformation_validation/*.pdf \
    "$PAPER_DIR/Figures/from_analysis/" 2>/dev/null || echo "  No STEP_2 figures found"
fi

if [ -d "STEP_3_Sensitivity_Analyses/results" ]; then
  find STEP_3_Sensitivity_Analyses/results -name "*.pdf" -exec \
    rsync -av --update {} "$PAPER_DIR/Figures/from_analysis/" \; 2>/dev/null || echo "  No STEP_3 PDFs found"
fi

if [ -d "STEP_4_Deep_Dive_Reporting/results/figures" ]; then
  rsync -av --update STEP_4_Deep_Dive_Reporting/results/figures/*.pdf \
    "$PAPER_DIR/Figures/from_analysis/" 2>/dev/null || echo "  No STEP_4 figures found"
fi

# Sync LaTeX tables
echo "Copying LaTeX tables..."
if [ -d "STEP_4_Deep_Dive_Reporting/results/tables" ]; then
  rsync -av --update STEP_4_Deep_Dive_Reporting/results/tables/*.tex \
    "$PAPER_DIR/Tables/" 2>/dev/null || echo "  No tables found"
fi

# Create/update sync log
echo "Last sync: $(date)" > .last_sync_to_paper.txt
echo "Synced to: $PAPER_DIR" >> .last_sync_to_paper.txt
echo "Files synced:" >> .last_sync_to_paper.txt
ls -1 "$PAPER_DIR/Figures/from_analysis/" | head -20 >> .last_sync_to_paper.txt

# Update .project_links.yml with sync timestamp
if command -v yq &> /dev/null; then
  yq eval ".downstream[0].last_sync = \"$(date)\"" -i .project_links.yml
fi

echo ""
echo "======================================================================"
echo "Sync complete"
echo "======================================================================"
echo "Figures: $PAPER_DIR/Figures/from_analysis/"
echo "Tables: $PAPER_DIR/Tables/"
echo ""
echo "Next: cd to paper directory and review updated materials"
