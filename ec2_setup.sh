#!/bin/bash
# EC2 Setup Script for Copula Sensitivity Analysis
# Run on fresh c8g.12xlarge Amazon Linux 2023 instance

set -e  # Exit on error

echo "=========================================="
echo "EC2 Setup for Copula Analysis"
echo "Instance: c8g.12xlarge (Graviton4)"
echo "=========================================="
echo ""

# Update system
echo "Updating system packages..."
sudo yum update -y

# Install R and dependencies
echo "Installing R and system dependencies..."
sudo yum install -y R git libcurl-devel openssl-devel libxml2-devel htop

# Install R packages
echo "Installing R packages (this may take 5-10 minutes)..."
sudo R --vanilla <<EOF
install.packages(c(
  "data.table",
  "copula", 
  "splines2",
  "parallel"
), repos = "https://cloud.r-project.org/", Ncpus = 4)
quit(save = "no")
EOF

# Verify installation
echo ""
echo "Verifying R package installation..."
R --vanilla -e "library(data.table); library(copula); library(splines2); library(parallel); cat('All packages loaded successfully\n')"

# Create directory structure
echo ""
echo "Creating directory structure..."
mkdir -p ~/copula-analysis/{Data,STEP_1_Family_Selection/results,functions}

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Upload data files to ~/copula-analysis/Data/"
echo "   scp -i ~/.ssh/your-key.pem Data/Copula_Sensitivity_Data_Set_*.Rdata ec2-user@<EC2-IP>:~/copula-analysis/Data/"
echo ""
echo "2. Upload analysis scripts to ~/copula-analysis/"
echo "   scp -i ~/.ssh/your-key.pem -r /path/to/Copula_Sensitivity_Analyses/* ec2-user@<EC2-IP>:~/copula-analysis/"
echo ""
echo "3. Run analysis:"
echo "   cd ~/copula-analysis"
echo "   nohup Rscript -e 'source(\"run_test_multiple_datasets.R\")' > analysis_output.log 2>&1 &"
echo "   tail -f analysis_output.log"
echo ""

