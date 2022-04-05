-- extract the diagnosis as well as the disease name for each patient
SELECT * 
FROM `physionet-data.mimic_hosp.diagnoses_icd` patient,
`physionet-data.mimic_hosp.d_icd_diagnoses` diag 
WHERE patient.icd_version = diag.icd_version and patient.icd_code = diag.icd_code
LIMIT 1000
