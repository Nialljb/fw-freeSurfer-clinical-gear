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

# copy ctx fix to freesurfer python scripts
RUN mv /usr/local/freesurfer/bin/recon-all-clinical.sh /usr/local/freesurfer/bin/DEPRICATED_recon-all-clinical.sh
RUN cp ./recon-all-clinical-fix.sh /usr/local/freesurfer/bin/recon-all-clinical.sh

# Configure entrypoint
RUN bash -c 'chmod +rx $FLYWHEEL/run.py' && \
    bash -c 'chmod +rx $FLYWHEEL/app/' && \
    bash -c 'chmod +rx $FLYWHEEL/start.sh'&& \
    bash -c 'chmod +rx ${FLYWHEEL}/app/main.sh' \
    bash -c 'chmod +rx /usr/local/freesurfer/bin/recon-all-clinical.sh'

ENTRYPOINT ["bash", "/flywheel/v0/start.sh"] 