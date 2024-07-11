# Use the latest Python 3 docker image
FROM nialljb/freesurfer-centos9:0.0.1

# Setup environment for Docker image
ENV HOME=/root/
ENV FLYWHEEL="/flywheel/v0"
WORKDIR $FLYWHEEL
RUN mkdir -p $FLYWHEEL/input

# Copy the contents of the directory the Dockerfile is into the working directory of the to be container
COPY ./ $FLYWHEEL/
COPY license.txt /usr/local/freesurfer/.license

# Install Dev dependencies 
RUN dnf update -y && \
    dnf install -y unzip gzip wget && \
    dnf install epel-release -y && \
    dnf install ImageMagick -y && \
    dnf install -y tcsh && \
    dnf install -y hostname && \
    dnf install -y zip && \
    dnf clean all

RUN pip3 install flywheel-gear-toolkit && \
    pip3 install flywheel-sdk && \
    pip3 install jsonschema && \
    pip3 install pandas  && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    cp license.txt /usr/local/freesurfer/.license

# # setup fs env
# ENV PATH /usr/local/freesurfer/bin:/usr/local/freesurfer/fsfast/bin:/usr/local/freesurfer/tktools:/usr/local/freesurfer/mni/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# ENV FREESURFER_HOME /usr/local/freesurfer
# ENV FREESURFER /usr/local/freesurfer

# # FSL setup
# #Install miniconda
# RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh && \
# /bin/bash ~/miniconda.sh -b -p /opt/conda
# ENV CONDA_DIR /opt/conda
# # store the FSL public conda channel
# ENV FSL_CONDA_CHANNEL="https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/public"
# # install tini into base conda environment
# RUN /opt/conda/bin/conda install -n base -c conda-forge tini -y
# RUN /opt/conda/bin/conda install -n base -c $FSL_CONDA_CHANNEL fsl-base fsl-utils fsl-avwutils -c conda-forge
# # set FSLDIR so FSL tools can use it, in this minimal case, the FSLDIR will be the root conda directory
# ENV PATH="/opt/conda/bin:${PATH}"
# ENV FSLDIR="/opt/conda"

# Configure entrypoint
RUN bash -c 'chmod +rx $FLYWHEEL/run.py' && \
    bash -c 'chmod +rx $FLYWHEEL/app/'

ENTRYPOINT ["python3","/flywheel/v0/start.sh"] 
# Flywheel reads the config command over this entrypoint