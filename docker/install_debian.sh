#!/bin/bash

# Remove some packages (if necesary) and install the necesary ones
apt-get remove docker docker-engine docker.io containerd runc -y
apt-get update
apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common -y

# Add docker gpg key
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -

# Add repository
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

# Install docker
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io -y

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

exit 0

