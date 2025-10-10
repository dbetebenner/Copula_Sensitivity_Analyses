############################################################################
### STATE CONFIGURATION TEMPLATE
### 
### Copy this file to state_config.R and modify for your state
### Then source it before running master_analysis.R
############################################################################

# STATE CONFIGURATION - Modify these for your state
STATE_NAME <- "YourState"
STATE_ABBREV <- "XX"
WORKSPACE_OBJECT_NAME <- "STATE_DATA_LONG"  # Keep this generic - name in workspace
RDATA_OBJECT_NAME <- "YourState_SGP_LONG_Data"  # Name of data table object inside the .RData file

# Data paths (state-specific)
EC2_DATA_PATH <- "/path/to/your/state/data.Rdata"
LOCAL_DATA_PATH <- "/path/to/your/state/data.Rdata"

# Example configurations for different states:

# Colorado (default - trimmed dataset for copula sensitivity analysis)
# STATE_NAME <- "Colorado"
# STATE_ABBREV <- "CO"
# RDATA_OBJECT_NAME <- "Copula_Sensitivity_Test_Data_CO"
# EC2_DATA_PATH <- "Data/Copula_Sensitivity_Test_Data_CO.Rdata"
# LOCAL_DATA_PATH <- "Data/Copula_Sensitivity_Test_Data_CO.Rdata"
#
# Note: This uses a trimmed dataset (7 essential variables only) to reduce
# memory usage by ~75-80%. See Data/README.md for details.

# Massachusetts (example)
# STATE_NAME <- "Massachusetts"
# STATE_ABBREV <- "MA"
# RDATA_OBJECT_NAME <- "Massachusetts_SGP_LONG_Data"
# EC2_DATA_PATH <- "/home/ec2-user/SGP/Dropbox/Massachusetts/Data/Massachusetts_SGP_LONG_Data.Rdata"
# LOCAL_DATA_PATH <- "/Users/conet/SGP Dropbox/Damian Betebenner/Massachusetts/Data/Massachusetts_SGP_LONG_Data.Rdata"

# New York (example)
# STATE_NAME <- "New York"
# STATE_ABBREV <- "NY"
# RDATA_OBJECT_NAME <- "New_York_SGP_LONG_Data"
# EC2_DATA_PATH <- "/home/ec2-user/SGP/Dropbox/NewYork/Data/NewYork_SGP_LONG_Data.Rdata"
# LOCAL_DATA_PATH <- "/Users/conet/SGP Dropbox/Damian Betebenner/NewYork/Data/NewYork_SGP_LONG_Data.Rdata"

cat("State configuration loaded:\n")
cat("  State:", STATE_NAME, "(", STATE_ABBREV, ")\n")
cat("  .Rdata object name:", RDATA_OBJECT_NAME, "\n")
cat("  Workspace object name:", WORKSPACE_OBJECT_NAME, "\n")
cat("  Local path:", LOCAL_DATA_PATH, "\n")
cat("  EC2 path:", EC2_DATA_PATH, "\n\n")
