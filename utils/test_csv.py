import pandas as pd

# set variables
subject_label = 'sub-001'
session_label = 'ses-001'
age = 25
PatientSex = 'M'
acquisition = 'T1w'
cleaned_string = 'sub-001_ses-001_T1w'

# assign values to lists. 
data = [{'subject': subject_label, 'session': session_label, 'age': age, 'sex': PatientSex, 'acquisition': acquisition }]  
# Creates DataFrame.  
demo = pd.DataFrame(data)

# Adjust the path as necessary
file_path = '/flywheel/v0/work/aparc_lh.csv'
# Use a space as the delimiter
lh_thickness = pd.read_csv(file_path, sep='\t', engine='python',index_col=None, header=0)
# Now df_space will have the columns correctly separated

# Adjust the path as necessary
file_path = '/flywheel/v0/work/aparc_rh.csv'
# Use a space as the delimiter
rh_thickness = pd.read_csv(file_path, sep='\t', engine='python', index_col=None, header=0)
# Now df_space will have the columns correctly separated



# smush the data together
frames = [demo, lh_thickness, rh_thickness]
df = pd.concat(frames, axis=1)
out_name = f"{cleaned_string}_thickness.csv"
outdir = ('/flywheel/v0/output/' + out_name)
df.to_csv(outdir)