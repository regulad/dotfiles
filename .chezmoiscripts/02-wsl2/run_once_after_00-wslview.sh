#!/bin/bash -e

if [ -f /etc/redhat-release ]; then
	source /etc/os-release
	if [ "$ID" = "fedora" ]; then
		# dnf5 - use direct repo URL, bypasses copr subcommand entirely
		sudo dnf config-manager --add-repo \
			"https://download.copr.fedorainfracloud.org/results/wslutilities/wslu/fedora-41-$(uname -m)/" | cat
	else
		# dnf4 (RHEL < 11)
		sudo dnf install -y epel-release dnf-plugins-core | cat
		if [ "$VERSION_ID" = "8" ]; then
			sudo dnf config-manager --set-enabled PowerTools | cat
		else
			sudo dnf config-manager --set-enabled crb | cat
		fi
		sudo dnf copr enable wslutilities/wslu -y | cat
	fi
	sudo dnf install wslu -y | cat
else
	export DEBIAN_FRONTEND=noninteractive
	sudo apt update | cat
	sudo apt install wslu -y | cat
	sudo apt upgrade -y | cat
	sudo apt autoremove -y | cat
fi
