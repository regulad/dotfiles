#!/bin/bash -e

# libva needs to use the `drm` display to work under WSLg, but applications may not set it.
# for vainfo, can be forced with `vainfo --display drm`
#
# That drm display (/dev/dri/card0, renderD128) is the vgem module's, and not
# every WSL kernel ships it: the 6.18.40.1 kernel of WSL 3.0.1 has none
# ("modinfo: ERROR: Module vgem not found", and no /dev/dri at all). The unit
# below therefore has an ExecCondition, so systemd skips it on such a kernel
# rather than failing it on every boot, and the steps here that need the
# module or its device nodes are guarded the same way.
if /usr/sbin/modinfo -n vgem >/dev/null 2>&1; then
	HAS_VGEM=1
	sudo modprobe vgem
else
	HAS_VGEM=0
	echo "notice: this WSL kernel ($(uname -r)) has no vgem module; vgem.service will be skipped until one does" >&2
fi

sudo tee /etc/systemd/system/vgem.service >/dev/null <<'EOF'
[Unit]
Description=Load vgem for WSL GPU support
After=multi-user.target

[Service]
Type=oneshot
# Not every WSL kernel ships vgem (6.18.40.1 in WSL 3.0.1 does not). modinfo
# exits 1 when the module is absent, which makes systemd skip the unit
# instead of failing it.
ExecCondition=/usr/sbin/modinfo -n vgem
ExecStart=/usr/sbin/modprobe vgem
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable vgem.service

sudo touch /etc/environment

sudo sh -c '
grep -qxF "GALLIUM_DRIVER=d3d12" /etc/environment || echo "GALLIUM_DRIVER=d3d12" >> /etc/environment
grep -qxF "LIBVA_DRIVER_NAME=d3d12" /etc/environment || echo "LIBVA_DRIVER_NAME=d3d12" >> /etc/environment
'

# Align the render/video GIDs with vgem's device nodes; without the module
# there are no nodes to align with (an earlier run on a vgem kernel has
# already done it on existing distros).
if [ "$HAS_VGEM" -eq 1 ]; then
	sudo groupmod -g "$(stat -c '%g' /dev/dri/renderD128)" render
	sudo groupmod -g "$(stat -c '%g' /dev/dri/card0)" video
fi
for g in render video; do sudo usermod -aG "$g" "$USER"; done
echo "warning: re-login may be required" >&2
