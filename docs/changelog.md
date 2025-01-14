# Changelog
14/01/2025
Version 0.4.0
- Added fix for potential `recon-all` error
- Added in segmentation & SynthSR output for QC

11/07/2024
Version 0.3.0
- Made changes to make the ouputs more BIDS compliant
- Setup cortical thickness output
- Zipped output for easier debugging
NOTE:
- Major changes implemented, need to test thoroughly

10/07/2024
Version 0.2.9
- Successfully run
NOTE:
- Amend outputs name to comply with BIDS standard
- Parse demographics into the summary output csv file (include other derivatives?)
- Add in render function for quick visualisation of outputs


10/07/2024:
Version 0.2.3 

- Need to install tcsh & additional dependencies for recon-all to work
- Updated interactive script
- Set up zipped output for debugging


10/07/2024:
Version 0.2.3 

- Major rebuild of OS and dependencies (CENTOS 9 Stream)
- Refactoring of codebase
- Updated description
- Cleaned up structure

30/06/2024:
Corrected bug in main script that prevented QC file from being generated. 