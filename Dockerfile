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
    && locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8

### Git ###
# RUN add-apt-repository -y ppa:git-core/ppa
# RUN apt-get update && apt-get install -y --no-install-recommends git git-lfs

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

ENV HOME=/home/gleez
WORKDIR $HOME
# custom Bash prompt
RUN { echo && echo "PS1='\[\033[01;32m\]\u\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\$(__git_ps1 \" (%s)\") $ '" ; } >> .bashrc

COPY default.gitconfig /etc/gitconfig
COPY --chown=gleez:gleez default.gitconfig /home/gleez/.gitconfig

# configure git-lfs
# RUN git lfs install --system --skip-repo

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
