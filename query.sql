-- Step 1: select a suitable date
-- get the corresponding day(s) with given number of admissions
-- and we will manually select one day(or a period) from these days
WITH date_admission_count AS
(SELECT DATE(admissions.admittime) AS day, COUNT(*) AS num 
FROM `physionet-data.mimic_core.admissions` admissions, `physionet-data.mimic_core.patients` patient
WHERE admissions.subject_id = patient.subject_id
GROUP BY DATE(admissions.admittime))

SELECT *
FROM date_admission_count
WHERE num = 16
ORDER BY day DESC;

-- Step 2: extract the incoming patients for that date
-- helper: select all the incoming patients' entries, as well as their info
SELECT DISTINCT admissions.subject_id AS subject_id, 
    DATE(admissions.admittime) AS admit_day, 
    patient.anchor_age AS age, 
    admissions.admission_type AS admission_type, 
    diagnoses.icd_version AS icd_version, 
    diagnoses.icd_code AS icd_diagnose,
    diagnoses.seq_num AS diagnose_priority,
    admissions.hospital_expire_flag AS dead_flag, 
    admissions.deathtime AS death_time
FROM `physionet-data.mimic_core.admissions` admissions JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
WHERE DATE(admissions.admittime) = '2190-06-06'
ORDER BY subject_id, diagnose_priority;

-- helper: can use this to check how many diagnoses each incoming patient has
WITH transfer_log AS
(
    SELECT DISTINCT admissions.subject_id AS subject_id,
        DATE(admissions.admittime) AS admit_day, 
        diagnoses.icd_code AS icd_diagnose, 
        diagnoses.seq_num AS diagnose_priority, 
        admissions.hospital_expire_flag AS dead_flag
    FROM `physionet-data.mimic_core.admissions` admissions JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
    WHERE DATE(admissions.admittime) = '2190-06-06'
    ORDER BY subject_id
)

SELECT subject_id, COUNT(*)
FROM transfer_log
GROUP BY subject_id;

-- this is the real query for getting the incoming patient's information, as well as the patient's real allocation result, for future checking
WITH transfer_log AS
(
    SELECT * 
    FROM `physionet-data.mimic_core.transfers` transf
    WHERE transf.eventtype = 'admit'
    ORDER BY transf.subject_id
),
icu_transfer_log AS
(
    SELECT DISTINCT transf.subject_id
    FROM `physionet-data.mimic_core.transfers` transf
    WHERE transf.eventtype = 'admit'
    AND transf.careunit LIKE '%ICU%'
    ORDER BY transf.subject_id
)

SELECT DISTINCT admissions.subject_id AS subject_id,
    DATE(admissions.admittime) AS admit_day, 
    patient.anchor_age AS age,
    admissions.admission_type AS admission_type,
    diagnoses.icd_version AS icd_version,
    diagnoses.icd_code AS icd_diagnose,
    diagnoses.seq_num AS diagnose_priority,
    admissions.hospital_expire_flag AS dead_flag, 
    admissions.deathtime AS death_time,
    CASE WHEN (admissions.subject_id in (SELECT subject_id FROM icu_transfer_log)) THEN 'ICU' ELSE 'INPATIENT' END AS allocation_result
FROM `physionet-data.mimic_core.admissions` admissions JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
WHERE DATE(admissions.admittime) = '2190-06-06'
ORDER BY subject_id;

-- Step 3: extract existing patients on that selected day, as well as their allocation results
-- existing patients: admit time is earlier than this day, but discharge time is later than this day
-- similar to the step 2
WITH transfer_log AS
(
    SELECT * 
    FROM `physionet-data.mimic_core.transfers` transf
    WHERE transf.eventtype = 'admit'
    ORDER BY transf.subject_id
),
icu_transfer_log AS
(
    SELECT DISTINCT transf.subject_id
    FROM `physionet-data.mimic_core.transfers` transf
    WHERE transf.eventtype = 'admit'
    AND transf.careunit LIKE '%ICU%'
    ORDER BY transf.subject_id
)

SELECT DISTINCT admissions.subject_id AS subject_id, 
    DATE(admissions.admittime) AS admit_day, 
    DATE(admissions.dischtime) AS discharge_day, 
    patient.anchor_age AS age, 
    admissions.admission_type AS admission_type, 
    diagnoses.icd_version AS icd_version, 
    diagnoses.icd_code AS icd_diagnose,
    diagnoses.seq_num AS diagnose_priority,
    admissions.hospital_expire_flag AS dead_flag, 
    admissions.deathtime AS death_time,
    CASE WHEN (admissions.subject_id in (SELECT subject_id FROM icu_transfer_log)) THEN 'ICU' ELSE 'INPATIENT' END AS allocation_result
FROM `physionet-data.mimic_core.admissions` admissions JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
WHERE DATE(admissions.admittime) < '2190-06-06' AND DATE(admissions.dischtime) >= '2190-06-06'
ORDER BY subject_id;

-- Step 4: extract the information for all the historical patients
-- historical patients are for calculating the E score, they have discharge time earlier than this day
-- helper: check how many ICU and INPATIENT respectively in historical patients
WITH icu_transfer_log AS
(
    SELECT DISTINCT transf.subject_id
    FROM `physionet-data.mimic_core.transfers` transf
    WHERE transf.eventtype = 'admit'
    AND transf.careunit LIKE '%ICU%'
    ORDER BY transf.subject_id
),
historic AS
(
SELECT DISTINCT admissions.subject_id AS subject_id, 
    DATE(admissions.admittime) AS admit_day, 
    DATE(admissions.dischtime) AS discharge_day, 
    patient.anchor_age AS age, 
    admissions.admission_type AS admission_type, 
    diagnoses.icd_version AS icd_version, 
    diagnoses.icd_code AS icd_diagnose,
    diagnoses.seq_num AS diagnose_priority,
    admissions.hospital_expire_flag AS dead_flag, 
    admissions.deathtime AS death_time,
    CASE WHEN (admissions.subject_id in (SELECT subject_id FROM icu_transfer_log)) THEN 'ICU' ELSE 'INPATIENT' END AS allocation_result
FROM `physionet-data.mimic_core.admissions` admissions JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
WHERE DATE(admissions.dischtime) < '2190-06-06'
ORDER BY subject_id
)

SELECT allocation_result, COUNT(*)
FROM historic
GROUP BY allocation_result;

-- this is the main query for getting historic patient's diagnoses, diagnoses priorities, death condition, allocation result (ICU or not?)
WITH icu_transfer_log AS
(
    SELECT DISTINCT transf.subject_id
    FROM `physionet-data.mimic_core.transfers` transf
    WHERE transf.eventtype = 'admit'
    AND transf.careunit LIKE '%ICU%'
    ORDER BY transf.subject_id
)

SELECT DISTINCT admissions.subject_id AS subject_id, 
    DATE(admissions.admittime) AS admit_day, 
    DATE(admissions.dischtime) AS discharge_day, 
    patient.anchor_age AS age, 
    admissions.admission_type AS admission_type, 
    diagnoses.icd_version AS icd_version, 
    diagnoses.icd_code AS icd_diagnose,
    diagnoses.seq_num AS diagnose_priority,
    admissions.hospital_expire_flag AS dead_flag, 
    admissions.deathtime AS death_time,
    CASE WHEN (admissions.subject_id in (SELECT subject_id FROM icu_transfer_log)) THEN 'ICU' ELSE 'INPATIENT' END AS allocation_result
FROM `physionet-data.mimic_core.admissions` admissions JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
WHERE DATE(admissions.dischtime) < '2190-06-06'
ORDER BY subject_id;


