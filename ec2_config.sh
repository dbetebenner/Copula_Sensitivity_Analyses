#!/bin/bash

################################################################################
# EC2 Configuration
# Update EC2_IP whenever you spin up a new instance
################################################################################

# Current EC2 instance IP address
EC2_IP="EC2_IP=54.235.242.211"

# SSH key location (default: ~/.ec2/SGP.pem)
KEY_PATH="$HOME/.ec2/SGP.pem"

# EC2 user (typically ec2-user for Amazon Linux)
EC2_USER="ec2-user"

# Base path on EC2 instance
EC2_BASE_PATH="/home/ec2-user/Copula_Sensitivity_Analyses"
