#!/bin/bash
###############################################################################
# EC2 Instance Setup for Copula_Sensitivity_Analyses
# 
# Usage on fresh Ubuntu EC2 instance:
#   wget https://raw.githubusercontent.com/YOUR_USERNAME/Copula_Sensitivity_Analyses/main/setup_ec2.sh
#   chmod +x setup_ec2.sh
#   ./setup_ec2.sh
###############################################################################

set -e

echo "======================================================================"
echo "COPULA SENSITIVITY ANALYSES - EC2 SETUP"
echo "======================================================================"

# Update system
echo "Updating system packages..."
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

# Install R
echo "Installing R..."
sudo apt-get install -y r-base r-base-dev

# Install system dependencies
echo "Installing system dependencies..."
sudo apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev

# Install R packages
echo "Installing R packages (10-15 minutes)..."
sudo Rscript -e "install.packages(c('data.table', 'copula', 'splines2', 'grid'), repos='https://cloud.r-project.org')"

# Create data directory
mkdir -p ~/data

echo ""
echo "======================================================================"
echo "SETUP COMPLETE"
echo "======================================================================"
echo ""
echo "Next steps:"
echo "  1. Upload data:"
echo "     scp Colorado_Data_LONG.RData ubuntu@YOUR-IP:~/data/"
echo ""
echo "  2. Clone repository:"
echo "     git clone https://github.com/YOUR_USERNAME/Copula_Sensitivity_Analyses.git"
echo ""
echo "  3. Run analysis:"
echo "     cd Copula_Sensitivity_Analyses"
echo "     nohup Rscript -e \"source('master_analysis.R')\" > output.log 2>&1 &"
echo ""
echo "  4. Monitor:"
echo "     tail -f Copula_Sensitivity_Analyses/output.log"
echo ""
echo "======================================================================"
