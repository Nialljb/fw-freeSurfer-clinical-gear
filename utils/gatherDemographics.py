import flywheel
import json
import pandas as pd
from datetime import datetime
import re
import os

#  Module to identify the correct template use for the subject VBM analysis based on age at scan
#  Need to get subject identifiers from inside running container in order to find the correct template from the SDK

def get_demo(context):

    data = []
    age = []
    sex = []
    # Read config.json file
    p = open('/flywheel/v0/config.json')
    config = json.loads(p.read())

    # Read API key in config file
    api_key = (config['inputs']['api-key']['key'])
    fw = flywheel.Client(api_key=api_key)
    gear = 'synthseg'
    
    input_container = context.client.get_analysis(context.destination["id"])
    proj_id = input_container.parents["project"]
    project_container = context.client.get(proj_id)
    project_label = project_container.label
    print("project label: ", project_label)

    # Get the subject id from the session id
    # & extract the subject container
    subject_id = input_container.parents['subject']
    subject_container = context.client.get(subject_id)
    subject = subject_container.reload()
    print("subject label: ", subject.label)
    subject_label = subject.label

    # Get the session id from the input file id
    # & extract the session container
    session_id = input_container.parents['session']
    session_container = context.client.get(session_id)
    session = session_container.reload()
    session_label = session.label
    print("session label: ", session.label)


    # --- Specify the directory you want to list files from --- #

    directory_path = '/flywheel/v0/input/'
    # List all files in the specified directory
    for filename in os.listdir(directory_path):
        if os.path.isfile(os.path.join(directory_path, filename)):
            filename_without_extension = filename.split('.')[0]
            no_white_spaces = filename_without_extension.replace(" ", "")
            # no_white_spaces = filename.replace(" ", "")
            cleaned_string = re.sub(r'[^a-zA-Z0-9]', '_', no_white_spaces)
            cleaned_string = cleaned_string.rstrip('_') # remove trailing underscore

    print("cleaned_string: ", cleaned_string)

    # -------------------  Get the subject age & matching template  -------------------  #

    # get the T2w axi dicom acquisition from the session
    # Should contain the DOB in the dicom header
    # Some projects may have DOB removed, but may have age at scan in the subject container

    for acq in session_container.acquisitions.iter():
        # print(acq.label)
        acq = acq.reload()
        if 'T2' in acq.label and 'AXI' in acq.label and 'Segmentation' not in acq.label: 
            for file_obj in acq.files: # get the files in the acquisition
                # Screen file object information & download the desired file
                if file_obj['type'] == 'dicom':
                    
                    dicom_header = fw._fw.get_acquisition_file_info(acq.id, file_obj.name)
                    try:
                        PatientSex = dicom_header.info["PatientSex"]
                    except:
                        PatientSex = "NA"
                        continue
                    print("PatientSex: ", PatientSex)

                    if 'PatientBirthDate' in dicom_header.info:
                        # Get dates from dicom header
                        dob = dicom_header.info['PatientBirthDate']
                        seriesDate = dicom_header.info['SeriesDate']
                        # Calculate age at scan
                        age = (datetime.strptime(seriesDate, '%Y%m%d')) - (datetime.strptime(dob, '%Y%m%d'))
                        age = age.days
                    elif session.age != None: 
                        # 
                        print("Checking session infomation label...")
                        # print("session.age: ", session.age) 
                        age = int(session.age / 365 / 24 / 60 / 60) # This is in seconds
                    elif 'PatientAge' in dicom_header.info:
                        print("No DOB in dicom header or age in session info! Trying PatientAge from dicom...")
                        age = dicom_header.info['PatientAge']
                        # Need to drop the 'D' from the age and convert to int
                        age = re.sub('\D', '', age)
                        age = int(age)
                    else:
                        print("No age at scan in session info label! Ask PI...")
                        age = 0

                    if age == 0:
                        print("No age at scan - skipping")
                        exit(1)
                    # Make sure age is positive
                    elif age < 0:
                        age = age * -1
                    print("age: ", age)
    
    # assign values to lists. 
    data = [{'subject': subject_label, 'session': session_label, 'age': age, 'sex': PatientSex }]  
    # Creates DataFrame.  
    demo = pd.DataFrame(data)

    # Adapt to the synthseg output
    filePath = '/flywheel/v0/output/vol.csv'
    with open(filePath) as csv_file:
        vols = pd.read_csv(csv_file, index_col=None, header=0) 
        vols = vols.drop('subject', axis=1)

    frames = [demo, vols]
    df = pd.concat(frames, axis=1)

    # sub-{subject_label}_ses-{session_label}_acq-
    out_name = f"{cleaned_string}_synthseg_{infant}volumes.csv"
    outdir = ('/flywheel/v0/output/' + out_name)
    df.to_csv(outdir)


  
    print("Demographics: ", subject_label, session_label, age, PatientSex)
    return subject_label, session_label, age, PatientSex




