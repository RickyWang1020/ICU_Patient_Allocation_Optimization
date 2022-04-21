-- In this version, only consider ICD-9 diagnoses

-- Step 1: select a suitable date
-- get the corresponding day(s) with given number of admissions
-- and we will manually select one day(or a period) from these days

WITH icd9_patient AS
(
    SELECT DISTINCT admissions.subject_id AS subject_id, 
    DATE(admissions.admittime) AS admit_day
    FROM `physionet-data.mimic_core.admissions` admissions 
    JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) 
    JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
    WHERE icd_version = 9
),
date_admission_count AS
(
    SELECT admit_day, COUNT(*) AS num 
    FROM icd9_patient
    GROUP BY admit_day
)

SELECT *
FROM date_admission_count
WHERE num = 12
ORDER BY admit_day DESC;

-- Step 2: extract the incoming patients for that date

with vaso_stg as
(
  select ie.stay_id, 'norepinephrine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.norepinephrine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'epinephrine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.epinephrine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'dobutamine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.dobutamine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'dopamine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.dopamine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
)
, vaso_mv AS
(
    SELECT
    ie.stay_id
    , max(CASE WHEN treatment = 'norepinephrine' THEN rate ELSE NULL END) as rate_norepinephrine
    , max(CASE WHEN treatment = 'epinephrine' THEN rate ELSE NULL END) as rate_epinephrine
    , max(CASE WHEN treatment = 'dopamine' THEN rate ELSE NULL END) as rate_dopamine
    , max(CASE WHEN treatment = 'dobutamine' THEN rate ELSE NULL END) as rate_dobutamine
  from `physionet-data.mimic_icu.icustays` ie
  LEFT JOIN vaso_stg v
      ON ie.stay_id = v.stay_id
  GROUP BY ie.stay_id
)
, pafi1 as
(
  -- join blood gas to ventilation durations to determine if patient was vent
  select ie.stay_id, bg.charttime
  , bg.pao2fio2ratio
  , case when vd.stay_id is not null then 1 else 0 end as IsVent
  from `physionet-data.mimic_icu.icustays` ie
  LEFT JOIN `physionet-data.mimic_derived.bg` bg
      ON ie.subject_id = bg.subject_id
      AND bg.charttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
      AND bg.charttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  LEFT JOIN `physionet-data.mimic_derived.ventilation` vd
    ON ie.stay_id = vd.stay_id
    AND bg.charttime >= vd.starttime
    AND bg.charttime <= vd.endtime
    AND vd.ventilation_status = 'InvasiveVent'
)
, pafi2 as
(
  -- because pafi has an interaction between vent/PaO2:FiO2, we need two columns for the score
  -- it can happen that the lowest unventilated PaO2/FiO2 is 68, but the lowest ventilated PaO2/FiO2 is 120
  -- in this case, the SOFA score is 3, *not* 4.
  select stay_id
  , min(case when IsVent = 0 then pao2fio2ratio else null end) as PaO2FiO2_novent_min
  , min(case when IsVent = 1 then pao2fio2ratio else null end) as PaO2FiO2_vent_min
  from pafi1
  group by stay_id
)
-- Aggregate the components for the score
, scorecomp as
(
select ie.stay_id
  , v.mbp_min
  , mv.rate_norepinephrine
  , mv.rate_epinephrine
  , mv.rate_dopamine
  , mv.rate_dobutamine

  , l.creatinine_max
  , l.bilirubin_total_max as bilirubin_max
  , l.platelets_min as platelet_min

  , pf.PaO2FiO2_novent_min
  , pf.PaO2FiO2_vent_min

  , uo.UrineOutput

  , gcs.gcs_min
from `physionet-data.mimic_icu.icustays` ie
left join vaso_mv mv
  on ie.stay_id = mv.stay_id
left join pafi2 pf
 on ie.stay_id = pf.stay_id
left join `physionet-data.mimic_derived.first_day_vitalsign` v
  on ie.stay_id = v.stay_id
left join `physionet-data.mimic_derived.first_day_lab` l
  on ie.stay_id = l.stay_id
left join `physionet-data.mimic_derived.first_day_urine_output` uo
  on ie.stay_id = uo.stay_id
left join `physionet-data.mimic_derived.first_day_gcs` gcs
  on ie.stay_id = gcs.stay_id
)
, scorecalc as
(
  -- Calculate the final score
  -- note that if the underlying data is missing, the component is null
  -- eventually these are treated as 0 (normal), but knowing when data is missing is useful for debugging
  select stay_id
  -- Respiration
  , case
      when PaO2FiO2_vent_min   < 100 then 4
      when PaO2FiO2_vent_min   < 200 then 3
      when PaO2FiO2_novent_min < 300 then 2
      when PaO2FiO2_novent_min < 400 then 1
      when coalesce(PaO2FiO2_vent_min, PaO2FiO2_novent_min) is null then null
      else 0
    end as respiration

  -- Coagulation
  , case
      when platelet_min < 20  then 4
      when platelet_min < 50  then 3
      when platelet_min < 100 then 2
      when platelet_min < 150 then 1
      when platelet_min is null then null
      else 0
    end as coagulation

  -- Liver
  , case
      -- Bilirubin checks in mg/dL
        when bilirubin_max >= 12.0 then 4
        when bilirubin_max >= 6.0  then 3
        when bilirubin_max >= 2.0  then 2
        when bilirubin_max >= 1.2  then 1
        when bilirubin_max is null then null
        else 0
      end as liver

  -- Cardiovascular
  , case
      when rate_dopamine > 15 or rate_epinephrine >  0.1 or rate_norepinephrine >  0.1 then 4
      when rate_dopamine >  5 or rate_epinephrine <= 0.1 or rate_norepinephrine <= 0.1 then 3
      when rate_dopamine >  0 or rate_dobutamine > 0 then 2
      when mbp_min < 70 then 1
      when coalesce(mbp_min, rate_dopamine, rate_dobutamine, rate_epinephrine, rate_norepinephrine) is null then null
      else 0
    end as cardiovascular

  -- Neurological failure (GCS)
  , case
      when (gcs_min >= 13 and gcs_min <= 14) then 1
      when (gcs_min >= 10 and gcs_min <= 12) then 2
      when (gcs_min >=  6 and gcs_min <=  9) then 3
      when  gcs_min <   6 then 4
      when  gcs_min is null then null
  else 0 end
    as cns

  -- Renal failure - high creatinine or low urine output
  , case
    when (creatinine_max >= 5.0) then 4
    when  UrineOutput < 200 then 4
    when (creatinine_max >= 3.5 and creatinine_max < 5.0) then 3
    when  UrineOutput < 500 then 3
    when (creatinine_max >= 2.0 and creatinine_max < 3.5) then 2
    when (creatinine_max >= 1.2 and creatinine_max < 2.0) then 1
    when coalesce(UrineOutput, creatinine_max) is null then null
  else 0 end
    as renal
  from scorecomp
),
patient_sofa AS
(
    select ie.subject_id, ie.hadm_id, ie.stay_id
    -- Combine all the scores to get SOFA
    -- Impute 0 if the score is missing
    , coalesce(respiration,0)
    + coalesce(coagulation,0)
    + coalesce(liver,0)
    + coalesce(cardiovascular,0)
    + coalesce(cns,0)
    + coalesce(renal,0)
    as SOFA
    , respiration
    , coagulation
    , liver
    , cardiovascular
    , cns
    , renal
    from `physionet-data.mimic_icu.icustays` ie
    left join scorecalc s
    on ie.stay_id = s.stay_id
),
patient_sofa_corrected AS
(
    SELECT subject_id, MAX(SOFA) AS sofa
    FROM patient_sofa
    GROUP BY subject_id
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
    diagnoses.icd_code AS icd_diagnose,
    diagnoses.seq_num AS diagnose_priority,
    CASE WHEN patient_sofa_corrected.sofa IS NULL THEN 1 ELSE patient_sofa_corrected.sofa END AS sofa, 
    CASE WHEN (admissions.subject_id in (SELECT subject_id FROM icu_transfer_log)) THEN 'ICU' ELSE 'INPATIENT' END AS allocation_result
FROM `physionet-data.mimic_core.admissions` admissions 
JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) 
JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
LEFT OUTER JOIN patient_sofa_corrected ON (admissions.subject_id = patient_sofa_corrected.subject_id)
WHERE DATE(admissions.admittime) = '2190-12-12' AND icd_version = 9
ORDER BY subject_id, icd_diagnose, diagnose_priority;


-- Step 3: extract existing patients on that selected day, as well as their allocation results
-- existing patients: admit time is earlier than this day, but discharge time is later than this day
-- similar to the step 2

with vaso_stg as
(
  select ie.stay_id, 'norepinephrine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.norepinephrine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'epinephrine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.epinephrine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'dobutamine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.dobutamine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'dopamine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.dopamine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
)
, vaso_mv AS
(
    SELECT
    ie.stay_id
    , max(CASE WHEN treatment = 'norepinephrine' THEN rate ELSE NULL END) as rate_norepinephrine
    , max(CASE WHEN treatment = 'epinephrine' THEN rate ELSE NULL END) as rate_epinephrine
    , max(CASE WHEN treatment = 'dopamine' THEN rate ELSE NULL END) as rate_dopamine
    , max(CASE WHEN treatment = 'dobutamine' THEN rate ELSE NULL END) as rate_dobutamine
  from `physionet-data.mimic_icu.icustays` ie
  LEFT JOIN vaso_stg v
      ON ie.stay_id = v.stay_id
  GROUP BY ie.stay_id
)
, pafi1 as
(
  -- join blood gas to ventilation durations to determine if patient was vent
  select ie.stay_id, bg.charttime
  , bg.pao2fio2ratio
  , case when vd.stay_id is not null then 1 else 0 end as IsVent
  from `physionet-data.mimic_icu.icustays` ie
  LEFT JOIN `physionet-data.mimic_derived.bg` bg
      ON ie.subject_id = bg.subject_id
      AND bg.charttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
      AND bg.charttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  LEFT JOIN `physionet-data.mimic_derived.ventilation` vd
    ON ie.stay_id = vd.stay_id
    AND bg.charttime >= vd.starttime
    AND bg.charttime <= vd.endtime
    AND vd.ventilation_status = 'InvasiveVent'
)
, pafi2 as
(
  -- because pafi has an interaction between vent/PaO2:FiO2, we need two columns for the score
  -- it can happen that the lowest unventilated PaO2/FiO2 is 68, but the lowest ventilated PaO2/FiO2 is 120
  -- in this case, the SOFA score is 3, *not* 4.
  select stay_id
  , min(case when IsVent = 0 then pao2fio2ratio else null end) as PaO2FiO2_novent_min
  , min(case when IsVent = 1 then pao2fio2ratio else null end) as PaO2FiO2_vent_min
  from pafi1
  group by stay_id
)
-- Aggregate the components for the score
, scorecomp as
(
select ie.stay_id
  , v.mbp_min
  , mv.rate_norepinephrine
  , mv.rate_epinephrine
  , mv.rate_dopamine
  , mv.rate_dobutamine

  , l.creatinine_max
  , l.bilirubin_total_max as bilirubin_max
  , l.platelets_min as platelet_min

  , pf.PaO2FiO2_novent_min
  , pf.PaO2FiO2_vent_min

  , uo.UrineOutput

  , gcs.gcs_min
from `physionet-data.mimic_icu.icustays` ie
left join vaso_mv mv
  on ie.stay_id = mv.stay_id
left join pafi2 pf
 on ie.stay_id = pf.stay_id
left join `physionet-data.mimic_derived.first_day_vitalsign` v
  on ie.stay_id = v.stay_id
left join `physionet-data.mimic_derived.first_day_lab` l
  on ie.stay_id = l.stay_id
left join `physionet-data.mimic_derived.first_day_urine_output` uo
  on ie.stay_id = uo.stay_id
left join `physionet-data.mimic_derived.first_day_gcs` gcs
  on ie.stay_id = gcs.stay_id
)
, scorecalc as
(
  -- Calculate the final score
  -- note that if the underlying data is missing, the component is null
  -- eventually these are treated as 0 (normal), but knowing when data is missing is useful for debugging
  select stay_id
  -- Respiration
  , case
      when PaO2FiO2_vent_min   < 100 then 4
      when PaO2FiO2_vent_min   < 200 then 3
      when PaO2FiO2_novent_min < 300 then 2
      when PaO2FiO2_novent_min < 400 then 1
      when coalesce(PaO2FiO2_vent_min, PaO2FiO2_novent_min) is null then null
      else 0
    end as respiration

  -- Coagulation
  , case
      when platelet_min < 20  then 4
      when platelet_min < 50  then 3
      when platelet_min < 100 then 2
      when platelet_min < 150 then 1
      when platelet_min is null then null
      else 0
    end as coagulation

  -- Liver
  , case
      -- Bilirubin checks in mg/dL
        when bilirubin_max >= 12.0 then 4
        when bilirubin_max >= 6.0  then 3
        when bilirubin_max >= 2.0  then 2
        when bilirubin_max >= 1.2  then 1
        when bilirubin_max is null then null
        else 0
      end as liver

  -- Cardiovascular
  , case
      when rate_dopamine > 15 or rate_epinephrine >  0.1 or rate_norepinephrine >  0.1 then 4
      when rate_dopamine >  5 or rate_epinephrine <= 0.1 or rate_norepinephrine <= 0.1 then 3
      when rate_dopamine >  0 or rate_dobutamine > 0 then 2
      when mbp_min < 70 then 1
      when coalesce(mbp_min, rate_dopamine, rate_dobutamine, rate_epinephrine, rate_norepinephrine) is null then null
      else 0
    end as cardiovascular

  -- Neurological failure (GCS)
  , case
      when (gcs_min >= 13 and gcs_min <= 14) then 1
      when (gcs_min >= 10 and gcs_min <= 12) then 2
      when (gcs_min >=  6 and gcs_min <=  9) then 3
      when  gcs_min <   6 then 4
      when  gcs_min is null then null
  else 0 end
    as cns

  -- Renal failure - high creatinine or low urine output
  , case
    when (creatinine_max >= 5.0) then 4
    when  UrineOutput < 200 then 4
    when (creatinine_max >= 3.5 and creatinine_max < 5.0) then 3
    when  UrineOutput < 500 then 3
    when (creatinine_max >= 2.0 and creatinine_max < 3.5) then 2
    when (creatinine_max >= 1.2 and creatinine_max < 2.0) then 1
    when coalesce(UrineOutput, creatinine_max) is null then null
  else 0 end
    as renal
  from scorecomp
),
patient_sofa AS
(
    select ie.subject_id, ie.hadm_id, ie.stay_id
    -- Combine all the scores to get SOFA
    -- Impute 0 if the score is missing
    , coalesce(respiration,0)
    + coalesce(coagulation,0)
    + coalesce(liver,0)
    + coalesce(cardiovascular,0)
    + coalesce(cns,0)
    + coalesce(renal,0)
    as SOFA
    , respiration
    , coagulation
    , liver
    , cardiovascular
    , cns
    , renal
    from `physionet-data.mimic_icu.icustays` ie
    left join scorecalc s
    on ie.stay_id = s.stay_id
),
patient_sofa_corrected AS
(
    SELECT subject_id, MAX(SOFA) AS sofa
    FROM patient_sofa
    GROUP BY subject_id
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
    diagnoses.icd_code AS icd_diagnose,
    diagnoses.seq_num AS diagnose_priority,
    CASE WHEN patient_sofa_corrected.sofa IS NULL THEN 1 ELSE patient_sofa_corrected.sofa END AS sofa,
    CASE WHEN (admissions.subject_id in (SELECT subject_id FROM icu_transfer_log)) THEN 'ICU' ELSE 'INPATIENT' END AS allocation_result
FROM `physionet-data.mimic_core.admissions` admissions 
JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) 
JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
LEFT OUTER JOIN patient_sofa_corrected ON (admissions.subject_id = patient_sofa_corrected.subject_id)
WHERE DATE(admissions.admittime) < '2190-12-12' AND DATE(admissions.dischtime) >= '2190-12-12' AND icd_version = 9
ORDER BY subject_id, icd_diagnose, diagnose_priority;

-- Step 4: extract the information for all the historical patients
-- historical patients are for calculating the E score, they have discharge time earlier than this day
-- this is the main query for getting historic patient's diagnoses, diagnoses priorities, death condition, allocation result (ICU or not?)
with vaso_stg as
(
  select ie.stay_id, 'norepinephrine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.norepinephrine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'epinephrine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.epinephrine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'dobutamine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.dobutamine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  UNION ALL
  select ie.stay_id, 'dopamine' AS treatment, vaso_rate as rate
  FROM `physionet-data.mimic_icu.icustays` ie
  INNER JOIN `physionet-data.mimic_derived.dopamine` mv
    ON ie.stay_id = mv.stay_id
    AND mv.starttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
    AND mv.starttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
)
, vaso_mv AS
(
    SELECT
    ie.stay_id
    , max(CASE WHEN treatment = 'norepinephrine' THEN rate ELSE NULL END) as rate_norepinephrine
    , max(CASE WHEN treatment = 'epinephrine' THEN rate ELSE NULL END) as rate_epinephrine
    , max(CASE WHEN treatment = 'dopamine' THEN rate ELSE NULL END) as rate_dopamine
    , max(CASE WHEN treatment = 'dobutamine' THEN rate ELSE NULL END) as rate_dobutamine
  from `physionet-data.mimic_icu.icustays` ie
  LEFT JOIN vaso_stg v
      ON ie.stay_id = v.stay_id
  GROUP BY ie.stay_id
)
, pafi1 as
(
  -- join blood gas to ventilation durations to determine if patient was vent
  select ie.stay_id, bg.charttime
  , bg.pao2fio2ratio
  , case when vd.stay_id is not null then 1 else 0 end as IsVent
  from `physionet-data.mimic_icu.icustays` ie
  LEFT JOIN `physionet-data.mimic_derived.bg` bg
      ON ie.subject_id = bg.subject_id
      AND bg.charttime >= DATETIME_SUB(ie.intime, INTERVAL '6' HOUR)
      AND bg.charttime <= DATETIME_ADD(ie.intime, INTERVAL '1' DAY)
  LEFT JOIN `physionet-data.mimic_derived.ventilation` vd
    ON ie.stay_id = vd.stay_id
    AND bg.charttime >= vd.starttime
    AND bg.charttime <= vd.endtime
    AND vd.ventilation_status = 'InvasiveVent'
)
, pafi2 as
(
  -- because pafi has an interaction between vent/PaO2:FiO2, we need two columns for the score
  -- it can happen that the lowest unventilated PaO2/FiO2 is 68, but the lowest ventilated PaO2/FiO2 is 120
  -- in this case, the SOFA score is 3, *not* 4.
  select stay_id
  , min(case when IsVent = 0 then pao2fio2ratio else null end) as PaO2FiO2_novent_min
  , min(case when IsVent = 1 then pao2fio2ratio else null end) as PaO2FiO2_vent_min
  from pafi1
  group by stay_id
)
-- Aggregate the components for the score
, scorecomp as
(
select ie.stay_id
  , v.mbp_min
  , mv.rate_norepinephrine
  , mv.rate_epinephrine
  , mv.rate_dopamine
  , mv.rate_dobutamine

  , l.creatinine_max
  , l.bilirubin_total_max as bilirubin_max
  , l.platelets_min as platelet_min

  , pf.PaO2FiO2_novent_min
  , pf.PaO2FiO2_vent_min

  , uo.UrineOutput

  , gcs.gcs_min
from `physionet-data.mimic_icu.icustays` ie
left join vaso_mv mv
  on ie.stay_id = mv.stay_id
left join pafi2 pf
 on ie.stay_id = pf.stay_id
left join `physionet-data.mimic_derived.first_day_vitalsign` v
  on ie.stay_id = v.stay_id
left join `physionet-data.mimic_derived.first_day_lab` l
  on ie.stay_id = l.stay_id
left join `physionet-data.mimic_derived.first_day_urine_output` uo
  on ie.stay_id = uo.stay_id
left join `physionet-data.mimic_derived.first_day_gcs` gcs
  on ie.stay_id = gcs.stay_id
)
, scorecalc as
(
  -- Calculate the final score
  -- note that if the underlying data is missing, the component is null
  -- eventually these are treated as 0 (normal), but knowing when data is missing is useful for debugging
  select stay_id
  -- Respiration
  , case
      when PaO2FiO2_vent_min   < 100 then 4
      when PaO2FiO2_vent_min   < 200 then 3
      when PaO2FiO2_novent_min < 300 then 2
      when PaO2FiO2_novent_min < 400 then 1
      when coalesce(PaO2FiO2_vent_min, PaO2FiO2_novent_min) is null then null
      else 0
    end as respiration

  -- Coagulation
  , case
      when platelet_min < 20  then 4
      when platelet_min < 50  then 3
      when platelet_min < 100 then 2
      when platelet_min < 150 then 1
      when platelet_min is null then null
      else 0
    end as coagulation

  -- Liver
  , case
      -- Bilirubin checks in mg/dL
        when bilirubin_max >= 12.0 then 4
        when bilirubin_max >= 6.0  then 3
        when bilirubin_max >= 2.0  then 2
        when bilirubin_max >= 1.2  then 1
        when bilirubin_max is null then null
        else 0
      end as liver

  -- Cardiovascular
  , case
      when rate_dopamine > 15 or rate_epinephrine >  0.1 or rate_norepinephrine >  0.1 then 4
      when rate_dopamine >  5 or rate_epinephrine <= 0.1 or rate_norepinephrine <= 0.1 then 3
      when rate_dopamine >  0 or rate_dobutamine > 0 then 2
      when mbp_min < 70 then 1
      when coalesce(mbp_min, rate_dopamine, rate_dobutamine, rate_epinephrine, rate_norepinephrine) is null then null
      else 0
    end as cardiovascular

  -- Neurological failure (GCS)
  , case
      when (gcs_min >= 13 and gcs_min <= 14) then 1
      when (gcs_min >= 10 and gcs_min <= 12) then 2
      when (gcs_min >=  6 and gcs_min <=  9) then 3
      when  gcs_min <   6 then 4
      when  gcs_min is null then null
  else 0 end
    as cns

  -- Renal failure - high creatinine or low urine output
  , case
    when (creatinine_max >= 5.0) then 4
    when  UrineOutput < 200 then 4
    when (creatinine_max >= 3.5 and creatinine_max < 5.0) then 3
    when  UrineOutput < 500 then 3
    when (creatinine_max >= 2.0 and creatinine_max < 3.5) then 2
    when (creatinine_max >= 1.2 and creatinine_max < 2.0) then 1
    when coalesce(UrineOutput, creatinine_max) is null then null
  else 0 end
    as renal
  from scorecomp
),
patient_sofa AS
(
    select ie.subject_id, ie.hadm_id, ie.stay_id
    -- Combine all the scores to get SOFA
    -- Impute 0 if the score is missing
    , coalesce(respiration,0)
    + coalesce(coagulation,0)
    + coalesce(liver,0)
    + coalesce(cardiovascular,0)
    + coalesce(cns,0)
    + coalesce(renal,0)
    as SOFA
    , respiration
    , coagulation
    , liver
    , cardiovascular
    , cns
    , renal
    from `physionet-data.mimic_icu.icustays` ie
    left join scorecalc s
    on ie.stay_id = s.stay_id
),
patient_sofa_corrected AS
(
    SELECT subject_id, MAX(SOFA) AS sofa
    FROM patient_sofa
    GROUP BY subject_id
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
    patient.anchor_age AS age, 
    diagnoses.icd_code AS icd_diagnose,
    diagnoses.seq_num AS diagnose_priority,
    admissions.hospital_expire_flag AS dead_flag, 
    admissions.deathtime AS death_time,
    CASE WHEN patient_sofa_corrected.sofa IS NULL THEN 1 ELSE patient_sofa_corrected.sofa END AS sofa,
    CASE WHEN (admissions.subject_id in (SELECT subject_id FROM icu_transfer_log)) THEN 'ICU' ELSE 'INPATIENT' END AS allocation_result
FROM `physionet-data.mimic_core.admissions` admissions 
JOIN `physionet-data.mimic_core.patients` patient ON (admissions.subject_id = patient.subject_id) 
JOIN `physionet-data.mimic_hosp.diagnoses_icd` diagnoses ON (admissions.subject_id = diagnoses.subject_id)
LEFT OUTER JOIN patient_sofa_corrected ON (admissions.subject_id = patient_sofa_corrected.subject_id)
WHERE DATE(admissions.dischtime) < '2190-12-12' AND icd_version = 9
ORDER BY subject_id, icd_diagnose, diagnose_priority;

