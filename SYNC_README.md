# EC2 Sync Tools

Quick reference for syncing files between your local machine and EC2 instance.

## Setup (One-Time)

1. **Edit the IP address** in `ec2_config.sh`:
   ```bash
   nano ec2_config.sh
   # Update EC2_IP="YOUR.NEW.IP.HERE"
   ```

2. **Make script executable** (already done):
   ```bash
   chmod +x sync_ec2.sh
   ```

## Common Usage

### Download Results from EC2

From the results directory:
```bash
cd STEP_1_Family_Selection/results
../../sync_ec2.sh
```

Or from project root:
```bash
./sync_ec2.sh -r Copula_Sensitivity_Analyses/STEP_1_Family_Selection/results/ -l STEP_1_Family_Selection/results/
```

### Dry Run First (See What Would Transfer)

```bash
./sync_ec2.sh -n
```

### Upload Code Changes to EC2

```bash
./sync_ec2.sh -d upload -r Copula_Sensitivity_Analyses/functions/ -l functions/
```

### Sync Entire Project

```bash
# Download everything
./sync_ec2.sh -r Copula_Sensitivity_Analyses/ -l .

# Upload (excluding large data files)
./sync_ec2.sh -d upload -r Copula_Sensitivity_Analyses/ -l .
```

## Options

```
-i IP_ADDRESS    EC2 IP address (or edit ec2_config.sh)
-d DIRECTION     "download" (default) or "upload"
-r REMOTE_PATH   Remote path on EC2
-l LOCAL_PATH    Local path (default: current directory)
-k KEY_PATH      SSH key path (default: ~/.ec2/SGP.pem)
-n               Dry run (show what would be transferred)
-h               Show help message
```

## When EC2 IP Changes

Just update one line in `ec2_config.sh`:
```bash
EC2_IP="NEW.IP.ADDRESS.HERE"
```

All sync commands will automatically use the new IP!

## Why rsync Instead of scp?

- ✅ **Skips unchanged files** (much faster)
- ✅ **Resumes interrupted transfers**
- ✅ **Compresses during transfer** (faster over network)
- ✅ **Shows detailed progress**
- ✅ **Verifies transfers**

## Examples

### From Results Directory
```bash
cd STEP_1_Family_Selection/results
../../sync_ec2.sh                    # Download results
../../sync_ec2.sh -n                 # Dry run first
```

### From Project Root
```bash
./sync_ec2.sh                        # Download results (default)
./sync_ec2.sh -d upload -r Copula_Sensitivity_Analyses/master_analysis.R -l master_analysis.R
```

### Specific Paths
```bash
# Download specific dataset
./sync_ec2.sh -r Copula_Sensitivity_Analyses/STEP_1_Family_Selection/results/dataset_1/ -l STEP_1_Family_Selection/results/dataset_1/

# Upload functions only
./sync_ec2.sh -d upload -r Copula_Sensitivity_Analyses/functions/ -l functions/
```

## Troubleshooting

**"rsync not found"**
- macOS: `brew install rsync`
- Linux: `sudo apt-get install rsync`

**"Permission denied (publickey)"**
- Check that `KEY_PATH` in `ec2_config.sh` points to your SSH key
- Verify key permissions: `chmod 400 ~/.ec2/SGP.pem`

**"Host key verification failed"**
- Run once manually: `ssh -i ~/.ec2/SGP.pem ec2-user@YOUR_IP`
- Accept the host key when prompted
