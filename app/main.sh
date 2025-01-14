#! /bin/bash
#
# Run script for flywheel/recon-all-clinical Gear.
#
# Authorship: Anastasia Smirnova, Niall Bourke
#
##############################################################################
# Define directory names and containers

subject=$1
session=$2
base_filename=$3

FLYWHEEL_BASE=/flywheel/v0
INPUT_DIR=$FLYWHEEL_BASE/input/
OUTPUT_DIR=$FLYWHEEL_BASE/output
WORKDIR=$FLYWHEEL_BASE/work
CONFIG_FILE=$FLYWHEEL_BASE/config.json
CONTAINER='[flywheel/recon-all-clinical]'
source /usr/local/freesurfer/SetUpFreeSurfer.sh

echo "permissions"
ls -ltra /flywheel/v0/

mkdir $FLYWHEEL_BASE/work
chmod 777 $FLYWHEEL_BASE/work
##############################################################################
# Parse configuration
function parse_config {

  CONFIG_FILE=$FLYWHEEL_BASE/config.json
  MANIFEST_FILE=$FLYWHEEL_BASE/manifest.json

  if [[ -f $CONFIG_FILE ]]; then
    echo "$(cat $CONFIG_FILE | jq -r '.config.'$1)"
  else
    CONFIG_FILE=$MANIFEST_FILE
    echo "$(cat $MANIFEST_FILE | jq -r '.config.'$1'.default')"
  fi
}

# define output choise:
config_output_nifti="$(parse_config 'output_nifti')"
config_output_mgh="$(parse_config 'output_mgh')"
config_rob="$(parse_config 'robust')"

##############################################################################
# Define brain and face templates

brain_template=$FLYWHEEL_BASE/talairach_mixed_with_skull.gca
face_template=$FLYWHEEL_BASE/face.gca

##############################################################################
# Handle INPUT file

# Find input file In input directory with the extension
input_file=`find $INPUT_DIR -iname '*.nii' -o -iname '*.nii.gz'`

# Check that input file exists
if [[ -e $input_file ]]; then
  echo "${CONTAINER}  Input file found: ${input_file}"

    # Determine the type of the input file
  if [[ "$input_file" == *.nii ]]; then
    type=".nii"
  elif [[ "$input_file" == *.nii.gz ]]; then
    type=".nii.gz"
  fi
  
else
  echo "${CONTAINER}: No inputs were found within input directory $INPUT_DIR"
  exit 1
fi

##############################################################################
# Run mri_synthseg algorithm

# Set initial exit status
recon_all_clinical_exit_status=0


if [[ $config_rob == 'true' ]]; then
  robust='--robust'
fi

# Run recon-all-clinical with options
if [[ -e $input_file ]]; then
  echo "Running recon-all-clinical..."
  
  tcsh /usr/local/freesurfer/bin/recon-all-clinical.sh $input_file $base_filename 4 $WORKDIR  
  recon_all_clinical_exit_status=$?
fi

# Step 3: Copy output files to the output directory
#mri_convert $WORKDIR/$base_filename/mri/synthseg.mgz $OUTPUT_DIR/synthseg.nii
cp $WORKDIR/$base_filename/stats/synthseg.vol.csv $WORKDIR/synthseg.vol.csv
cp $WORKDIR/$base_filename/stats/synthseg.qc.csv $WORKDIR/synthseg.qc.csv
mri_convert --out_orientation RAS $WORKDIR/$base_filename/mri/synthSR.mgz $WORKDIR/synthSR.nii.gz
mri_convert --out_orientation RAS $WORKDIR/$base_filename/mri/aparc+aseg.mgz $WORKDIR/aparc+aseg.nii.gz
zip -r $OUTPUT_DIR/$base_filename.zip $WORKDIR/$base_filename


# Step 4: Extract cortical thickness measures
# Set SUBJECTS_DIR to the work directory
export SUBJECTS_DIR=$WORKDIR
aparcstats2table --subjects $base_filename --hemi lh --meas thickness --parc=aparc --tablefile=$WORKDIR/aparc_lh.csv
aparcstats2table --subjects $base_filename --hemi rh --meas thickness --parc=aparc --tablefile=$WORKDIR/aparc_rh.csv

  
# Handle Exit status
if [[ $recon_all_clinical_exit_status == 0 ]]; then
  echo -e "${CONTAINER} Success!"
  exit 0
else
  echo "${CONTAINER}  Something went wrong! recon-all-clinical exited non-zero!"
  exit 1
fi
