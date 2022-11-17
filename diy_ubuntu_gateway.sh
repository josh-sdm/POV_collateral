#!/bin/bash
# This script should work for VM user data as well as running VMs where you wish to install a strongDM gateway
# Your VM should have a public IPv4 address and a firewall rule that allows 5000/tcp from 0.0.0.0/0
# Your VM should also have a friendly name that contains only digits, lowercase characters, and/or - (dash/tack)
#
# Create SDM_ADMIN_TOKEN in the strongDM Admin UI with the four scopes in the line below
# Relays: Create, Relays: List, Datasources & Servers: Create, and Control Panel: View Settings
#
# Please update the SDM_LISTEN_PORT variable below if you'd like the strongDM gateway to listen on a port other than the default 5000/tcp
# Please check/update the SSH_USERNAME variable below; the typical Ubuntu username (also a sudoer) is: ubuntu
export SDM_ADMIN_TOKEN=<YOUR_TOKEN_HERE>
export SDM_LISTEN_PORT=5000
export SSH_USERNAME=ubuntu

# Update the package repository; install jq and unzip
apt update
apt install jq unzip -y

# Configure inbound host firewall rules for ssh and strongDM gateway traffic
ufw allow ssh
ufw allow $SDM_LISTEN_PORT/tcp
ufw --force enable

# Create the strongdm user with a home directory and grant it sudo privileges
useradd -m strongdm
usermod -aG sudo strongdm

# Download the strongDM gateway binary and unzip it
curl -J -O -L https://app.strongdm.com/releases/cli/linux
unzip sdmcli* && rm -f sdmcli*

# Set additional variables
# INSTANCE_NAME variable may contain only digits, lowercase characters, and/or - (dash/tack) and requires that tags be enabled for IMDS
export INSTANCE_PUBLIC_IP=<YOUR_INSTANCE_PUBLIC_IP>
export INSTANCE_PRIVATE_IP=<YOUR_INSTANCE_PRIVATE_IP>
export INSTANCE_ID=<YOUR_INSTANCE_UNIQUE_ID>
export INSTANCE_FRIENDLY_NAME=<YOUR_INSTANCE_FRIENDLY_NAME>

# Use the sdm binary with SDM_ADMIN_TOKEN to create a ssh certificate authority resource for the gateway
./sdm admin servers create ssh-cert --hostname $INSTANCE_PRIVATE_IP --port 22 --username $SSH_USERNAME $INSTANCE_FRIENDLY_NAME-ssh --tags instance=$INSTANCE_ID

# Set SDM_RELAY_TOKEN token by using the sdm binary with SDM_ADMIN_TOKEN to add a new gateway
export SDM_RELAY_TOKEN=`./sdm admin relays create-gateway $INSTANCE_PUBLIC_IP:$SDM_LISTEN_PORT 0.0.0.0:$SDM_LISTEN_PORT --name $INSTANCE_FRIENDLY_NAME --tags instance=$INSTANCE_ID`
export SDM_CA_PUB=`./sdm admin ssh view-ca`
unset SDM_ADMIN_TOKEN
./sdm install --relay --user strongdm

# Add the public certificate from your strongDM tenant to the sshd config of the gateway
echo $SDM_CA_PUB | tee -a /etc/ssh/sdm_ca.pub
echo "TrustedUserCAKeys /etc/ssh/sdm_ca.pub" | tee -a /etc/ssh/sshd_config
systemctl restart ssh

# Configure sdm-proxy service to expose metrics on 127.0.0.1:9999 (the blank line is intentional)
tee -a /etc/sysconfig/sdm-proxy <<EOF > /dev/null 2>&1

SDM_METRICS_LISTEN_ADDRESS=127.0.0.1:9999
EOF
systemctl daemon-reload
systemctl restart sdm-proxy
