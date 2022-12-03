FROM buildpack-deps:22.04-curl

### base ###
RUN apt-get update && apt-get install -y --no-install-recommends \
        zip \
        unzip \
        bash-completion \
        build-essential \
        ninja-build \
        htop \
        iputils-ping \
        jq \
        less \
        locales \
        man-db \
        nano \
        ripgrep \
        software-properties-common \
        sudo \
        stow \
        time \
        emacs-nox \
        vim \
        multitail \
        lsof \
        ssl-cert \
        fish \
        zsh \
        libatomic1 \
        git \
        openssh-client \
        openssh-server \
        mysql-server \
        mysql-client \
        postgresql-12 \
        postgresql-contrib-12 \
        iputils \
        net-tools \
        tzdata \
        ca-certificates \
        protobuf-compiler \
    && locale-gen en_US.UTF-8

# ENV LANG=en_US.UTF-8

ARG RELEASE_TAG
ARG RELEASE_ORG="gitpod-io"
ARG OPENVSCODE_SERVER_ROOT="/home/.openvscode-server"

# Downloading the latest VSC Server release and extracting the release archive
# Rename `openvscode-server` cli tool to `code` for convenience
RUN if [ -z "${RELEASE_TAG}" ]; then \
        echo "The RELEASE_TAG build arg must be set." >&2 && \
        exit 1; \
    fi && \
    arch=$(uname -m) && \
    if [ "${arch}" = "x86_64" ]; then \
        arch="x64"; \
    elif [ "${arch}" = "aarch64" ]; then \
        arch="arm64"; \
    elif [ "${arch}" = "armv7l" ]; then \
        arch="armhf"; \
    fi && \
    wget https://github.com/${RELEASE_ORG}/openvscode-server/releases/download/${RELEASE_TAG}/${RELEASE_TAG}-linux-${arch}.tar.gz && \
    tar -xzf ${RELEASE_TAG}-linux-${arch}.tar.gz && \
    mv -f ${RELEASE_TAG}-linux-${arch} ${OPENVSCODE_SERVER_ROOT} && \
    cp ${OPENVSCODE_SERVER_ROOT}/bin/remote-cli/openvscode-server ${OPENVSCODE_SERVER_ROOT}/bin/remote-cli/code && \
    rm -f ${RELEASE_TAG}-linux-${arch}.tar.gz
 
ARG USERNAME=gleez
ARG USER_UID=1000
ARG USER_GID=$USER_UID

### Gleez user ###
# '-l': see https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#user
RUN groupadd --gid $USER_GID $USERNAME \
    useradd -l -u 1000 -G sudo -G $USERNAME -md /home/$USERNAME -s /bin/bash -p $USERNAME $USERNAME \
    # passwordless sudo for users in the 'sudo' group
    && sed -i.bkp -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers \
    # To emulate the workspace-session behavior within dazzle build env
    && mkdir /workspace && chown -hR $USERNAME:$USERNAME /workspace

RUN chmod g+rw /home && \
    mkdir -p /home/workspace && \
    chown -R $USERNAME:$USERNAME /home/workspace && \
    chown -R $USERNAME:$USERNAME ${OPENVSCODE_SERVER_ROOT}
    
ENV HOME=/home/gleez
WORKDIR $HOME
# custom Bash prompt
RUN { echo && echo "PS1='\[\033[01;32m\]\u\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\$(__git_ps1 \" (%s)\") $ '" ; } >> .bashrc

COPY default.gitconfig /etc/gitconfig
COPY --chown=gleez:gleez default.gitconfig /home/gleez/.gitconfig

### Gleez user (2) ###
USER gleez
# use sudo so that user does not get sudo usage info on (the first) login
RUN sudo echo "Running 'sudo' for Gleez: success" && \
    # create .bashrc.d folder and source it in the bashrc
    mkdir -p /home/gleez/.bashrc.d && \
    (echo; echo "for i in \$(ls -A \$HOME/.bashrc.d/); do source \$HOME/.bashrc.d/\$i; done"; echo) >> /home/gleez/.bashrc && \
    # create a completions dir for gleez user
    mkdir -p /home/gleez/.local/share/bash-completion/completions

# Custom PATH additions
ENV PATH=$HOME/.local/bin:/usr/games:$PATH

WORKDIR /home/workspace/

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    EDITOR=code \
    VISUAL=code \
    GIT_EDITOR="code --wait" \
    OPENVSCODE_SERVER_ROOT=${OPENVSCODE_SERVER_ROOT}
  
  # Default exposed port if none is specified
EXPOSE 3000 8080 8081 8082 8083 8084 8085

ENTRYPOINT [ "/bin/sh", "-c", "exec ${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server --host 0.0.0.0 \"${@}\"", "--" ]
