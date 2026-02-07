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
# always user 1000 by convention
ARG USERNAME="regulad.linux"
ARG S6_OVERLAY_VERSION=3.2.0.3

ENV DEBIAN_FRONTEND=noninteractive
ENV CHEZMOI_USE_DUMMY=1

# Homebrew configuration
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# Install all development packages
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
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean \
  && localedef -i en_US -f UTF-8 en_US.UTF-8

# Install s6-overlay
RUN --mount=type=tmpfs,target=/tmp \
    curl -fsSL https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz -o /tmp/s6-overlay-noarch.tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
  && curl -fsSL https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz -o /tmp/s6-overlay-x86_64.tar.xz \
  && tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz

# Create user with UID 1000 and add to sudoers
RUN useradd -m -s /bin/bash -u 1000 ${USERNAME} \
  && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
  && chmod 0440 /etc/sudoers.d/${USERNAME}

# Install Homebrew as the UID 1000 user
RUN --mount=type=tmpfs,target=/tmp \
    su -l ${USERNAME} -c 'NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' \
  && rm -rf /home/${USERNAME}/.cache/*

# Install pnpm globally
RUN --mount=type=tmpfs,target=/tmp \
    npm install -g pnpm

# Install chezmoi via Homebrew
RUN su -l ${USERNAME} -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; brew install chezmoi' \
  && rm -rf /home/${USERNAME}/.cache/*

# Copy dotfiles repository to chezmoi source directory
COPY --chown=${USERNAME}:${USERNAME} . /home/${USERNAME}/.local/share/chezmoi/

# Initialize and apply chezmoi (expects brew and pnpm to already exist)
# Clean up apt cache after chezmoi apply since it may install packages via sudo
# note: su -l drops all env (even with -m!) so we have to redeclare CHEMZOI_USE_DUMMY again just for this line
RUN su -l ${USERNAME} -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"; CHEZMOI_USE_DUMMY=1 chezmoi init; chezmoi apply --exclude encrypted' \
  && rm -rf /home/${USERNAME}/.cache/* \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean

# Set s6-overlay as the init system
ENTRYPOINT ["/init"]

# To get a login shell, use one of:
#   docker exec -it <container> su - <username>
#   docker exec -it <container> su -l <username> /bin/bash
#   docker exec -it <container> su -l <username> /bin/zsh
