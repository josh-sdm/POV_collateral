#!/bin/bash
# This script should work for VM user data as well as running VMs where you wish to install a strongDM relay
# Your VM should have an egress route and firewall rules that allow it to reach your strongDM gateways 5000/tcp 
# Your VM should also have a friendly name that contains only digits, lowercase characters, and/or - (dash/tack)
#
# Create SDM_ADMIN_TOKEN in the strongDM Admin UI with the four scopes in the line below
# Relays: Create, Relays: List, Datasources & Servers: Create, and Control Panel: View Settings
#
# Please check/update the SSH_USERNAME variable below; the typical Ubuntu username (also a sudoer) is: ubuntu
export SDM_ADMIN_TOKEN=<YOUR_TOKEN_HERE>
export SSH_USERNAME=ubuntu

# Update the package repository; install jq and unzip
apt update
apt install jq unzip -y

# Create the strongdm user with a home directory and grant it sudo privileges
useradd -m strongdm
usermod -aG sudo strongdm

# Download the strongDM binary and unzip it
curl -J -O -L https://app.strongdm.com/releases/cli/linux
unzip sdmcli* && rm -f sdmcli*

# Set additional variables
# INSTANCE_NAME variable may contain only digits, lowercase characters, and/or - (dash/tack) and requires that tags be enabled for IMDS
export INSTANCE_PRIVATE_IP=<YOUR_INSTANCE_PRIVATE_IP>
export INSTANCE_ID=<YOUR_INSTANCE_UNIQUE_ID>
export INSTANCE_FRIENDLY_NAME=<YOUR_INSTANCE_FRIENDLY_NAME>

# Use the sdm binary with SDM_ADMIN_TOKEN to create a ssh certificate authority resource for the relay
./sdm admin servers create ssh-cert --hostname $INSTANCE_PRIVATE_IP --port 22 --username $SSH_USERNAME $INSTANCE_FRIENDLY_NAME-ssh --tags instance=$INSTANCE_ID

# Set SDM_RELAY_TOKEN token by using the sdm binary with SDM_ADMIN_TOKEN to add a new relay
export SDM_RELAY_TOKEN=`./sdm admin relays create --name $INSTANCE_FRIENDLY_NAME --tags instance=$INSTANCE_ID`
export SDM_CA_PUB=`./sdm admin ssh view-ca`
unset SDM_ADMIN_TOKEN
./sdm install --relay --user strongdm

# Add the public certificate from your strongDM tenant to the sshd config of the relay
echo $SDM_CA_PUB | tee -a /etc/ssh/sdm_ca.pub
echo "TrustedUserCAKeys /etc/ssh/sdm_ca.pub" | tee -a /etc/ssh/sshd_config
systemctl restart ssh

# Configure sdm-proxy service to expose metrics on 127.0.0.1:9999 (the blank line is intentional)
tee -a /etc/sysconfig/sdm-proxy <<EOF > /dev/null 2>&1

SDM_METRICS_LISTEN_ADDRESS=127.0.0.1:9999
EOF
systemctl daemon-reload
systemctl restart sdm-proxy
