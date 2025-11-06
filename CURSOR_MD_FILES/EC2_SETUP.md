# EC2 Setup Guide for Copula Sensitivity Analysis

---

## Quick Start: Get Running in 15 Minutes

### 1. Launch Instance (5 min)
```
Instance Type: c8g.12xlarge
AMI: Amazon Linux 2023 ARM64
Storage: 100 GB gp3
Security: SSH (port 22) from your IP
```

### 2. Automated Setup (5 min)
```bash
# Upload and run setup script
scp -i ~/.ssh/your-key.pem ec2_setup.sh ec2-user@<EC2-IP>:~/
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2-IP>
chmod +x ec2_setup.sh
./ec2_setup.sh
```

### 3. Upload Data & Code (5 min)
```bash
# From your local machine
scp -i ~/.ssh/your-key.pem Data/Copula_Sensitivity_Data_Set_*.Rdata ec2-user@<EC2-IP>:~/copula-analysis/Data/
scp -i ~/.ssh/your-key.pem -r /path/to/Copula_Sensitivity_Analyses/* ec2-user@<EC2-IP>:~/copula-analysis/
```

### 4. Run Analysis
```bash
# Recommended: Use tmux for long sessions
tmux new -s copula
cd ~/copula-analysis
Rscript -e 'source("run_test_multiple_datasets.R")'
# Press Ctrl+B then D to detach
# Reattach later: tmux attach -t copula

# Alternative: Use nohup
cd ~/copula-analysis
nohup Rscript -e 'source("run_test_multiple_datasets.R")' > analysis.log 2>&1 &
tail -f analysis.log
```

### 5. Download Results
```bash
# From your local machine
scp -i ~/.ssh/your-key.pem -r ec2-user@<EC2-IP>:~/copula-analysis/STEP_1_Family_Selection/results/ ./
```

---

## What You Should See

### Initialization (first 30 seconds)
```
DETECTED EC2 ENVIRONMENT
Instance type: c8g.12xlarge
Using EC2-optimized settings

Initializing FORK cluster (Unix shared memory)...
  Type: FORK (copy-on-write, no data export needed)
Available cores: 48
Using cores: 46

Goodness-of-Fit Testing: ENABLED (N = 1000 bootstrap samples)
```

✅ **If you see this, everything is working correctly!**

---

## Performance Expectations

### Runtime (N=1000 bootstraps)

| Dataset | Conditions | Time | Cost |
|---------|-----------|------|------|
| Dataset 1 | 28 | ~15-20 min | $0.50-0.70 |
| Dataset 2 | ~21 | ~12-15 min | $0.40-0.50 |
| Dataset 3 | 80 | ~45-60 min | $1.50-2.00 |
| **Total** | **129** | **1.5-2 hours** | **$3-4** |

### vs. Local Performance
- **M2 MacBook (11 cores):** 15-20 hours
- **EC2 c8g.12xlarge (46 cores):** 1.5-2 hours
- **Speedup:** ~10× faster on EC2

---

## Detailed Configuration

### Instance Specifications

**Recommended: c8g.12xlarge**
- **Processor:** AWS Graviton4 (ARM-based, 48 vCPUs)
- **Memory:** 96 GB
- **Network:** Up to 30 Gbps
- **Storage:** 100 GB gp3 (500 IOPS, 125 MB/s)
- **Cost:** $2.07/hour on-demand, ~$0.86/hour spot (58% savings)

### Launch Configuration

#### 1. AMI Selection
- **Recommended:** Amazon Linux 2023 ARM64
- **Alternative:** Ubuntu 22.04 ARM64

#### 2. Instance Settings
- Instance type: **c8g.12xlarge**
- Storage: **100 GB gp3** (500 IOPS, 125 MB/s)
- Security group: **SSH (port 22) from your IP only**
- Key pair: Use existing or create new

#### 3. Spot Instance (Optional, Recommended)
- Enable spot in launch wizard
- Set max price: $2.07/hour
- Risk: Rarely interrupted for c8g instances
- **Savings: 58% vs on-demand**

---

## Manual Software Installation

If you prefer not to use the automated setup script:

### Update System
```bash
sudo yum update -y  # Amazon Linux
# OR
sudo apt update && sudo apt upgrade -y  # Ubuntu
```

### Install R (Version 4.3+)
```bash
# Amazon Linux 2023
sudo yum install -y R

# Ubuntu
sudo apt install -y r-base r-base-dev
```

### Install System Dependencies
```bash
# Amazon Linux
sudo yum install -y git libcurl-devel openssl-devel libxml2-devel htop

# Ubuntu  
sudo apt install -y git libcurl4-openssl-dev libssl-dev libxml2-dev htop
```

### Install R Packages
```bash
# Launch R as sudo
sudo R

# Install required packages (will take ~5-10 minutes)
install.packages(c(
  "data.table",
  "copula",
  "splines2",
  "parallel"
), repos = "https://cloud.r-project.org/", Ncpus = 4)

quit(save = "no")
```

### Verify Installation
```bash
R -e "library(data.table); library(copula); library(splines2); library(parallel)"
```

---

## Monitoring & Management

### Monitor Resources
```bash
# CPU and memory usage
htop

# Check running R processes
ps aux | grep R

# Check disk usage
df -h

# Monitor analysis log in real-time
tail -f analysis.log
```

### Connect to Running Session
```bash
# If using tmux
tmux attach -t copula

# If using nohup
tail -f analysis.log
```

---

## Best Practices

### 1. Use tmux for Long Sessions
```bash
tmux new -s copula
# Run analysis
# Detach: Ctrl+B then D
# Reattach: tmux attach -t copula
# Kill session: tmux kill-session -t copula
```

**Why tmux?**
- Survives SSH disconnections
- Can check progress anytime
- No need for nohup/background jobs

### 2. Save Intermediate Results
- Code automatically saves per-dataset CSVs
- Safe to stop after each dataset completes
- Results in `STEP_1_Family_Selection/results/dataset_*/`

### 3. Monitor Costs
- Set billing alarm in AWS Console
- Budget: $50-100/month for regular use
- Test runs (N=100): ~$0.30-0.50
- Production (N=1000): ~$3-4

### 4. Instance Termination
```bash
# Stop instance (can restart later, keeps data)
# Do this from AWS Console

# Terminate instance (deletes everything)
# Download results first!
```

---

## Performance Details

### FORK vs PSOCK Cluster

| Metric | FORK (Unix/Linux/macOS) | PSOCK (Windows) |
|--------|------------------------|-----------------|
| Cluster init | ~2-5 seconds | ~5-10 seconds |
| Memory/worker | ~400 MB (copy-on-write) | ~600 MB (full copies) |
| Data export | None needed | ~2-3 seconds |
| **Overall speed** | **Baseline** | **~15% slower** |

**Your setup uses FORK** - fastest option for Unix systems.

### Resource Utilization
- **Memory:** ~20-25 GB of 96 GB (21-26%)
- **CPU:** 46 cores at ~95-100% utilization
- **Disk:** <10 GB for data + results
- **Network:** Minimal (only for data transfer)

---

## Cost Optimization

### Instance Type Comparison

| Instance | vCPUs | RAM | Runtime (N=1000) | Cost/Run | Notes |
|----------|-------|-----|------------------|----------|-------|
| c8g.8xlarge | 32 | 64 GB | ~2-2.5 hours | $2.50-3.50 | Budget option |
| **c8g.12xlarge** | **48** | **96 GB** | **~1.5-2 hours** | **$3-4** | **⭐ Recommended** |
| c8g.24xlarge | 96 | 192 GB | ~1 hour | $4-5 | Diminishing returns |

### Pricing Options

**On-Demand (Guaranteed):**
- c8g.12xlarge: $2.07/hour
- Always available
- No interruption risk

**Spot (58% cheaper):**
- c8g.12xlarge: ~$0.86/hour
- Set max price: $2.07/hour
- Rarely interrupted (c8g very stable)
- **Recommended for production**

### Monthly Budget Estimates
- **Light usage** (2-3 runs/month): ~$10-15
- **Regular usage** (8-10 runs/month): ~$30-50
- **Heavy usage** (20+ runs/month): ~$60-100

---

## Troubleshooting

### Connection Issues
**Symptom:** Can't SSH to instance

**Solutions:**
- Check security group allows SSH (port 22) from your IP
- Verify key permissions: `chmod 400 ~/.ssh/your-key.pem`
- Check instance is running in AWS Console
- Verify you're using correct public IP

### R Package Installation Fails
**Symptom:** `ec2_setup.sh` fails during R package install

**Solutions:**
```bash
# Install devtools first
sudo R -e "install.packages('devtools')"

# Retry individual packages
sudo R -e "install.packages('copula', repos='https://cloud.r-project.org/')"
```

### Out of Memory
**Symptom:** R crashes or system freezes

**Solutions:**
- Should NOT happen with 96 GB RAM
- Check memory usage: `free -h`
- If needed, reduce cores:
  - Edit `phase1_family_selection_parallel.R` line 34
  - Change to: `n_cores_use <- 30` (instead of 46)

### Slow Progress
**Symptom:** Analysis seems stuck

**Solutions:**
- Check this is **normal** - each condition takes time with bootstraps
- Monitor CPU: `htop` (should see 46 cores at ~100%)
- Check log: `tail -f analysis.log`
- Expected: ~1 condition per minute per core

### FORK Not Working
**Symptom:** Output shows "PSOCK" instead of "FORK"

**Solutions:**
- FORK only works on Unix (should work on Amazon Linux)
- Check: `uname -s` (should show "Linux")
- If still PSOCK, performance is fine, just 10-15% slower

### Spot Instance Interrupted
**Symptom:** Analysis stops mid-run

**Solutions:**
- Very rare for c8g instances
- Code saves per-dataset results automatically
- Re-run will skip completed datasets
- Consider on-demand if reliability critical

### Network Slow for Data Transfer
**Symptom:** Upload/download takes forever

**Solutions:**
- Use same AWS region as data source
- Consider uploading large data to S3 first
- Use `rsync` instead of `scp` for partial transfers:
  ```bash
  rsync -avz -e "ssh -i ~/.ssh/your-key.pem" \
    Data/ ec2-user@<EC2-IP>:~/copula-analysis/Data/
  ```

---

## Advanced Tips

### Running Multiple Analyses
```bash
# Run different configurations in separate tmux sessions
tmux new -s copula_test   # N=100 bootstraps
tmux new -s copula_prod   # N=1000 bootstraps

# Switch between sessions
tmux ls                    # List sessions
tmux attach -t copula_test # Attach to specific session
```

### Customizing Bootstrap Count
```r
# In run_test_multiple_datasets.R
N_BOOTSTRAP_GOF <- 100   # Testing
N_BOOTSTRAP_GOF <- 1000  # Production
N_BOOTSTRAP_GOF <- 5000  # Publication quality
```

### S3 Integration (Optional)
```bash
# Upload results to S3 automatically
aws s3 sync STEP_1_Family_Selection/results/ \
  s3://your-bucket/copula-results/ \
  --exclude "*.RData"
```

### Automatic Shutdown on Completion
```bash
# Add to end of analysis script
sudo shutdown -h now
```

---

## Summary Checklist

### Before Starting
- [ ] EC2 instance launched (c8g.12xlarge, Amazon Linux 2023 ARM64)
- [ ] Security group configured (SSH from your IP)
- [ ] Key pair downloaded and permissions set (`chmod 400`)

### Setup
- [ ] `ec2_setup.sh` uploaded and executed successfully
- [ ] Data files uploaded to `~/copula-analysis/Data/`
- [ ] Code uploaded to `~/copula-analysis/`
- [ ] R packages verified: `data.table`, `copula`, `splines2`, `parallel`

### Running
- [ ] Analysis running in tmux or nohup
- [ ] Can see "FORK cluster" in output
- [ ] GoF testing enabled (N=1000)
- [ ] CPU usage ~100% across 46 cores

### Completion
- [ ] All 3 datasets completed successfully
- [ ] Results downloaded from EC2
- [ ] GoF columns populated in CSVs
- [ ] Runtime ~1.5-2 hours
- [ ] Cost ~$3-4
- [ ] Instance stopped or terminated

---

## Support & Documentation

**Key Files:**
- `ec2_setup.sh` - Automated setup script
- `run_test_multiple_datasets.R` - Main execution script
- `CURSOR_MD_FILES/EC2_FORK_OPTIMIZATION_COMPLETE.md` - Technical implementation details

**Common Commands Quick Reference:**
```bash
# Connect
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2-IP>

# Upload
scp -i ~/.ssh/your-key.pem -r local-dir/ ec2-user@<EC2-IP>:~/remote-dir/

# Download
scp -i ~/.ssh/your-key.pem -r ec2-user@<EC2-IP>:~/remote-dir/ ./local-dir/

# Monitor
htop                    # CPU/memory
tail -f analysis.log    # Progress
tmux attach -t copula   # Re-attach session
```

---

**Last Updated:** October 29, 2025  
**Optimized for:** c8g.12xlarge (AWS Graviton4)  
**Framework Version:** FORK-optimized parallel processing
