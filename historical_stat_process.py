import json

def mapping_sofa_to_mortality(sofa_score):
    # statistics of sofa score mapping to mortality rate
    # 0 to 6	< 10%
    # 7 to 9	15 - 35%
    # 10 to 12	40 - 50%
    # 13 to 15	55 - 75%
    # 16 to 24	> 80%
    # we use a linear mapping
    assert 0 <= sofa_score <= 24
    if sofa_score == 0:
        mortality = 0
    elif 0 < sofa_score <= 6:
        mortality = 0.1 / 6 * sofa_score
    elif 7 <= sofa_score <= 9:
        mortality = 0.1 * sofa_score - 0.55
    elif 10 <= sofa_score <= 12:
        mortality = 0.05 * sofa_score - 0.1
    elif 13 <= sofa_score <= 15:
        mortality = 0.1 * sofa_score - 0.75
    else:
        mortality = 0.025 * sofa_score + 0.4
    return round(mortality, 3)

def process_and_save_hist_file(path, new_filename):
    file = open(path)
    newdata = {}
    for patient_data in file.readlines():
        patient = json.loads(patient_data)
        sid = patient["subject_id"]
        if sid not in newdata:
            newdata[sid] = {
                "icd_code": {},
                "age": patient["age"],
                "sofa": patient["sofa"],
                "mortality_by_sofa": mapping_sofa_to_mortality(int(patient["sofa"])),
                "death": patient["dead_flag"] # 0 means not dead, 1 means dead
            }
        if patient["icd_diagnose"] not in newdata[sid]["icd_code"]:
            newdata[sid]["icd_code"][patient["icd_diagnose"]] = patient["diagnose_priority"]
        newdata[sid]["result"] = patient["allocation_result"]

    file.close()
    with open(new_filename, 'w') as f:
        json.dump(newdata, f, ensure_ascii=False, indent=4)


def calculate_hist_patient_prob(path, new_filename):
    file = open(path)
    data = json.load(file)
    full_hist_data = {key: value for (key, value) in (list(data.items()))}
    # the diagnosis dictionary:
    # key is the icd_code of disease,
    # value is a 3-element array:
    # 1st element is the total number of patients with this disease,
    # 2nd element is the total number of dead patients with this disease,
    # 3rd element is the total sum of mortality_by_sofa of patients with this disease
    diagnosis_icu = {}
    diagnosis_inpatient = {}
    # put patients' diagnoses into the corresponding dictionary
    for patient_data in full_hist_data.values():
        current_diagnosis = patient_data["icd_code"]
        patient_death = int(patient_data["death"])
        # this patient belongs to icu
        if patient_data["result"] == "ICU":
            for diagnosis in current_diagnosis:
                if diagnosis in diagnosis_icu:
                    diagnosis_icu[diagnosis][0] += 1
                    diagnosis_icu[diagnosis][1] += patient_death
                    diagnosis_icu[diagnosis][2] += patient_data["mortality_by_sofa"]
                else:
                    diagnosis_icu[diagnosis] = [1, patient_death, patient_data["mortality_by_sofa"]]
        # this patient belongs to general inpatient units
        else:
            for diagnosis in current_diagnosis:
                if diagnosis in diagnosis_inpatient:
                    diagnosis_inpatient[diagnosis][0] += 1
                    diagnosis_inpatient[diagnosis][1] += patient_death
                    diagnosis_inpatient[diagnosis][2] += patient_data["mortality_by_sofa"]
                else:
                    diagnosis_inpatient[diagnosis] = [1, patient_death, patient_data["mortality_by_sofa"]]

    file.close()
    # print(diagnosis_icu)
    # print(diagnosis_inpatient)

    ep_icu_noicu = {}
    # the version that we round to 0 if the difference is negative
    # for k1, v1 in diagnosis_icu.items():
    #     if v1[2]-v1[1] < 0:
    #         ep_icu_noicu[k1] = [0, 0]
    #     else:
    #         ep_icu_noicu[k1] = [(v1[2]-v1[1])/v1[0], 0]
    # for k2, v2 in diagnosis_inpatient.items():
    #     if k2 in ep_icu_noicu:
    #         if v2[2]-v2[1] < 0:
    #             ep_icu_noicu[k2][1] = 0
    #         else:
    #             ep_icu_noicu[k2][1] = (v2[2]-v2[1])/v2[0]
    #     else:
    #         if v2[2]-v2[1] < 0:
    #             ep_icu_noicu[k2] = [0, 0]
    #         else:
    #             ep_icu_noicu[k2] = [0, (v2[2]-v2[1])/v2[0]]

    # the version that has no rounding
    for k1, v1 in diagnosis_icu.items():
        ep_icu_noicu[k1] = [(v1[2]-v1[1])/v1[0], 0]
    for k2, v2 in diagnosis_inpatient.items():
        if k2 in ep_icu_noicu:
            ep_icu_noicu[k2][1] = (v2[2]-v2[1])/v2[0]
        else:
            ep_icu_noicu[k2] = [0, (v2[2]-v2[1])/v2[0]]

    # print(ep_icu_noicu)
    with open(new_filename, 'w') as f:
        json.dump(ep_icu_noicu, f, ensure_ascii=False, indent=4)

if __name__ == "__main__":
    process_and_save_hist_file("historical.json", "newhistorydata.json")
    calculate_hist_patient_prob("newhistorydata.json", "epstats.json")
