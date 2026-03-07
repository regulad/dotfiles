#!/bin/bash -e

if [ -f /etc/redhat-release ]; then
	source /etc/os-release
	if [ "$ID" = "fedora" ]; then
		if [ "$VERSION_ID" -gt 41 ]; then
			# The wslutilities/wslu COPR was not maintained past Fedora 41, so on newer
			# Fedora releases the repo file's $releasever resolves to a non-existent path.
			# Write the repo file manually with the last working baseurl hardcoded to F41.
			sudo rm -f /etc/yum.repos.d/*wslu* /etc/yum.repos.d/*wslutilities*
			sudo tee /etc/yum.repos.d/wslutilities-wslu.repo >/dev/null <<EOF
[copr:copr.fedorainfracloud.org:wslutilities:wslu]
name=Copr repo for wslu owned by wslutilities
baseurl=https://download.copr.fedorainfracloud.org/results/wslutilities/wslu/fedora-41-$(uname -m)/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/wslutilities/wslu/pubkey.gpg
repo_gpgcheck=0
enabled=1
EOF
		else
			sudo dnf5 config-manager addrepo --from-repofile \
				"https://copr.fedorainfracloud.org/coprs/wslutilities/wslu/repo/fedora-41/wslutilities-wslu-fedora-41.repo" | cat
		fi
		sudo dnf5 install wslu -y | cat
	else
		# RHEL uses dnf4
		sudo dnf4 install -y epel-release dnf-plugins-core | cat
		if [ "$VERSION_ID" = "8" ]; then
			sudo dnf4 config-manager --set-enabled PowerTools | cat
		else
			sudo dnf4 config-manager --set-enabled crb | cat
		fi
		if [ "$VERSION_ID" -gt 10 ]; then
			# The wslutilities/wslu COPR was not maintained past RHEL 10, so on newer
			# RHEL releases the repo file's $releasever resolves to a non-existent path.
			# Write the repo file manually with the last working baseurl hardcoded to epel-10.
			sudo rm -f /etc/yum.repos.d/*wslu* /etc/yum.repos.d/*wslutilities*
			sudo tee /etc/yum.repos.d/wslutilities-wslu.repo >/dev/null <<EOF
[copr:copr.fedorainfracloud.org:wslutilities:wslu]
name=Copr repo for wslu owned by wslutilities
baseurl=https://download.copr.fedorainfracloud.org/results/wslutilities/wslu/epel-10-$(uname -m)/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/wslutilities/wslu/pubkey.gpg
repo_gpgcheck=0
enabled=1
EOF
		else
			sudo dnf4 copr enable wslutilities/wslu -y | cat
		fi
		sudo dnf4 install wslu -y | cat
	fi
else
	export DEBIAN_FRONTEND=noninteractive
	sudo apt update | cat
	sudo apt install wslu -y | cat
	sudo apt upgrade -y | cat
	sudo apt autoremove -y | cat
fi
