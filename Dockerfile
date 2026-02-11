# Dockerfile for sandbox environment with s6-overlay supervisor and dotfiles
#
# Author: Parker Wahle (regulad)
# Assisted by: Claude Sonnet 4.5
# License: AGPLv3.0 - see LICENSE.md
#
# Based on Debian Trixie (Debian 13)

FROM debian:trixie

# Build arguments
# dot linux suffix is lima-style (https://github.com/lima-vm/lima/discussions/2622#discussioncomment-108517600)
ARG USERNAME="regulad.linux"
ARG UID="1000"
ARG GROUPNAME="regulad.linux"
ARG GID="1000"

ARG S6_OVERLAY_VERSION=3.2.2.0

ENV TZ="America/New_York"
ENV DEBIAN_FRONTEND="noninteractive"

# overwrite the existing debian.sources with a version that includes non-free assets,
# which is important for the propriteary toolchains like nvcc
RUN cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
RUN chmod 644 /etc/apt/sources.list.d/debian.sources

# Create user with UID 1000 and add to sudoers
# sudo doesn't take filenames that have periods in them, so we have to change it to _
# -o flags enable non-unique UIDs, should they be needed
RUN groupadd -g ${GID} -o ${GROUPNAME} \
  && useradd --no-log-init -m -s /bin/bash -u ${UID} -o -g ${GROUPNAME} ${USERNAME} \
  && mkdir -p /etc/sudoers.d/ \
  && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$(echo ${USERNAME} | tr '.' '_') \
  && chmod 0440 /etc/sudoers.d/$(echo ${USERNAME} | tr '.' '_')

# Copy dotfiles repository to chezmoi source directory
COPY --chown=${USERNAME}:${USERNAME} . /home/${USERNAME}/.local/share/chezmoi/

## NOTE: since the docker buildx GHA action doesn't support squashing, all installs have to be done in a single layer.
##       who cares about caching!
# Install all development packages
## NOTE: for now, nvcc (provided by nvidia-cuda-toolkit) is installed in the container definitions rather than in the
##       bootstrap script. I may change this in the future.
# Install s6-overlay
# Install Homebrew as the UID 1000 user
# Install pnpm globally
# Install chezmoi via Homebrew
# Initialize and apply chezmoi (expects brew and pnpm to already exist)
# Clean up apt cache after chezmoi apply since it may install packages via sudo
RUN --mount=type=tmpfs,target=/tmp \
    apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    zsh \
    ca-certificates \
    curl \
    git \
    jq \
    python3 \
    ripgrep \
    wget \
    coreutils \
    grep \
    nodejs \
    npm \
    golang-go \
    rustc \
    cargo \
    unzip \
    pkg-config \
    libasound2-dev \
    build-essential \
    file \
    locales \
    procps \
    sudo \
    xz-utils \
    nvidia-cuda-toolkit \
  && localedef -i en_US -f UTF-8 en_US.UTF-8 \
  \
  && curl -fsSL https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz -o /tmp/s6-overlay-noarch.tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
  && curl -fsSL https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-$(uname -m).tar.xz -o /tmp/s6-overlay-$(uname -m).tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-$(uname -m).tar.xz \
  \
  && su -l ${USERNAME} -c 'NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
  && npm install -g pnpm \
  && su -l ${USERNAME} -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; brew install chezmoi' \
  && su -l ${USERNAME} -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; CHEZMOI_USE_DUMMY=1 chezmoi init; chezmoi apply --exclude encrypted' \
  \
  && apt-get clean \
  && rm -rf /home/${USERNAME}/.cache/* \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean

# Set s6-overlay as the init system
ENTRYPOINT ["/init"]

# To get a login shell, use one of:
#   docker exec -it <container> su - <username>
#   docker exec -it <container> su -l <username> /bin/bash
#   docker exec -it <container> su -l <username> /bin/zsh
