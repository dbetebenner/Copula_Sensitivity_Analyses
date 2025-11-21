# Real-Time Progress Monitoring

The copula analysis now writes real-time progress to `.progress.txt` files as each condition completes.

## 📊 Quick Start

### Option 1: Use the Monitor Script (Recommended)

**Terminal 1**: Run analysis
```bash
cd /path/to/Copula_Sensitivity_Analyses
Rscript master_analysis.R
```

**Terminal 2**: Monitor progress
```bash
cd /path/to/Copula_Sensitivity_Analyses
./monitor_progress.sh
```

The monitor script provides:
- ✅ Color-coded output (STARTED=blue, COMPLETE=green, ERROR=red)
- 📊 Real-time statistics (started, completed, running, errors)
- 📈 Completion percentage
- 🔄 Auto-refresh every 5 seconds
- 🎯 Automatic detection of completion

### Option 2: Manual Monitoring

**Watch live updates:**
```bash
tail -f STEP_1_Family_Selection/results/dataset_1/.progress.txt
```

**Check current status:**
```bash
# Count completed conditions
grep -c "COMPLETE" STEP_1_Family_Selection/results/dataset_1/.progress.txt

# Show last 10 events
tail -10 STEP_1_Family_Selection/results/dataset_1/.progress.txt

# Find errors
grep "ERROR" STEP_1_Family_Selection/results/dataset_1/.progress.txt
```

**Periodic summary:**
```bash
watch -n 10 '
echo "=== $(date) ==="
echo ""
echo "Completed: $(grep -c COMPLETE STEP_1_Family_Selection/results/dataset_1/.progress.txt)"
echo "Running:   $(( $(grep -c STARTED STEP_1_Family_Selection/results/dataset_1/.progress.txt) - $(grep -c COMPLETE STEP_1_Family_Selection/results/dataset_1/.progress.txt) - $(grep -c ERROR STEP_1_Family_Selection/results/dataset_1/.progress.txt) ))"
echo ""
tail -5 STEP_1_Family_Selection/results/dataset_1/.progress.txt
'
```

## 📝 Progress File Format

Each line shows:
```
[HH:MM:SS] STATUS  ID/TOTAL: CONTENT GX->GY (YEAR->YEAR) [TIMING] [RESULT]
```

**Example output:**
```
======================================================================
COPULA FAMILY SELECTION: Progress Log
======================================================================
Started: 2025-11-06 15:30:00
Total conditions: 21
Copula families: gaussian, t, clayton, gumbel, frank, comonotonic
Workers: 6
======================================================================

[15:30:05] STARTED    1/21: MATH G4->G5 (2010->2011)
[15:30:05] STARTED    2/21: MATH G5->G6 (2010->2011)
[15:30:05] STARTED    3/21: MATH G6->G7 (2010->2011)
[15:30:05] STARTED    4/21: MATH G7->G8 (2010->2011)
[15:30:05] STARTED    5/21: MATH G4->G6 (2010->2012)
[15:30:05] STARTED    6/21: MATH G5->G7 (2010->2012)
[15:33:42] COMPLETE   1/21: MATH G4->G5 (3.6 min, n=2845, best=t)
[15:33:42] STARTED    7/21: ELA G4->G5 (2010->2011)
[15:36:18] COMPLETE   2/21: MATH G5->G6 (6.3 min, n=3127, best=t)
[15:36:18] STARTED    8/21: ELA G5->G6 (2010->2011)
...
======================================================================
ANALYSIS COMPLETE
======================================================================
Finished: 2025-11-06 16:45:23
Total time: 75.4 minutes
Average per condition: 3.6 minutes
Successful: 21 / 21
======================================================================
```

## 🖥️ EC2 Monitoring

### Via SSH

**Monitor in real-time:**
```bash
ssh ec2-user@<EC2-IP>
cd ~/copula_analysis
tail -f STEP_1_Family_Selection/results/dataset_1/.progress.txt
```

**Or use the monitor script:**
```bash
ssh ec2-user@<EC2-IP>
cd ~/copula_analysis
./monitor_progress.sh
```

### From Local Machine

**Periodically sync and check:**
```bash
# Download progress file every 30 seconds
watch -n 30 '
scp ec2-user@<EC2-IP>:~/copula_analysis/STEP_1_Family_Selection/results/dataset_1/.progress.txt /tmp/ec2_progress.txt
echo "=== EC2 Progress ($(date)) ==="
tail -10 /tmp/ec2_progress.txt
echo ""
echo "Completed: $(grep -c COMPLETE /tmp/ec2_progress.txt) conditions"
'
```

## 🔍 Interpreting Progress

### Timing Expectations

**Dataset 1 (21 conditions)**:
- **Local (12 cores)**: ~3-5 min per condition = 10-18 min total
- **EC2 (48 cores)**: ~2-3 min per condition = 7-11 min total

**Dataset 2 (21 conditions)**:
- Similar to Dataset 1

**Dataset 3 (87 conditions)**:
- **Local (12 cores)**: ~3-5 min per condition = 45-75 min total
- **EC2 (48 cores)**: ~2-3 min per condition = 30-45 min total

### Status Meanings

| Status | Meaning | Action |
|--------|---------|--------|
| **STARTED** | Condition is being processed | Normal - wait |
| **COMPLETE** | Condition finished successfully | Normal - progress! |
| **ERROR** | Condition failed | Check error message |

### What If Progress Stops?

**Symptoms:**
- No new COMPLETE messages for 10+ minutes
- Last STARTED was >10 min ago
- R process still running

**Possible causes:**
1. **Long-running condition** (large n, complex data) - Normal, wait
2. **Stuck worker** (rare) - Check `htop` for hung R process
3. **Memory pressure** - Check `free -h` and swap usage
4. **I/O bottleneck** - Check `iostat -x 5`

**Diagnosis:**
```bash
# How many R processes?
ps aux | grep "[R]" | wc -l
# Should match number of workers

# Which conditions are running?
tail -20 STEP_1_Family_Selection/results/dataset_1/.progress.txt | grep STARTED | grep -v COMPLETE
```

## 🎯 Multiple Datasets

When running `master_analysis.R` with multiple datasets, each gets its own progress file:

- `STEP_1_Family_Selection/results/dataset_1/.progress.txt`
- `STEP_1_Family_Selection/results/dataset_2/.progress.txt`
- `STEP_1_Family_Selection/results/dataset_3/.progress.txt`

**Monitor specific dataset:**
```bash
./monitor_progress.sh dataset_1
./monitor_progress.sh dataset_2
./monitor_progress.sh dataset_3
```

**Monitor all at once (split screen):**
```bash
# Terminal 1
tail -f STEP_1_Family_Selection/results/dataset_1/.progress.txt

# Terminal 2
tail -f STEP_1_Family_Selection/results/dataset_2/.progress.txt

# Terminal 3
tail -f STEP_1_Family_Selection/results/dataset_3/.progress.txt
```

## 🚀 Tips & Tricks

### Estimate Time Remaining

```bash
# Count total and completed
total=$(grep "Total conditions:" STEP_1_Family_Selection/results/dataset_1/.progress.txt | awk '{print $3}')
done=$(grep -c "COMPLETE" STEP_1_Family_Selection/results/dataset_1/.progress.txt)
remaining=$((total - done))

# Get average time per condition (from complete messages)
avg_time=$(grep "COMPLETE" STEP_1_Family_Selection/results/dataset_1/.progress.txt | \
           awk -F'[()]' '{print $2}' | \
           awk '{sum+=$1; count++} END {printf "%.1f", sum/count}')

# Estimate remaining time
echo "Remaining: $remaining conditions"
echo "Average time: $avg_time min/condition"
echo "Estimated time left: $(echo "$remaining * $avg_time" | bc) minutes"
```

### Alert When Complete

```bash
# Play sound when analysis finishes
while ! grep -q "ANALYSIS COMPLETE" STEP_1_Family_Selection/results/dataset_1/.progress.txt; do
  sleep 30
done
say "Analysis complete!"  # macOS
# Or: spd-say "Analysis complete!"  # Linux
```

### Log to File with Timestamps

```bash
tail -f STEP_1_Family_Selection/results/dataset_1/.progress.txt | \
  while IFS= read -r line; do
    echo "$(date +%H:%M:%S) $line" | tee -a my_progress_log.txt
  done
```

## 📱 Mobile Monitoring

Set up simple HTTP access (only on trusted networks!):

```bash
# On EC2/server (temporary, for monitoring only)
cd ~/copula_analysis/STEP_1_Family_Selection/results
python3 -m http.server 8888

# From phone/laptop browser
http://<EC2-IP>:8888/dataset_1/.progress.txt
```

**Security note**: Use SSH tunnel for production:
```bash
ssh -L 8888:localhost:8888 ec2-user@<EC2-IP>
# Then browse to http://localhost:8888/dataset_1/.progress.txt
```

