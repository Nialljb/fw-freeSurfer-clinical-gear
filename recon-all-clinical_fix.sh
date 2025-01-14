#! /bin/tcsh -f

set tcsh61706 = (`tcsh --version | grep "6\.17\.06"`)
if ("$tcsh61706" != "") then
  echo ""
  echo "WARNING: tcsh v6.17.06 has an exit code bug! Please update tcsh!"
  echo ""
  # workaround to force expected behavior:
  set anyerror
endif

set PYTHON_SCRIPT_DIR=$FREESURFER_HOME/python/scripts
set MODEL=$FREESURFER_HOME/models/synthsurf_v10_230420.h5

# If no arguments given
# If requesting help
if( $1 == "--help") then
  echo " "
  echo "Recon-all-like stream for clinical scans of arbigrary orientation/resolution/contrast"
  echo " "
  echo "Use this script to process clinical scans of arbitrary orientation, resolution, and "
  echo "contrast. It essentially runs a combination of:"
  echo "* SynthSeg: to obtain a volumetric segmentation and linear registration to Talairach space"
  echo "* SynthSR: to have a higher resolution 1mm MPRAGE for visualization"
  echo "* SynthDist: to fit surfaces by predicting the distance maps and reconstructing topologically accurate cortical surfaces"
  echo " "
  echo "Using this module is very simple: you just provide an input scan, the subject name, the"
  echo "number of threads you want to use, and (optionally) the subjects directory:"
  echo " "
  echo "   recon-all-clinical.sh INPUT_SCAN SUBJECT_ID THREADS [SUBJECT_DIR]"
  echo " "
  echo "   (the argument [SUBJECT_DIR] is only necessary if the"
  echo "    environment variable SUBJECTS_DIR has not been set"
  echo "    or if you want to override it)"
  echo " "
  echo "This stream runs a bit faster than the original recon-all, since the volumetric"
  echo "segmentation is much faster than the iterative Bayesian method in the standard stream"
  echo " "
  echo "If you use this stream for your analysis, please cite:"
  echo " "
  echo "K Gopinath, DN Greeve, S Das, S Arnold, C Magdamo, JE Iglesias:"
  echo "Cortical analysis of heterogeneous clinical brain MRI scans for large-scale neuroimaging studies"
  echo "https://arxiv.org/abs/2305.01827"
  echo " "
  echo "B Billot, DN Greve, O Puonti, A Thielscher, K Van Leemput, B Fischl, AV Dalca, JE Iglesias:"
  echo "SynthSeg: Segmentation of brain MRI scans of any contrast and resolution without retraining"
  echo "Medical Image Analysis, 83, 102789 (2023)"
  echo " "
  echo "B Billot, C Magdamo, SE Arnold, S Das, JE Iglesias:"
  echo "Robust machine learning segmentation for large-scale analysis of heterogeneous clinical brain MRI datasets"
  echo "PNAS, 120(9), e2216399120 (2023)"
  echo " "
  echo "SynthSR: a public AI tool to turn heterogeneous clinical brain scans into high-resolution T1-weighted images for 3D morphometry"
  echo "JE Iglesias, B Billot, Y Balbastre, C Magdamo, S Arnold, S Das, B Edlow, D Alexander, P Golland, B Fischl"
  echo "Science Advances, 9(5), eadd3607 (2023)"
  echo " "
  exit 0
endif

if( $#argv < 3 || $#argv > 4) then
  echo " "
  echo "Usage: "
  echo " "
  echo "   recon-all-clinical.sh INPUT_SCAN SUBJECT_ID THREADS [SUBJECT_DIR]"
  echo " "
  echo "Or, for help"
  echo " "
  echo "   recon-all-clinical.sh --help"
  echo " "
  exit 1
endif

setenv INPUT_SCAN $1
setenv SNAME $2
setenv THREADS $3

# Error if SUBJECTS_DIR (the environment variable) does not exist
if ($#argv == 3) then
  if (! $?SUBJECTS_DIR)  then
    echo " "
    echo "SUBJECTS_DIR variable does not exist"
    echo "Please define it or provide subjects directory as fourth input"
    echo " "
    exit 1
  endif
endif

# Error if SUBJECTS_DIR (the environemnt variable) is empty
if ($#argv == 3) then
  if ( $SUBJECTS_DIR == "" ) then
    echo " "
    echo "SUBJECTS_DIR variable is empty"
    echo "Please redefine it or provide subjects directory as second input"
    echo " "
    exit 1
  endif
endif

# If SUBJECTS_DIR is provided, just set it
if ($#argv == 4) then
  set SUBJECTS_DIR = `getfullpath  $4`
  setenv SUBJECTS_DIR $SUBJECTS_DIR
endif

# Error if subject directory does not exist
if (! -d $SUBJECTS_DIR ) then
  echo " "
  echo "Subjects directory:"
  echo "   $SUBJECTS_DIR"
  echo "does not exist"
  echo " "
  exit 1
endif

# Make sure that the (T1) hippocampal subfields are not running already for this subject
set IsRunningFile = ${SUBJECTS_DIR}/${SNAME}/scripts/IsRunning.lh+rh
if(-e $IsRunningFile) then
  echo ""
  echo "It appears that recon-all-clinical is already running for this subject,"
  echo "based on the presence of IsRunning.lh+rh"
  echo "It could also be recon-all-clinical was running at one point but died"
  echo "in an unexpected way. If it is the case that there is a process running,"
  echo "you can kill it and start over or just let it run. If the process has"
  echo "died, you should type:"
  echo ""
  echo "rm $IsRunningFile"
  echo ""
  echo "and re-run."
  echo "----------------------------------------------------------"
  cat  $IsRunningFile
  echo "----------------------------------------------------------"
  exit 1;
endif

# If everything is in place, let's do it! First, we create the directories we need
mkdir -p $SUBJECTS_DIR/$SNAME
mkdir -p $SUBJECTS_DIR/$SNAME/label
mkdir -p $SUBJECTS_DIR/$SNAME/mri
mkdir -p $SUBJECTS_DIR/$SNAME/mri/transforms
mkdir -p $SUBJECTS_DIR/$SNAME/scripts
mkdir -p $SUBJECTS_DIR/$SNAME/stats
mkdir -p $SUBJECTS_DIR/$SNAME/surf
mkdir -p $SUBJECTS_DIR/$SNAME/tmp
mkdir -p $SUBJECTS_DIR/$SNAME/touch
mkdir -p $SUBJECTS_DIR/$SNAME/trash

# Next, we create the IsRunning file
echo "------------------------------" > $IsRunningFile
echo "SUBJECT SNAME" >> $IsRunningFile
echo "DATE `date`"     >> $IsRunningFile
echo "USER $user"      >> $IsRunningFile
echo "HOST `hostname`" >> $IsRunningFile
echo "PROCESSID $$ "   >> $IsRunningFile
echo "PROCESSOR `uname -m`" >> $IsRunningFile
echo "OS `uname -s`"       >> $IsRunningFile
uname -a         >> $IsRunningFile
if($?PBS_JOBID) then
  echo "pbsjob $PBS_JOBID"  >> $IsRunningFile
endif

set LogFile = (${SUBJECTS_DIR}/${SNAME}/scripts/recon-all-clinical.log)
rm -f $LogFile

echo "------------------------------" > $LogFile
echo "USER $user"      >> $LogFile
echo "HOST `hostname`" >> $LogFile
echo "PROCESSID $$ "   >> $LogFile
echo "PROCESSOR `uname -m`" >> $LogFile
echo "OS `uname -s`"       >> $LogFile
echo "NUMBER OF THREADS $THREADS " >> $LogFile
uname -a         >> $LogFile
if($?PBS_JOBID) then
  echo "pbsjob $PBS_JOBID"  >> $LogFile
endif
echo "------------------------------" >> $LogFile
echo " " >> $LogFile
cat $FREESURFER_HOME/build-stamp.txt  >> $LogFile
echo " " >> $LogFile
echo "setenv SUBJECTS_DIR $SUBJECTS_DIR"  >> $LogFile
echo "cd `pwd`"   >> $LogFile
echo $0 $argv  >> $LogFile
echo ""  >> $LogFile


echo "#--------------------------------------------" \
   |& tee -a $LogFile
 echo "#@# recon-all-clinical `date`" \
   |& tee -a $LogFile
echo " " |& tee -a $LogFile

############
# commands #
############

# Initial mri_convert
set cmd="mri_convert $INPUT_SCAN $SUBJECTS_DIR/$SNAME/mri/native.mgz"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mri_convert" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

cd $SUBJECTS_DIR/$SNAME/mri

# SynthSeg
set cmd="mri_synthseg --i ./native.mgz --o ./synthseg.mgz --parc --threads $THREADS --robust --vol ../stats/synthseg.vol.csv --cpu --qc ../stats/synthseg.qc.csv"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in SynthSeg" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

# SynthSR
set cmd="mri_synthsr --i ./native.mgz --o ./synthSR.raw.mgz --threads $THREADS --cpu"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in SynthSR" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

# SynthSurf (Karthik's) code
set cmd="fspython $PYTHON_SCRIPT_DIR/mri_synth_surf.py --subject_mri_dir $PWD   --input_image ./native.mgz --input_synthseg ./synthseg.mgz  --cpu --threads $THREADS --pad 5   --model_file $MODEL"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in SynthSurfaces" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

# Create norm.synthsr.mgz (useful for some bits here and there)
mri_convert ./synthseg.mgz ./synthseg.resampled.mgz -rl ./synthSR.raw.mgz -rt nearest -odt float
set cmd="fspython $PYTHON_SCRIPT_DIR/norm_synthSR.py ./synthSR.raw.mgz ./synthseg.resampled.mgz ./synthSR.norm.tmp.mgz"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in norm_synthSR" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile
rm ./synthseg.resampled.mgz
mri_convert ./synthSR.norm.tmp.mgz ./synthSR.norm.mgz -rl ./norm.mgz -odt float
rm  ./synthSR.norm.tmp.mgz


# LTA convert
set cmd="lta_convert --src norm.mgz --trg $FREESURFER_HOME/average/mni305.cor.mgz --inxfm transforms/talairach.xfm --outlta transforms/talairach.xfm.lta --subject fsaverage --ltavox2vox"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in LTA convert" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

# Corpus callosum: TODO: doesn't work very well, I'm not exactly sure why...
set cmd="mri_cc -norm ./synthSR.norm.mgz -aseg ./aseg.auto_noCCseg.mgz -o aseg.presurf.mgz -lta ./transforms/cc_up.lta $SNAME"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mri_cc (corpus callosum)" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

# mri_pretess
set cmd="mri_pretess wm.seg.mgz wm norm.mgz wm.mgz"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mri_pretess" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

set cmd="mri_pretess ./filled.mgz 255 ./norm.mgz ./filled-pretess255.mgz"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mri_pretess" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

set cmd="mri_tessellate ./filled-pretess255.mgz 255 ../surf/lh.orig.nofix"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mri_tessellate" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile
rm -f ../mri/filled-pretess255.mgz

set cmd="mris_extract_main_component ../surf/lh.orig.nofix ../surf/lh.orig.nofix"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mris_extract_main_component" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

set cmd="mri_pretess ./filled.mgz 127 ./norm.mgz ./filled-pretess127.mgz"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mri_pretess" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

set cmd="mri_tessellate ./filled-pretess127.mgz 127 ../surf/rh.orig.nofix"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mri_tessellate" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile
rm -f ../mri/filled-pretess127.mgz

set cmd="mris_extract_main_component ../surf/rh.orig.nofix ../surf/rh.orig.nofix"
$cmd |& tee -a $LogFile
if ($status) then
  echo "Error in mris_extract_main_component" |& tee -a $LogFile
  exit 1
endif
echo " " |& tee -a $LogFile

cd ../surf

# Eugenio: I don't think commands can really go wrong from here on... so I stop the checking

# Smooth, infate, sphere. topology
set cmd="mris_smooth -nw -seed 1234 ./lh.orig.nofix ./lh.smoothwm.nofix"
$cmd |& tee -a $LogFile
set cmd="mris_smooth -nw -seed 1234 ./rh.orig.nofix ./rh.smoothwm.nofix"
$cmd |& tee -a $LogFile
set cmd="mris_inflate -no-save-sulc ./lh.smoothwm.nofix ./lh.inflated.nofix"
$cmd |& tee -a $LogFile
set cmd="mris_inflate -no-save-sulc ./rh.smoothwm.nofix ./rh.inflated.nofix"
$cmd |& tee -a $LogFile
set cmd="mris_sphere -q -p 6 -a 128 -seed 1234 ./lh.inflated.nofix ./lh.qsphere.nofix"
$cmd |& tee -a $LogFile
set cmd="mris_sphere -q -p 6 -a 128 -seed 1234 ./rh.inflated.nofix ./rh.qsphere.nofix"
$cmd |& tee -a $LogFile
set cmd="mris_fix_topology -mgz -sphere qsphere.nofix -inflated inflated.nofix -orig orig.nofix -out orig.premesh -ga -seed 1234 $SNAME lh -threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_fix_topology -mgz -sphere qsphere.nofix -inflated inflated.nofix -orig orig.nofix -out orig.premesh -ga -seed 1234 $SNAME rh -threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_euler_number ./lh.orig.premesh"
$cmd |& tee -a $LogFile
set cmd="mris_euler_number ./rh.orig.premesh"
$cmd |& tee -a $LogFile

# Remesh and remove intersections
set cmd="mris_remesh --remesh --iters 3 --input ./lh.orig.premesh --output ./lh.orig"
$cmd |& tee -a $LogFile
set cmd="mris_remesh --remesh --iters 3 --input ./rh.orig.premesh --output ./rh.orig"
$cmd |& tee -a $LogFile
set cmd="mris_remove_intersection ./lh.orig ./lh.orig"
$cmd |& tee -a $LogFile
rm -f ./lh.inflated
set cmd="mris_remove_intersection ./rh.orig ./rh.orig"
$cmd |& tee -a $LogFile
rm -f ./rh.inflated

cd ../mri

# Place surfaces
set cmd="mris_autodet_gwstats --o ../surf/autodet.gw.stats.lh.dat --i brain.mgz --wm wm.mgz --surf ../surf/lh.orig.premesh"
$cmd |& tee -a $LogFile
set cmd="mris_autodet_gwstats --o ../surf/autodet.gw.stats.rh.dat --i brain.mgz --wm wm.mgz --surf ../surf/rh.orig.premesh"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --adgws-in ../surf/autodet.gw.stats.lh.dat --wm wm.mgz --threads $THREADS --invol brain.mgz --lh --i ../surf/lh.orig --o ../surf/lh.white.preaparc --white --seg aseg.presurf.mgz --nsmooth 5"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --adgws-in ../surf/autodet.gw.stats.rh.dat --wm wm.mgz --threads $THREADS --invol brain.mgz --rh --i ../surf/rh.orig --o ../surf/rh.white.preaparc --white --seg aseg.presurf.mgz --nsmooth 5"
$cmd |& tee -a $LogFile

$cmd |& tee -a $LogFile
set cmd="mri_label2label --label-cortex ../surf/lh.white.preaparc aseg.presurf.mgz 0 ../label/lh.cortex.label"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --label-cortex ../surf/lh.white.preaparc aseg.presurf.mgz 1 ../label/lh.cortex+hipamyg.label"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --label-cortex ../surf/rh.white.preaparc aseg.presurf.mgz 0 ../label/rh.cortex.label"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --label-cortex ../surf/rh.white.preaparc aseg.presurf.mgz 1 ../label/rh.cortex+hipamyg.label"
$cmd |& tee -a $LogFile

cd ../surf

# Second round of smoothing / inflating / mapping
set cmd="mris_smooth -n 3 -nw -seed 1234 ./lh.white.preaparc ./lh.smoothwm"
$cmd |& tee -a $LogFile
set cmd="mris_smooth -n 3 -nw -seed 1234 ./rh.white.preaparc ./rh.smoothwm"
$cmd |& tee -a $LogFile
set cmd="mris_inflate ./lh.smoothwm ./lh.inflated"
$cmd |& tee -a $LogFile
set cmd="mris_inflate ./rh.smoothwm ./rh.inflated"
$cmd |& tee -a $LogFile
set cmd="mris_curvature -w -seed 1234 lh.white.preaparc"
$cmd |& tee -a $LogFile
set cmd="mris_curvature -seed 1234 -thresh .999 -n -a 5 -w -distances 10 10 lh.inflated"
$cmd |& tee -a $LogFile
set cmd="mris_curvature -w -seed 1234 rh.white.preaparc"
$cmd |& tee -a $LogFile
set cmd="mris_curvature -seed 1234 -thresh .999 -n -a 5 -w -distances 10 10 rh.inflated"
$cmd |& tee -a $LogFile
set cmd="mris_sphere -seed 1234 ../surf/lh.inflated ../surf/lh.sphere"
$cmd |& tee -a $LogFile
set cmd="mris_sphere -seed 1234 ../surf/rh.inflated ../surf/rh.sphere"
$cmd |& tee -a $LogFile

# Cortical registration
set cmd="mris_register -curv ./lh.sphere $FREESURFER_HOME/average/lh.folding.atlas.acfb40.noaparc.i12.2016-08-02.tif ./lh.sphere.reg -threads $THREADS"
$cmd |& tee -a $LogFile
ln -sf lh.sphere.reg lh.fsaverage.sphere.reg
set cmd="mris_register -curv ./rh.sphere $FREESURFER_HOME/average/rh.folding.atlas.acfb40.noaparc.i12.2016-08-02.tif ./rh.sphere.reg -threads $THREADS"
$cmd |& tee -a $LogFile
ln -sf rh.sphere.reg rh.fsaverage.sphere.reg

# Cortical segmentation
set cmd="mris_jacobian ./lh.white.preaparc ./lh.sphere.reg ./lh.jacobian_white"
$cmd |& tee -a $LogFile
set cmd="mris_jacobian ./rh.white.preaparc ./rh.sphere.reg ./rh.jacobian_white"
$cmd |& tee -a $LogFile
set cmd="mrisp_paint -a 5 $FREESURFER_HOME/average/lh.folding.atlas.acfb40.noaparc.i12.2016-08-02.tif#6 ./lh.sphere.reg ./lh.avg_curv"
$cmd |& tee -a $LogFile
set cmd="mrisp_paint -a 5 $FREESURFER_HOME/average/rh.folding.atlas.acfb40.noaparc.i12.2016-08-02.tif#6 ./rh.sphere.reg ./rh.avg_curv"
$cmd |& tee -a $LogFile
set cmd="mris_ca_label -l ../label/lh.cortex.label -aseg ../mri/aseg.presurf.mgz -seed 1234 $SNAME lh ./lh.sphere.reg $FREESURFER_HOME/average/lh.DKaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs ../label/lh.aparc.annot -threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_ca_label -l ../label/rh.cortex.label -aseg ../mri/aseg.presurf.mgz -seed 1234 $SNAME rh ./rh.sphere.reg $FREESURFER_HOME/average/rh.DKaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs ../label/rh.aparc.annot -threads $THREADS"
$cmd |& tee -a $LogFile

cd ../mri
# Reposition surfaces (including pial) and compute curvature stats as well as ribbon mask
set cmd="mris_place_surface --adgws-in ../surf/autodet.gw.stats.lh.dat --seg aseg.presurf.mgz --threads $THREADS --wm wm.mgz --invol brain.mgz --lh --i ../surf/lh.white.preaparc --o ../surf/lh.white --white --nsmooth 0 --rip-label ../label/lh.cortex.label --rip-bg --rip-surf ../surf/lh.white.preaparc --aparc ../label/lh.aparc.annot"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --adgws-in ../surf/autodet.gw.stats.rh.dat --seg aseg.presurf.mgz --threads $THREADS --wm wm.mgz --invol brain.mgz --rh --i ../surf/rh.white.preaparc --o ../surf/rh.white --white --nsmooth 0 --rip-label ../label/rh.cortex.label --rip-bg --rip-surf ../surf/rh.white.preaparc --aparc ../label/rh.aparc.annot"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --adgws-in ../surf/autodet.gw.stats.lh.dat --seg aseg.presurf.mgz --threads $THREADS --wm wm.mgz --invol brain.mgz --lh --i ../surf/lh.white --o ../surf/lh.pial --pial --nsmooth 0 --rip-label ../label/lh.cortex+hipamyg.label --pin-medial-wall ../label/lh.cortex.label --aparc ../label/lh.aparc.annot --repulse-surf ../surf/lh.white --white-surf ../surf/lh.white"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --adgws-in ../surf/autodet.gw.stats.rh.dat --seg aseg.presurf.mgz --threads $THREADS --wm wm.mgz --invol brain.mgz --rh --i ../surf/rh.white --o ../surf/rh.pial --pial --nsmooth 0 --rip-label ../label/rh.cortex+hipamyg.label --pin-medial-wall ../label/rh.cortex.label --aparc ../label/rh.aparc.annot --repulse-surf ../surf/rh.white --white-surf ../surf/rh.white"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --curv-map ../surf/lh.white 2 10 ../surf/lh.curv --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --area-map ../surf/lh.white ../surf/lh.area --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --curv-map ../surf/lh.pial 2 10 ../surf/lh.curv.pial --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --area-map ../surf/lh.pial ../surf/lh.area.pial --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --thickness ../surf/lh.white ../surf/lh.pial 20 5 ../surf/lh.thickness --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --thickness ../surf/lh.white ../surf/lh.pial 20 5 ../surf/lh.thickness --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --curv-map ../surf/rh.white 2 10 ../surf/rh.curv --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --area-map ../surf/rh.white ../surf/rh.area --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --curv-map ../surf/rh.pial 2 10 ../surf/rh.curv.pial --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --area-map ../surf/rh.pial ../surf/rh.area.pial --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --thickness ../surf/rh.white ../surf/rh.pial 20 5 ../surf/rh.thickness --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_place_surface --thickness ../surf/rh.white ../surf/rh.pial 20 5 ../surf/rh.thickness --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_curvature_stats -m --writeCurvatureFiles -G -o ../stats/lh.curv.stats -F smoothwm $SNAME lh curv sulc"
$cmd |& tee -a $LogFile
set cmd="mris_curvature_stats -m --writeCurvatureFiles -G -o ../stats/rh.curv.stats -F smoothwm $SNAME rh curv sulc"
$cmd |& tee -a $LogFile
set cmd="mris_volmask --aseg_name aseg.presurf --label_left_white 2 --label_left_ribbon 3 --label_right_white 41 --label_right_ribbon 42 --save_ribbon $SNAME --threads $THREADS"
$cmd |& tee -a $LogFile

# Refine SynthSR and aseg with ribbon
set cmd="fspython $PYTHON_SCRIPT_DIR/refine_synthSR.py ./synthSR.norm.mgz ./ribbon.mgz ./brain.mgz ./synthSR.mgz"
$cmd |& tee -a $LogFile
set cmd="mri_surf2volseg --o aseg.mgz --i aseg.presurf.mgz --fix-presurf-with-ribbon ./ribbon.mgz --threads 1 --lh-cortex-mask ../label/lh.cortex.label --lh-white ../surf/lh.white --lh-pial ../surf/lh.pial --rh-cortex-mask ../label/rh.cortex.label --rh-white ../surf/rh.white --rh-pial ../surf/rh.pial"
$cmd |& tee -a $LogFile

# More cortical parcellations
set cmd="mris_ca_label -l ../label/lh.cortex.label -aseg ./aseg.presurf.mgz -seed 1234 $SNAME lh ../surf/lh.sphere.reg $FREESURFER_HOME/average/lh.CDaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs ../label/lh.aparc.a2009s.annot --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_ca_label -l ../label/rh.cortex.label -aseg ./aseg.presurf.mgz -seed 1234 $SNAME rh ../surf/rh.sphere.reg $FREESURFER_HOME/average/rh.CDaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs ../label/rh.aparc.a2009s.annot --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_ca_label -l ../label/lh.cortex.label -aseg ./aseg.presurf.mgz -seed 1234 $SNAME lh ../surf/lh.sphere.reg $FREESURFER_HOME/average/lh.DKTaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs ../label/lh.aparc.DKTatlas.annot --threads $THREADS"
$cmd |& tee -a $LogFile
set cmd="mris_ca_label -l ../label/rh.cortex.label -aseg ./aseg.presurf.mgz -seed 1234 $SNAME rh ../surf/rh.sphere.reg $FREESURFER_HOME/average/rh.DKTaparc.atlas.acfb40.noaparc.i12.2016-08-02.gcs ../label/rh.aparc.DKTatlas.annot --threads $THREADS"
$cmd |& tee -a $LogFile

# mri_surf2volseg
set cmd="mri_surf2volseg --o aparc+aseg.mgz --label-cortex --i aseg.mgz --threads $THREADS --lh-annot ../label/lh.aparc.annot 1000 --lh-cortex-mask ../label/lh.cortex.label --lh-white ../surf/lh.white --lh-pial ../surf/lh.pial --rh-annot ../label/rh.aparc.annot 2000 --rh-cortex-mask ../label/rh.cortex.label --rh-white ../surf/rh.white --rh-pial ../surf/rh.pial"
$cmd |& tee -a $LogFile
set cmd="mri_surf2volseg --o aparc.a2009s+aseg.mgz --label-cortex --i aseg.mgz --threads $THREADS --lh-annot ../label/lh.aparc.a2009s.annot 11100 --lh-cortex-mask ../label/lh.cortex.label --lh-white ../surf/lh.white --lh-pial ../surf/lh.pial --rh-annot ../label/rh.aparc.a2009s.annot 12100 --rh-cortex-mask ../label/rh.cortex.label --rh-white ../surf/rh.white --rh-pial ../surf/rh.pial"
$cmd |& tee -a $LogFile
set cmd="mri_surf2volseg --o aparc.DKTatlas+aseg.mgz --label-cortex --i aseg.mgz --threads $THREADS --lh-annot ../label/lh.aparc.DKTatlas.annot 1000 --lh-cortex-mask ../label/lh.cortex.label --lh-white ../surf/lh.white --lh-pial ../surf/lh.pial --rh-annot ../label/rh.aparc.DKTatlas.annot 2000 --rh-cortex-mask ../label/rh.cortex.label --rh-white ../surf/rh.white --rh-pial ../surf/rh.pial"
$cmd |& tee -a $LogFile
set cmd="mri_surf2volseg --o wmparc.mgz --label-wm --i aparc+aseg.mgz --threads $THREADS --lh-annot ../label/lh.aparc.annot 3000 --lh-cortex-mask ../label/lh.cortex.label --lh-white ../surf/lh.white --lh-pial ../surf/lh.pial --rh-annot ../label/rh.aparc.annot 4000 --rh-cortex-mask ../label/rh.cortex.label --rh-white ../surf/rh.white --rh-pial ../surf/rh.pial"
$cmd |& tee -a $LogFile

# anatomical stats
set cmd="mris_anatomical_stats -th3 -mgz -cortex ../label/lh.cortex.label -f ../stats/lh.aparc.stats -b -a ../label/lh.aparc.annot -c ../label/aparc.annot.ctab $SNAME lh white"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -cortex ../label/lh.cortex.label -f ../stats/lh.aparc.pial.stats -b -a ../label/lh.aparc.annot -c ../label/aparc.annot.ctab $SNAME lh pial"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -cortex ../label/rh.cortex.label -f ../stats/rh.aparc.stats -b -a ../label/rh.aparc.annot -c ../label/aparc.annot.ctab $SNAME rh white"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -cortex ../label/rh.cortex.label -f ../stats/rh.aparc.pial.stats -b -a ../label/rh.aparc.annot -c ../label/aparc.annot.ctab $SNAME rh pial"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -cortex ../label/lh.cortex.label -f ../stats/lh.aparc.a2009s.stats -b -a ../label/lh.aparc.a2009s.annot -c ../label/aparc.annot.a2009s.ctab $SNAME lh white"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -cortex ../label/rh.cortex.label -f ../stats/rh.aparc.a2009s.stats -b -a ../label/rh.aparc.a2009s.annot -c ../label/aparc.annot.a2009s.ctab $SNAME rh white"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -cortex ../label/lh.cortex.label -f ../stats/lh.aparc.DKTatlas.stats -b -a ../label/lh.aparc.DKTatlas.annot -c ../label/aparc.annot.DKTatlas.ctab $SNAME lh white"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -cortex ../label/rh.cortex.label -f ../stats/rh.aparc.DKTatlas.stats -b -a ../label/rh.aparc.DKTatlas.annot -c ../label/aparc.annot.DKTatlas.ctab $SNAME rh white"
$cmd |& tee -a $LogFile

if ( ! -e $SUBJECTS_DIR/fsaverage) then
  ln -s $FREESURFER_HOME/subjects/fsaverage $SUBJECTS_DIR/
endif  
cd ../label

# labels
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA1_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA1_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA2_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA2_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA3a_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA3a_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA3b_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA3b_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA4a_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA4a_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA4p_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA4p_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA6_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA6_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA44_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA44_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA45_exvivo.label --trgsubject $SNAME --trglabel ./lh.BA45_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.V1_exvivo.label --trgsubject $SNAME --trglabel ./lh.V1_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.V2_exvivo.label --trgsubject $SNAME --trglabel ./lh.V2_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.MT_exvivo.label --trgsubject $SNAME --trglabel ./lh.MT_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.entorhinal_exvivo.label --trgsubject $SNAME --trglabel ./lh.entorhinal_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.perirhinal_exvivo.label --trgsubject $SNAME --trglabel ./lh.perirhinal_exvivo.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.FG1.mpm.vpnl.label --trgsubject $SNAME --trglabel ./lh.FG1.mpm.vpnl.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.FG2.mpm.vpnl.label --trgsubject $SNAME --trglabel ./lh.FG2.mpm.vpnl.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.FG3.mpm.vpnl.label --trgsubject $SNAME --trglabel ./lh.FG3.mpm.vpnl.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.FG4.mpm.vpnl.label --trgsubject $SNAME --trglabel ./lh.FG4.mpm.vpnl.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.hOc1.mpm.vpnl.label --trgsubject $SNAME --trglabel ./lh.hOc1.mpm.vpnl.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.hOc2.mpm.vpnl.label --trgsubject $SNAME --trglabel ./lh.hOc2.mpm.vpnl.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.hOc3v.mpm.vpnl.label --trgsubject $SNAME --trglabel ./lh.hOc3v.mpm.vpnl.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.hOc4v.mpm.vpnl.label --trgsubject $SNAME --trglabel ./lh.hOc4v.mpm.vpnl.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mris_label2annot --s $SNAME --ctab $FREESURFER_HOME/average/colortable_vpnl.txt --hemi lh --a mpm.vpnl --maxstatwinner --noverbose --l lh.FG1.mpm.vpnl.label --l lh.FG2.mpm.vpnl.label --l lh.FG3.mpm.vpnl.label --l lh.FG4.mpm.vpnl.label --l lh.hOc1.mpm.vpnl.label --l lh.hOc2.mpm.vpnl.label --l lh.hOc3v.mpm.vpnl.label --l lh.hOc4v.mpm.vpnl.label"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA1_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA1_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA2_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA2_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA3a_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA3a_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA3b_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA3b_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA4a_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA4a_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA4p_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA4p_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA6_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA6_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA44_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA44_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.BA45_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.BA45_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.V1_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.V1_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.V2_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.V2_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.MT_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.MT_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.entorhinal_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.entorhinal_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/lh.perirhinal_exvivo.thresh.label --trgsubject $SNAME --trglabel ./lh.perirhinal_exvivo.thresh.label --hemi lh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mris_label2annot --s $SNAME --hemi lh --ctab $FREESURFER_HOME/average/colortable_BA.txt --l lh.BA1_exvivo.label --l lh.BA2_exvivo.label --l lh.BA3a_exvivo.label --l lh.BA3b_exvivo.label --l lh.BA4a_exvivo.label --l lh.BA4p_exvivo.label --l lh.BA6_exvivo.label --l lh.BA44_exvivo.label --l lh.BA45_exvivo.label --l lh.V1_exvivo.label --l lh.V2_exvivo.label --l lh.MT_exvivo.label --l lh.perirhinal_exvivo.label --l lh.entorhinal_exvivo.label --a BA_exvivo --maxstatwinner --noverbose"
$cmd |& tee -a $LogFile
set cmd="mris_label2annot --s $SNAME --hemi lh --ctab $FREESURFER_HOME/average/colortable_BA_thresh.txt --l lh.BA1_exvivo.thresh.label --l lh.BA2_exvivo.thresh.label --l lh.BA3a_exvivo.thresh.label --l lh.BA3b_exvivo.thresh.label --l lh.BA4a_exvivo.thresh.label --l lh.BA4p_exvivo.thresh.label --l lh.BA6_exvivo.thresh.label --l lh.BA44_exvivo.thresh.label --l lh.BA45_exvivo.thresh.label --l lh.V1_exvivo.thresh.label --l lh.V2_exvivo.thresh.label --l lh.MT_exvivo.thresh.label --l lh.perirhinal_exvivo.thresh.label --l lh.entorhinal_exvivo.thresh.label --a BA_exvivo.thresh --maxstatwinner --noverbose"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -f ../stats/lh.BA_exvivo.stats -b -a ./lh.BA_exvivo.annot -c ./BA_exvivo.ctab $SNAME lh white"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -f ../stats/lh.BA_exvivo.thresh.stats -b -a ./lh.BA_exvivo.thresh.annot -c ./BA_exvivo.thresh.ctab $SNAME lh white"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA1_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA1_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA2_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA2_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA3a_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA3a_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA3b_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA3b_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA4a_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA4a_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA4p_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA4p_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA6_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA6_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA44_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA44_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA45_exvivo.label --trgsubject $SNAME --trglabel ./rh.BA45_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.V1_exvivo.label --trgsubject $SNAME --trglabel ./rh.V1_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.V2_exvivo.label --trgsubject $SNAME --trglabel ./rh.V2_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.MT_exvivo.label --trgsubject $SNAME --trglabel ./rh.MT_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.entorhinal_exvivo.label --trgsubject $SNAME --trglabel ./rh.entorhinal_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.perirhinal_exvivo.label --trgsubject $SNAME --trglabel ./rh.perirhinal_exvivo.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.FG1.mpm.vpnl.label --trgsubject $SNAME --trglabel ./rh.FG1.mpm.vpnl.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.FG2.mpm.vpnl.label --trgsubject $SNAME --trglabel ./rh.FG2.mpm.vpnl.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.FG3.mpm.vpnl.label --trgsubject $SNAME --trglabel ./rh.FG3.mpm.vpnl.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.FG4.mpm.vpnl.label --trgsubject $SNAME --trglabel ./rh.FG4.mpm.vpnl.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.hOc1.mpm.vpnl.label --trgsubject $SNAME --trglabel ./rh.hOc1.mpm.vpnl.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.hOc2.mpm.vpnl.label --trgsubject $SNAME --trglabel ./rh.hOc2.mpm.vpnl.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.hOc3v.mpm.vpnl.label --trgsubject $SNAME --trglabel ./rh.hOc3v.mpm.vpnl.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.hOc4v.mpm.vpnl.label --trgsubject $SNAME --trglabel ./rh.hOc4v.mpm.vpnl.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mris_label2annot --s $SNAME --ctab $FREESURFER_HOME/average/colortable_vpnl.txt --hemi rh --a mpm.vpnl --maxstatwinner --noverbose --l rh.FG1.mpm.vpnl.label --l rh.FG2.mpm.vpnl.label --l rh.FG3.mpm.vpnl.label --l rh.FG4.mpm.vpnl.label --l rh.hOc1.mpm.vpnl.label --l rh.hOc2.mpm.vpnl.label --l rh.hOc3v.mpm.vpnl.label --l rh.hOc4v.mpm.vpnl.label"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA1_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA1_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA2_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA2_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA3a_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA3a_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA3b_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA3b_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA4a_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA4a_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA4p_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA4p_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA6_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA6_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA44_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA44_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.BA45_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.BA45_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.V1_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.V1_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.V2_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.V2_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.MT_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.MT_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.entorhinal_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.entorhinal_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mri_label2label --srcsubject fsaverage --srclabel $SUBJECTS_DIR/fsaverage/label/rh.perirhinal_exvivo.thresh.label --trgsubject $SNAME --trglabel ./rh.perirhinal_exvivo.thresh.label --hemi rh --regmethod surface"
$cmd |& tee -a $LogFile
set cmd="mris_label2annot --s $SNAME --hemi rh --ctab $FREESURFER_HOME/average/colortable_BA.txt --l rh.BA1_exvivo.label --l rh.BA2_exvivo.label --l rh.BA3a_exvivo.label --l rh.BA3b_exvivo.label --l rh.BA4a_exvivo.label --l rh.BA4p_exvivo.label --l rh.BA6_exvivo.label --l rh.BA44_exvivo.label --l rh.BA45_exvivo.label --l rh.V1_exvivo.label --l rh.V2_exvivo.label --l rh.MT_exvivo.label --l rh.perirhinal_exvivo.label --l rh.entorhinal_exvivo.label --a BA_exvivo --maxstatwinner --noverbose"
$cmd |& tee -a $LogFile
set cmd="mris_label2annot --s $SNAME --hemi rh --ctab $FREESURFER_HOME/average/colortable_BA_thresh.txt --l rh.BA1_exvivo.thresh.label --l rh.BA2_exvivo.thresh.label --l rh.BA3a_exvivo.thresh.label --l rh.BA3b_exvivo.thresh.label --l rh.BA4a_exvivo.thresh.label --l rh.BA4p_exvivo.thresh.label --l rh.BA6_exvivo.thresh.label --l rh.BA44_exvivo.thresh.label --l rh.BA45_exvivo.thresh.label --l rh.V1_exvivo.thresh.label --l rh.V2_exvivo.thresh.label --l rh.MT_exvivo.thresh.label --l rh.perirhinal_exvivo.thresh.label --l rh.entorhinal_exvivo.thresh.label --a BA_exvivo.thresh --maxstatwinner --noverbose"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -f ../stats/rh.BA_exvivo.stats -b -a ./rh.BA_exvivo.annot -c ./BA_exvivo.ctab $SNAME rh white"
$cmd |& tee -a $LogFile
set cmd="mris_anatomical_stats -th3 -mgz -f ../stats/rh.BA_exvivo.thresh.stats -b -a ./rh.BA_exvivo.thresh.annot -c ./BA_exvivo.thresh.ctab $SNAME rh white"
$cmd |& tee -a $LogFile



# All done!
echo "All done!" >> $LogFile
rm -f $IsRunningFile

echo " "
echo "All done!"
echo " "
echo "If you have used results from this software for a publication, please cite:"
echo " "
echo "K Gopinath, DN Greeve, S Das, S Arnold, C Magdamo, JE Iglesias:"
echo "Cortical analysis of heterogeneous clinical brain MRI scans for large-scale neuroimaging studies"
echo "https://arxiv.org/abs/2305.01827"
echo " "
echo "B Billot, DN Greve, O Puonti, A Thielscher, K Van Leemput, B Fischl, AV Dalca, JE Iglesias:"
echo "SynthSeg: Segmentation of brain MRI scans of any contrast and resolution without retraining"
echo "Medical Image Analysis, 83, 102789 (2023)"
echo " "
echo "B Billot, C Magdamo, SE Arnold, S Das, JE Iglesias:"
echo "Robust machine learning segmentation for large-scale analysis of heterogeneous clinical brain MRI datasets"
echo "PNAS, 120(9), e2216399120 (2023)"
echo " "
echo "SynthSR: a public AI tool to turn heterogeneous clinical brain scans into high-resolution T1-weighted images for 3D morphometry"
echo "JE Iglesias, B Billot, Y Balbastre, C Magdamo, S Arnold, S Das, B Edlow, D Alexander, P Golland, B Fischl"
echo "Science Advances, 9(5), eadd3607 (2023)"
echo " "

exit 0