############################################################################
### STATE CONFIGURATION TEMPLATE
### 
### Copy this file to state_config.R and modify for your state
### Then source it before running master_analysis.R
############################################################################

# STATE CONFIGURATION - Modify these for your state
STATE_NAME <- "YourState"
STATE_ABBREV <- "XX"
DATA_OBJECT_NAME <- "STATE_DATA_LONG"  # Keep this generic
DATA_VARIABLE_NAME <- "YourState_SGP_LONG_Data"  # Variable name inside the .RData file

# Data paths (state-specific)
EC2_DATA_PATH <- "/path/to/your/state/data.Rdata"
LOCAL_DATA_PATH <- "/path/to/your/state/data.Rdata"

# Example configurations for different states:

# Colorado (current)
# STATE_NAME <- "Colorado"
# STATE_ABBREV <- "CO"
# DATA_VARIABLE_NAME <- "Colorado_SGP_LONG_Data"
# EC2_DATA_PATH <- "/home/ec2-user/SGP/Dropbox/Colorado/Data/Archive/February_2016/Colorado_SGP_LONG_Data.Rdata"
# LOCAL_DATA_PATH <- "/Users/conet/SGP Dropbox/Damian Betebenner/Colorado/Data/Archive/February_2016/Colorado_SGP_LONG_Data.Rdata"

# Massachusetts (example)
# STATE_NAME <- "Massachusetts"
# STATE_ABBREV <- "MA"
# DATA_VARIABLE_NAME <- "Massachusetts_SGP_LONG_Data"
# EC2_DATA_PATH <- "/home/ec2-user/SGP/Dropbox/Massachusetts/Data/Massachusetts_SGP_LONG_Data.Rdata"
# LOCAL_DATA_PATH <- "/Users/conet/SGP Dropbox/Damian Betebenner/Massachusetts/Data/Massachusetts_SGP_LONG_Data.Rdata"

# New York (example)
# STATE_NAME <- "New York"
# STATE_ABBREV <- "NY"
# DATA_VARIABLE_NAME <- "New_York_SGP_LONG_Data"
# EC2_DATA_PATH <- "/home/ec2-user/SGP/Dropbox/NewYork/Data/NewYork_SGP_LONG_Data.Rdata"
# LOCAL_DATA_PATH <- "/Users/conet/SGP Dropbox/Damian Betebenner/NewYork/Data/NewYork_SGP_LONG_Data.Rdata"

cat("State configuration loaded:\n")
cat("  State:", STATE_NAME, "(", STATE_ABBREV, ")\n")
cat("  Data variable:", DATA_VARIABLE_NAME, "\n")
cat("  Local path:", LOCAL_DATA_PATH, "\n")
cat("  EC2 path:", EC2_DATA_PATH, "\n\n")
