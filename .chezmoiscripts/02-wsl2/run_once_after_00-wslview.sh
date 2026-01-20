#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive

sudo apt update | cat
sudo apt install wslu -y | cat
sudo apt upgrade -y | cat
sudo apt autoremove -y | cat
