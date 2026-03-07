#!/bin/bash -e

if [ -f /etc/redhat-release ]; then
	source /etc/os-release
	if [ "$ID" = "fedora" ]; then
		# Fedora 41+ uses dnf5
		sudo dnf5 config-manager addrepo --from-repofile \
			"https://copr.fedorainfracloud.org/coprs/wslutilities/wslu/repo/fedora-41/wslutilities-wslu-fedora-41.repo" | cat
	else
		# RHEL uses dnf4
		sudo dnf4 install -y epel-release dnf-plugins-core | cat
		if [ "$VERSION_ID" = "8" ]; then
			sudo dnf4 config-manager --set-enabled PowerTools | cat
		else
			sudo dnf4 config-manager --set-enabled crb | cat
		fi
		sudo dnf4 copr enable wslutilities/wslu -y | cat
	fi
	sudo dnf install wslu -y | cat
else
	export DEBIAN_FRONTEND=noninteractive
	sudo apt update | cat
	sudo apt install wslu -y | cat
	sudo apt upgrade -y | cat
	sudo apt autoremove -y | cat
fi
