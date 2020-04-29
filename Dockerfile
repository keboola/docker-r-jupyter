FROM quay.io/keboola/docker-custom-r:1.9.3

ARG NB_USER="jupyter"
ARG NB_UID="1000"
ARG NB_GID="100"

USER root

RUN apt-get update && apt-get -yq dist-upgrade \
 && apt-get install -yq --no-install-recommends \
    ca-certificates \
    locales \
    python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Taken from https://github.com/jupyter/docker-stacks/tree/master/base-notebook

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get -yq dist-upgrade \
 && apt-get install -yq --no-install-recommends \
    wget \
    bzip2 \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV SHELL /bin/bash
ENV NB_USER $NB_USER
ENV NB_UID $NB_UID
ENV NB_GID $NB_GID
ENV HOME /home/$NB_USER
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# Add a script that we will use to correct permissions after running certain commands
ADD fix-permissions /usr/local/bin/fix-permissions

# Create NB_USER with NB_UID and in the NB_GID group
# and make sure these dirs are writable by the NB_GID group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID -g $NB_GID $NB_USER && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME

# Install Tini
RUN wget --quiet https://github.com/krallin/tini/releases/download/v0.10.0/tini && \
    echo "1361527f39190a7338a0b434bd8c88ff7233ce7b9a4876f3315c22fce7eca1b0 *tini" | sha256sum -c - && \
    mv tini /usr/local/bin/tini && \
    chmod +x /usr/local/bin/tini && \
    fix-permissions /home/$NB_USER

USER $NB_UID
WORKDIR $HOME

# Setup work directory for backward-compatibility
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER

# Taken from https://github.com/jupyter/docker-stacks/blob/master/minimal-notebook/Dockerfile
# Install all OS dependencies for fully functional notebook server
# libav-tools for matplotlib anim
RUN apt-get update && apt-get upgrade -yq python3 \
    && apt-get install -yq --no-install-recommends \
        build-essential \
        emacs \
        git \
        inkscape \
        jed \
        libsm6 \
        libxext-dev \
        libxrender1 \
        lmodern \
        pandoc \
        python-dev \
        python3-pip \
        python3-setuptools \
        unzip \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure environment
ENV SHELL /bin/bash
ENV NB_USER root
ENV NB_UID 0
ENV HOME /home/$NB_USER
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# Taken from https://github.com/jupyter/docker-stacks/blob/master/scipy-notebook/Dockerfile

# run the pip installations as root
USER root
# Install Python 3 packages
# Remove pyqt and qt pulled in for matplotlib since we're only ever going to
# use notebook-friendly backends in these images
RUN pip3 install --no-cache-dir \
    notebook \
    jupyterhub \
    jupyterlab \
    ipywidgets \
    qgrid \
    mlflow

# Activate ipywidgets extension in the environment that runs the notebook server
RUN jupyter nbextension enable --py widgetsnbextension --sys-prefix \
 && jupyter nbextension enable --py --sys-prefix qgrid

RUN R -e 'install.packages("IRkernel")'

USER root

RUN R -e 'IRkernel::installspec()'

RUN jupyter kernelspec install /home/root/.local/share/jupyter/kernels/ir/ \
    && yes | jupyter kernelspec uninstall python3

# Install KBC Transformation package
RUN R -e "devtools::install_github('keboola/r-transformation', ref = '1.2.11')"

EXPOSE 8888
WORKDIR /data/

RUN fix-permissions /data
RUN fix-permissions /tmp

# the datadir should now be owned by NB_UID
USER $NB_UID
CMD chmod -R 777 /data
CMD chmod -R g+s /data
CMD chmod -R 777 /tmp
CMD chmod -R g+s /tmp

# add users local bin dir to PATH
ENV PATH=/home/$NB_USER/.local/bin:$PATH

# Configure container startup
ENTRYPOINT ["tini", "--"]
CMD ["start-lab.sh"]

# Add local files as late as possible to avoid cache busting
COPY start.sh /usr/local/bin/
COPY start-lab.sh /usr/local/bin/
COPY jupyter_notebook_config.py /etc/jupyter/
COPY wait-for-it.sh /usr/local/bin/
COPY install.R /usr/local/bin/

RUN chown -R $NB_USER:users /etc/jupyter/
