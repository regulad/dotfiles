#!/bin/bash -e

# libva needs to use the `drm` display to work under WSLg, but applications may not set it.
# for vainfo, can be forced with `vainfo --display drm`

sudo modprobe vgem

sudo tee /etc/systemd/system/vgem.service >/dev/null <<'EOF'
[Unit]
Description=Load vgem for WSL GPU support
After=multi-user.target

[Service]
Type=oneshot
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

sudo groupmod -g "$(stat -c '%g' /dev/dri/renderD128)" render
sudo groupmod -g "$(stat -c '%g' /dev/dri/card0)" video
for g in render video; do sudo usermod -aG "$g" "$USER"; done
echo "warning: re-login may be required" >&2
