# EC2 Run Options Quick Reference

---

## 🎯 Which Script Should I Use?

### **Option 1: Testing & Development** ⚡ FAST
**Script:** `run_test_multiple_datasets.R`  
**Bootstrap:** N = 100  
**Runtime:** 1.5-2 hours  
**Cost:** $3-4  

**Use when:**
- Testing code changes
- Debugging issues
- Iterative development
- Initial analysis exploration

**Command:**
```bash
cd ~/copula-analysis
tmux new -s copula
Rscript -e 'source("run_test_multiple_datasets.R")'
```

---

### **Option 2: Production Quality** 📊 RECOMMENDED
**Script:** `run_production_ec2.R`  
**Bootstrap:** N = 1000  
**Runtime:** 8-10 hours  
**Cost:** $16-21  

**Use when:**
- Generating final paper results
- Preparing for peer review
- Need rigorous GoF p-values
- Publication submission

**Command:**
```bash
cd ~/copula-analysis
tmux new -s copula
Rscript -e 'source("run_production_ec2.R")'
```

---

### **Option 3: Maximum Precision** 🔬 OPTIONAL
**Script:** Modify `run_production_ec2.R`  
**Bootstrap:** N = 5000  
**Runtime:** 40-50 hours  
**Cost:** $80-100  

**Use when:**
- Reviewer requests more rigorous testing
- Sensitivity analysis of bootstrap precision
- Comparing different bootstrap sizes

**Modification:**
```r
# In run_production_ec2.R, change line 16:
N_BOOTSTRAP_GOF <- 5000  # Maximum precision
```

---

## 📊 Comparison Table

| Metric | Testing (N=100) | Production (N=1000) | Maximum (N=5000) |
|--------|----------------|---------------------|------------------|
| **Runtime** | 1.5-2 hrs | 8-10 hrs | 40-50 hrs |
| **Cost (on-demand)** | $3-4 | $16-21 | $80-100 |
| **Cost (spot)** | $1-2 | $7-9 | $35-40 |
| **p-value precision** | ±0.01 | ±0.001 | ±0.0002 |
| **Use case** | Development | Paper submission | Reviewer response |
| **Recommended for** | ✅ Initial runs | ✅ Final results | ⚠️ Special cases |

---

## 🚀 Recommended Workflow

### **Phase 1: Development** (N=100)
```bash
# Run quick test to verify everything works
Rscript -e 'source("run_test_multiple_datasets.R")'
```
**Time:** 1.5-2 hours  
**Verify:** All GoF columns populated, t-copula working

---

### **Phase 2: Production** (N=1000)
```bash
# Run overnight for final paper results
tmux new -s copula
Rscript -e 'source("run_production_ec2.R")'
# Ctrl+B then D to detach
```
**Time:** 8-10 hours (run overnight)  
**Result:** Publication-quality results

---

### **Phase 3: Analysis** (Local)
```bash
# Download results from EC2
scp -i ~/.ssh/your-key.pem -r \
  ec2-user@<EC2-IP>:~/copula-analysis/STEP_1_Family_Selection/results/ \
  ./

# Generate plots and summaries (run locally)
Rscript -e 'source("STEP_1_Family_Selection/phase1_analysis.R")'
```

---

## 💰 Cost Optimization Tips

### **Use Spot Instances**
- **Savings:** 58% cheaper ($0.86/hr vs $2.07/hr)
- **Risk:** Rarely interrupted for c8g instances
- **Recommendation:** Use for all runs unless on tight deadline

**Spot pricing:**
- Testing (N=100): ~$1-2 instead of $3-4
- Production (N=1000): ~$7-9 instead of $16-21

### **Time Your Runs**
Run overnight when you don't need immediate results:
- Start run at 8 PM
- Complete by 6 AM next morning
- Zero waiting time during work hours

### **Terminate When Done**
```bash
# Check if run is complete
tail ~/copula-analysis/STEP_1_Family_Selection/results/dataset_all/*.csv

# If complete, download results then terminate instance
# (from local machine)
scp -i ~/.ssh/your-key.pem -r \
  ec2-user@<EC2-IP>:~/copula-analysis/STEP_1_Family_Selection/results/ \
  ./results_$(date +%Y%m%d)/

# Then terminate instance in AWS Console
```

---

## 🔍 How to Monitor Progress

### **From SSH Session:**
```bash
# Attach to tmux session
tmux attach -t copula

# View progress in another window
tmux new-window
tail -f STEP_1_Family_Selection/results/dataset_1/*.csv

# Check CPU usage
htop
# Should show 46 cores at ~100%
```

### **From Local Machine:**
```bash
# SSH and check log
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2-IP>
tmux attach -t copula
```

---

## ✅ Verification After Run

### **Check 1: All Files Created**
```r
# In R on local machine after downloading
library(data.table)

# Load results
results <- fread("results/dataset_all/phase1_copula_family_comparison_all_datasets.csv")

# Check dimensions
nrow(results)  # Should be 774 (129 conditions × 6 families)
ncol(results)  # Should be 38 columns

# Check GoF columns exist and populated
summary(results$gof_pvalue)  # Should have numeric values, not all NA
table(results$gof_method)    # Should show bootstrap methods
```

### **Check 2: T-Copula GoF Working**
```r
# Verify t-copula tests ran successfully
t_results <- results[family == "t"]
nrow(t_results)  # Should be 129

# Check method
table(t_results$gof_method)
# Should show: bootstrap_gofTstat_N=100 or bootstrap_gofTstat_N=1000

# Check p-values
summary(t_results$gof_pvalue)
# Should have numeric values between 0 and 1
```

### **Check 3: Pass Rates**
```r
# Calculate pass rates
results[!is.na(gof_pvalue), .(
  n_tests = .N,
  n_pass = sum(gof_pass_0.05),
  pct_pass = 100 * mean(gof_pass_0.05),
  median_pvalue = median(gof_pvalue)
), by = family]
```

---

## 🎯 Quick Decision Guide

**Ask yourself:**

1. **Is this my first run?**  
   → Use `run_test_multiple_datasets.R` (N=100)

2. **Am I ready to submit the paper?**  
   → Use `run_production_ec2.R` (N=1000)

3. **Did a reviewer request more rigorous testing?**  
   → Modify for N=5000

4. **Am I on a tight budget?**  
   → Use spot instances for all runs

5. **Do I need results immediately?**  
   → Use on-demand instances + N=100

---

## 📋 Pre-Flight Checklist

Before starting any EC2 run:

- [ ] EC2 instance launched (c8g.12xlarge recommended)
- [ ] Data files uploaded to EC2
- [ ] Code files uploaded to EC2
- [ ] R packages installed (`data.table`, `copula`, `splines2`, `parallel`)
- [ ] tmux session created
- [ ] Spot instance alarm configured (if using spot)
- [ ] Local backup of previous results (if any)
- [ ] Billing alarm set in AWS Console

---

## 🆘 Troubleshooting

**Run taking longer than expected?**
- Check `htop` - should see 46 cores at ~100%
- Verify FORK cluster is being used (check startup output)
- Confirm N_BOOTSTRAP_GOF is set correctly

**Out of memory?**
- Shouldn't happen with 96 GB on c8g.12xlarge
- Check `free -h` to verify
- Reduce cores if needed (unlikely)

**Spot instance interrupted?**
- Results are saved per-dataset
- Re-run will skip completed datasets
- Consider switching to on-demand

---

## 📞 Quick Commands Reference

```bash
# Connect to EC2
ssh -i ~/.ssh/your-key.pem ec2-user@<EC2-IP>

# Start testing run
cd ~/copula-analysis
tmux new -s copula
Rscript -e 'source("run_test_multiple_datasets.R")'

# Start production run
cd ~/copula-analysis
tmux new -s copula
Rscript -e 'source("run_production_ec2.R")'

# Detach from tmux
Ctrl+B then D

# Reattach to tmux
tmux attach -t copula

# Monitor CPU
htop

# Download results
scp -i ~/.ssh/your-key.pem -r \
  ec2-user@<EC2-IP>:~/copula-analysis/STEP_1_Family_Selection/results/ \
  ./results_$(date +%Y%m%d)/
```

---

**Bottom Line:** Start with `run_test_multiple_datasets.R` to verify everything works, then use `run_production_ec2.R` for your final paper results. Total cost: $3-4 + $16-21 = **~$20-25 for complete analysis from start to finish.**

