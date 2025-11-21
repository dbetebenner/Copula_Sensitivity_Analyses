#!/bin/bash
################################################################################
# Progress Monitor for Copula Analysis
# Usage: ./monitor_progress.sh [dataset_id]
#   Example: ./monitor_progress.sh dataset_1
#   If no dataset specified, monitors dataset_all (combined)
################################################################################

# Determine which progress file to monitor
if [ -z "$1" ]; then
  PROGRESS_FILE="STEP_1_Family_Selection/results/dataset_all/.progress.txt"
  DATASET_LABEL="Combined (All Datasets)"
else
  PROGRESS_FILE="STEP_1_Family_Selection/results/$1/.progress.txt"
  DATASET_LABEL="$1"
fi

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Clear screen
clear

echo "========================================================================"
echo "  COPULA ANALYSIS PROGRESS MONITOR"
echo "========================================================================"
echo "  Dataset: $DATASET_LABEL"
echo "  Progress file: $PROGRESS_FILE"
echo "========================================================================"
echo ""

# Check if file exists
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "${RED}✗ Progress file not found!${NC}"
  echo ""
  echo "Expected: $PROGRESS_FILE"
  echo ""
  echo "Possible reasons:"
  echo "  1. Analysis hasn't started yet"
  echo "  2. Wrong dataset ID specified"
  echo "  3. Working directory is incorrect"
  echo ""
  echo "To start analysis, run:"
  echo "  cd /path/to/Copula_Sensitivity_Analyses"
  echo "  Rscript master_analysis.R"
  echo ""
  exit 1
fi

# Function to display summary
show_summary() {
  echo ""
  echo "========================================================================"
  echo "  CURRENT STATUS"
  echo "========================================================================"
  
  # Count events
  local started=$(grep -c "STARTED" "$PROGRESS_FILE" 2>/dev/null || echo "0")
  local completed=$(grep -c "COMPLETE" "$PROGRESS_FILE" 2>/dev/null || echo "0")
  local errors=$(grep -c "ERROR" "$PROGRESS_FILE" 2>/dev/null || echo "0")
  local running=$((started - completed - errors))
  
  echo "  Started:   ${BLUE}$started${NC}"
  echo "  Completed: ${GREEN}$completed${NC}"
  echo "  Running:   ${YELLOW}$running${NC}"
  if [ $errors -gt 0 ]; then
    echo "  Errors:    ${RED}$errors${NC}"
  fi
  
  # Show completion percentage
  if [ $started -gt 0 ]; then
    local pct=$((completed * 100 / started))
    echo "  Progress:  ${pct}% complete"
  fi
  
  echo "========================================================================"
  echo ""
  echo "Recent activity (last 15 lines):"
  echo "------------------------------------------------------------------------"
  tail -15 "$PROGRESS_FILE" | while IFS= read -r line; do
    if [[ $line == *"STARTED"* ]]; then
      echo "${BLUE}$line${NC}"
    elif [[ $line == *"COMPLETE"* ]]; then
      echo "${GREEN}$line${NC}"
    elif [[ $line == *"ERROR"* ]]; then
      echo "${RED}$line${NC}"
    else
      echo "$line"
    fi
  done
  echo "------------------------------------------------------------------------"
  echo ""
  echo "Press Ctrl+C to exit | Refreshing every 5 seconds..."
}

# Monitor loop
while true; do
  clear
  echo "========================================================================"
  echo "  COPULA ANALYSIS PROGRESS MONITOR"
  echo "========================================================================"
  echo "  Dataset: $DATASET_LABEL"
  echo "  Updated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "========================================================================"
  
  show_summary
  
  # Check if analysis is complete
  if grep -q "ANALYSIS COMPLETE" "$PROGRESS_FILE" 2>/dev/null; then
    echo ""
    echo "${GREEN}✓✓✓ ANALYSIS COMPLETE ✓✓✓${NC}"
    echo ""
    echo "Final summary:"
    tail -10 "$PROGRESS_FILE"
    echo ""
    exit 0
  fi
  
  sleep 5
done

