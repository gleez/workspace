FROM buildpack-deps:jammy@sha256:f028439d1e21418883b8ea83670b1bb142aae932caa17602f4542cd33cb85094

ARG NODE_VERSION
ARG GO_VERSION
ARG RELEASE_TAG

### base ###
RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake \
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
        tree \
        emacs-nox \
        vim \
        multitail \
        lsof \
        ssl-cert \
        fish \
        zsh \
        libatomic1 \
        git \
        pip \
        poppler-utils \
        openssh-client \
        openssh-server \
        mysql-server \
        mysql-client \
        postgresql-client \
        net-tools \
        dnsutils \
        tzdata \
        ca-certificates \
        protobuf-compiler \
        llvm-dev \
        libclang-dev \
        clang \
        cargo \
        kmod \
        net-tools \
        iproute2 \
        libssl-dev \
        pkg-config \
    && locale-gen en_US.UTF-8

# ENV LANG=en_US.UTF-8

ARG RELEASE_ORG="gitpod-io"
ARG OPENVSCODE_SERVER_ROOT="/home/.openvscode-server"

### Update and upgrade the base image ###
RUN apt upgrade -y

### Git ###
RUN add-apt-repository -y ppa:git-core/ppa
# https://github.com/git-lfs/git-lfs/blob/main/INSTALLING.md
RUN curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
RUN apt-get update && apt-get install -y --no-install-recommends git git-lfs

### Python 3.11 ###
RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt-get update && apt-get install -y python3.11-full

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
    && useradd -l -u 1000 -G sudo --gid $USERNAME -md /home/gleez -s /bin/bash -p $USERNAME $USERNAME \
    # passwordless sudo for users in the 'sudo' group
    && sed -i.bkp -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers \
    # To emulate the workspace-session behavior within dazzle build env
    && mkdir /workspace && chown -hR gleez:gleez /workspace

RUN chmod g+rw /home && \
    mkdir -p /home/workspace && \
    chown -R $USERNAME:$USERNAME /home/workspace && \
    chown -R $USERNAME:$USERNAME /home/gleez && \
    chown -R $USERNAME:$USERNAME ${OPENVSCODE_SERVER_ROOT}
    
ENV HOME=/home/gleez
WORKDIR $HOME
# custom Bash prompt
RUN { echo && echo "PS1='\[\033[01;32m\]\u\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\$(__git_ps1 \" (%s)\") $ '" ; } >> .bashrc

COPY default.gitconfig /etc/gitconfig
COPY --chown=gleez:gleez default.gitconfig /home/gleez/.gitconfig

# Configure SSH to use Bash with colors by default.
RUN mkdir -p /home/gleez/.ssh \
 && chown -R gleez:gleez /home/gleez/.ssh \
 && touch /home/gleez/.ssh/authorized_keys \
 && touch /home/gleez/.ssh/config \
 && echo "SHELL=/bin/bash\nTERM=xterm-256color" >> /home/gleez/.ssh/environment \
 && chmod 700 /home/gleez/.ssh \
 && chmod 600 /home/gleez/.ssh/* \
 && chown -R gleez:gleez /workspace \
 && mkdir -p /var/run/watchman/gleez-state \
 && chown -R gleez:gleez /var/run/watchman/gleez-state

# configure git-lfs
RUN git lfs install --system --skip-repo

### Gleez user (2) ###
USER gleez
# use sudo so that user does not get sudo usage info on (the first) login
RUN sudo echo "Running 'sudo' for Gleez: success" \
    # create .bashrc.d folder and source it in the bashrc
    && mkdir -p /home/gleez/.bashrc.d \
    && (echo; echo "for i in \$(ls -A \$HOME/.bashrc.d/); do source \$HOME/.bashrc.d/\$i; done"; echo) >> /home/gleez/.bashrc \
    # create a completions dir for gleez user
    && mkdir -p /home/gleez/.local/share/bash-completion/completions \
    && git config --global user.email "hello@gleez.tech" \
    && git config --global user.name "Gleez Technologies"

ENV NODE_VERSION=${NODE_VERSION}

ENV PNPM_HOME=/home/gleez/.pnpm
ENV PATH=/home/gleez/.nvm/versions/node/v${NODE_VERSION}/bin:/home/gleez/.yarn/bin:${PNPM_HOME}:$PATH

RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | PROFILE=/dev/null bash \
    && bash -c ". .nvm/nvm.sh \
        && nvm install v${NODE_VERSION} \
        && nvm alias default v${NODE_VERSION} \
        && npm install -g typescript yarn pnpm node-gyp" \
    && echo ". ~/.nvm/nvm-lazy.sh"  >> /home/gleez/.bashrc.d/50-node
# above, we are adding the lazy nvm init to .bashrc, because one is executed on interactive shells, the other for non-interactive shells (e.g. plugin-host)
COPY --chown=gleez:gleez nvm-lazy.sh /home/gleez/.nvm/nvm-lazy.sh

ENV GO_VERSION=${GO_VERSION}
ENV GOPATH=$HOME/go-packages
ENV GOROOT=$HOME/go
ENV PATH=$GOROOT/bin:$GOPATH/bin:/home/gleez/bin:$PATH

RUN curl -fsSL https://dl.google.com/go/go$GO_VERSION.linux-amd64.tar.gz | tar xzs && \
# install VS Code Go tools for use with gopls as per https://github.com/golang/vscode-go/blob/master/docs/tools.md
# also https://github.com/golang/vscode-go/blob/27bbf42a1523cadb19fad21e0f9d7c316b625684/src/goTools.ts#L139
    go install -v github.com/uudashr/gopkgs/cmd/gopkgs@v2 && \
    go install -v github.com/ramya-rao-a/go-outline@latest && \
    go install -v github.com/cweill/gotests/gotests@latest && \
    go install -v github.com/fatih/gomodifytags@latest && \
    go install -v github.com/josharian/impl@latest && \
    go install -v github.com/haya14busa/goplay/cmd/goplay@latest && \
    go install -v github.com/go-delve/delve/cmd/dlv@latest && \
    go install -v github.com/golangci/golangci-lint/cmd/golangci-lint@latest && \
    go install -v golang.org/x/tools/gopls@latest && \
    go install -v honnef.co/go/tools/cmd/staticcheck@latest && \
    sudo rm -rf $GOPATH/src $GOPATH/pkg $HOME/.cache/go $HOME/.cache/go-build && \
    printf '%s\n' 'export GOPATH=/workspace/go' \
                  'export PATH=$GOPATH/bin:$PATH' > $HOME/.bashrc.d/300-go

WORKDIR /home/workspace/

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    EDITOR=code \
    VISUAL=code \
    GIT_EDITOR="code --wait" \
    OPENVSCODE_SERVER_ROOT=${OPENVSCODE_SERVER_ROOT} \
    PATH=$HOME/.local/bin:/usr/games:/home/workspace/bin:/home/gleez/.deno/bin:$PATH
  
  # Default exposed port if none is specified
EXPOSE 3000 8080 8081 8082 8083 8084 8085

ENTRYPOINT [ "/bin/sh", "-c", "exec ${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server --host 0.0.0.0 \"${@}\"", "--" ]
