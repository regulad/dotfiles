#!/bin/bash -e

# libva needs to use the `drm` display to work under WSLg, but applications may not set it.
# for vainfo, can be forced with `vainfo --display drm`

sudo modprobe vgem

sudo touch /etc/environment

sudo sh -c '
grep -qxF "GALLIUM_DRIVER=d3d12" /etc/environment || echo "GALLIUM_DRIVER=d3d12" >> /etc/environment
grep -qxF "LIBVA_DRIVER_NAME=d3d12" /etc/environment || echo "LIBVA_DRIVER_NAME=d3d12" >> /etc/environment
'

sudo touch /etc/rc.local
sudo chmod u+x /etc/rc.local

sudo sh -c '
grep -qxF "modprobe vgem" /etc/rc.local || echo "modprobe vgem" >> /etc/rc.local
'

sudo groupmod -g "$(stat -c '%g' /dev/dri/renderD128)" render
sudo groupmod -g "$(stat -c '%g' /dev/dri/card0)" video
for g in render video; do id -nG "$USER" | tr ' ' '\n' | grep -qx "$g" || sudo usermod -aG "$g" "$USER" && echo "warning: re-login required" >&2; done
