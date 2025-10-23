# Generic Data System for Multi-State Analysis

## Overview

The copula sensitivity analysis framework has been refactored to support data from any state, not just Colorado. The system uses generic object names and configurable data paths to make it easy to switch between different states.

## How It Works

### 1. Generic Data Object
- **Workspace Object Name**: `STATE_DATA_LONG` (used throughout all step files)
- **Access Function**: `get_state_data()` (cleaner than direct access)
- **State-Specific .Rdata Object**: Defined in configuration (e.g., `Copula_Sensitivity_Test_Data_CO`)

### 2. Configuration System
- **Default**: Colorado configuration built into `master_analysis.R`
- **Custom**: Create `state_config.R` from `state_config_template.R`
- **Automatic**: Script detects and loads external configuration if present

## Usage

### For Colorado (Default)
```r
# No configuration needed - uses built-in Colorado settings
source("master_analysis.R")
```

### For Other States
1. **Copy the template:**
   ```bash
   cp state_config_template.R state_config.R
   ```

2. **Edit state_config.R:**
   ```r
   STATE_NAME <- "Massachusetts"
   STATE_ABBREV <- "MA"
   RDATA_OBJECT_NAME <- "Massachusetts_Data_LONG"
   EC2_DATA_PATH <- "/path/to/MA_data.Rdata"
   LOCAL_DATA_PATH <- "/path/to/MA_data.Rdata"
   ```

3. **Run analysis:**
   ```r
   source("master_analysis.R")
   ```

## Data Requirements

Your state data must be a data.table with these columns:
- `ID`: Student identifier
- `GRADE`: Grade level
- `YEAR`: Assessment year
- `CONTENT_AREA`: Subject area (e.g., "MATHEMATICS", "READING")
- `SCALE_SCORE`: IRT-scaled score

## Configuration Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `STATE_NAME` | Full state name | "Massachusetts" |
| `STATE_ABBREV` | State abbreviation | "MA" |
| `WORKSPACE_OBJECT_NAME` | Generic object name in workspace (keep as "STATE_DATA_LONG") | "STATE_DATA_LONG" |
| `RDATA_OBJECT_NAME` | Data table object name inside .RData file | "Massachusetts_Data_LONG" |
| `EC2_DATA_PATH` | Path to data file on EC2 | "/home/ec2-user/data/MA_data.Rdata" |
| `LOCAL_DATA_PATH` | Path to data file locally | "/Users/username/data/MA_data.Rdata" |

## Step File Changes

All step files now use the generic system:

### Before (Colorado-specific):
```r
# Load Colorado data
if (!exists("Colorado_Data_LONG")) {
  load("/path/to/Colorado_Data_LONG.RData")
  Colorado_Data_LONG <- as.data.table(Colorado_Data_LONG)
}

# Use data
create_longitudinal_pairs(data = Colorado_Data_LONG, ...)
```

### After (Generic):
```r
# Data is loaded centrally by master_analysis.R
# STATE_DATA_LONG should already be available

# Use data
create_longitudinal_pairs(data = get_state_data(), ...)
```

## Benefits

1. **Easy State Switching**: Change one configuration file
2. **Consistent Interface**: All step files use same data access pattern
3. **Error Prevention**: Centralized data loading prevents path issues
4. **Maintainability**: Single place to update data loading logic
5. **Flexibility**: Works with any state's data structure

## Testing

The system includes built-in validation:
- Checks that required columns exist
- Verifies data is loaded correctly
- Provides clear error messages if configuration is wrong

## Examples

### Massachusetts Configuration
```r
STATE_NAME <- "Massachusetts"
STATE_ABBREV <- "MA"
RDATA_OBJECT_NAME <- "Massachusetts_Data_LONG"
EC2_DATA_PATH <- "/home/ec2-user/SGP/Dropbox/Massachusetts/Data/Massachusetts_Data_LONG.Rdata"
LOCAL_DATA_PATH <- "/Users/conet/SGP Dropbox/Damian Betebenner/Massachusetts/Data/Massachusetts_Data_LONG.Rdata"
```

### New York Configuration
```r
STATE_NAME <- "New York"
STATE_ABBREV <- "NY"
RDATA_OBJECT_NAME <- "NewYork_Data_LONG"
EC2_DATA_PATH <- "/home/ec2-user/SGP/Dropbox/NewYork/Data/NewYork_Data_LONG.Rdata"
LOCAL_DATA_PATH <- "/Users/conet/SGP Dropbox/Damian Betebenner/NewYork/Data/NewYork_Data_LONG.Rdata"
```

## Migration Guide

If you have existing analyses that reference `Colorado_Data_LONG` directly:

1. **Update data access**: Replace `Colorado_Data_LONG` with `get_state_data()`
2. **Remove data loading**: Remove individual data loading code from step files
3. **Test configuration**: Verify your state configuration works
4. **Run analysis**: Use `source("master_analysis.R")` as usual

The generic data system maintains full backward compatibility while providing much greater flexibility for multi-state analyses.