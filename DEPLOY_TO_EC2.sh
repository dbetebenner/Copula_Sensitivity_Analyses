#!/bin/bash
################################################################################
# EC2 Deployment Script for T-Copula GoF Fix
################################################################################

# USAGE:
#   1. Set your EC2 details below
#   2. Run: bash DEPLOY_TO_EC2.sh
#   3. Follow the verification steps

# ============================================================================
# CONFIGURATION - UPDATE THESE VALUES
# ============================================================================

EC2_IP="YOUR_EC2_IP_HERE"  # e.g., "54.123.45.67"
SSH_KEY="~/.ssh/your-key.pem"  # Path to your SSH key
EC2_USER="ec2-user"
EC2_DIR="~/copula-analysis"

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

echo "======================================================================"
echo "EC2 DEPLOYMENT: T-Copula GoF Fix"
echo "======================================================================"
echo ""

if [ "$EC2_IP" = "YOUR_EC2_IP_HERE" ]; then
    echo "❌ ERROR: Please set EC2_IP in this script first!"
    echo "   Edit DEPLOY_TO_EC2.sh and set your EC2 instance IP address."
    exit 1
fi

if [ ! -f "${SSH_KEY/#\~/$HOME}" ]; then
    echo "❌ ERROR: SSH key not found at $SSH_KEY"
    echo "   Update SSH_KEY path in this script."
    exit 1
fi

echo "Configuration:"
echo "  EC2 IP: $EC2_IP"
echo "  SSH Key: $SSH_KEY"
echo "  Remote dir: $EC2_DIR"
echo ""

# ============================================================================
# FILE UPLOADS
# ============================================================================

echo "======================================================================"
echo "UPLOADING UPDATED FILES"
echo "======================================================================"
echo ""

FILES_TO_UPLOAD=(
    "functions/copula_bootstrap.R"
    "master_analysis.R"
    "run_test_ultrafast.R"
    "run_production_ec2.R"
    "GOF_FIX_COMPLETE.md"
    "T_COPULA_GOF_FIX_FINAL.md"
)

for file in "${FILES_TO_UPLOAD[@]}"; do
    if [ -f "$file" ]; then
        echo "Uploading: $file"
        scp -i "$SSH_KEY" "$file" "$EC2_USER@$EC2_IP:$EC2_DIR/$file" || {
            echo "❌ Failed to upload $file"
            exit 1
        }
        echo "✓ Uploaded: $file"
        echo ""
    else
        echo "⚠️  File not found (skipping): $file"
        echo ""
    fi
done

echo "======================================================================"
echo "VERIFYING DEPLOYMENT"
echo "======================================================================"
echo ""

# Run verification script on EC2
ssh -i "$SSH_KEY" "$EC2_USER@$EC2_IP" << 'ENDSSH'
    cd ~/copula-analysis
    
    echo "Checking files:"
    echo ""
    
    # Check copula_bootstrap.R has the new code
    if grep -q "bootstrap_empirical_tcopula" functions/copula_bootstrap.R; then
        echo "✓ copula_bootstrap.R: T-copula fix detected"
    else
        echo "❌ copula_bootstrap.R: Fix NOT found!"
        exit 1
    fi
    
    if grep -q "O(n log n)" functions/copula_bootstrap.R; then
        echo "✓ copula_bootstrap.R: Optimization comment present"
    else
        echo "⚠️  copula_bootstrap.R: Optimization may be old version"
    fi
    
    # Check master_analysis.R has NA fallback
    if grep -q "is.na(n_cores_available)" master_analysis.R; then
        echo "✓ master_analysis.R: NA fallback present"
    else
        echo "⚠️  master_analysis.R: Missing NA fallback"
    fi
    
    echo ""
    echo "File timestamps:"
    ls -lh functions/copula_bootstrap.R master_analysis.R run_production_ec2.R
    
    echo ""
    echo "======================================================================"
    echo "DEPLOYMENT VERIFICATION COMPLETE"
    echo "======================================================================"
    
ENDSSH

if [ $? -eq 0 ]; then
    echo ""
    echo "======================================================================"
    echo "✅ DEPLOYMENT SUCCESSFUL"
    echo "======================================================================"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Test on EC2 with ultra-fast script (N=10, ~90 min):"
    echo "   ssh -i $SSH_KEY $EC2_USER@$EC2_IP"
    echo "   cd $EC2_DIR"
    echo "   nohup Rscript run_test_ultrafast.R > ultrafast_test.log 2>&1 &"
    echo "   tail -f ultrafast_test.log"
    echo ""
    echo "2. If test passes, run production (N=1000, ~6-8 hours):"
    echo "   nohup Rscript run_production_ec2.R > production_run.log 2>&1 &"
    echo "   tail -f production_run.log"
    echo ""
    echo "3. Download results when complete:"
    echo "   scp -i $SSH_KEY -r $EC2_USER@$EC2_IP:$EC2_DIR/STEP_1_Family_Selection/results/ ."
    echo ""
else
    echo ""
    echo "======================================================================"
    echo "❌ DEPLOYMENT VERIFICATION FAILED"
    echo "======================================================================"
    echo ""
    echo "Please check the error messages above and try again."
    exit 1
fi

