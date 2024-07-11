#!/bin/env bash 

# Source FSL
FSLDIR=/opt/conda
. $FSLDIR/etc/fslconf/fsl.sh
echo "FSLOUTPUTTYPE set to $FSLOUTPUTTYPE"

# # Start the virtual display
# Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
# export DISPLAY=:99

# Run the gear
python3 -u /flywheel/v0/run.py
