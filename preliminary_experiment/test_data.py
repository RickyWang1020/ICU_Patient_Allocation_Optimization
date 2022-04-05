### sample data ###

### number count of data ###
Pi = 5  # incoming patients
Pe = 10  # existing patients
R_icu = 20  # Number of ICU resources (beds)
R_noicu = 40  # Number of general impatient resources (beds)

### weights and percentages ###
Umax = 0.9  # ICU resource max usage (percentage)
w1 = 0.9
w2 = 0.5

### back-up parameters for programming ##
t = []  # bed turnaround time of ICU patients reallocation
xi = []  # possibilities of incoming patients going to different departments
xe = []  # possibilities of existing patients going to different departments
x = [xi, xe]

### The calculated expectation of treatment effectiveness of all the diseases (appeared in the data we use) ###
# for every key-value pair, the value is a list with 2 elements:
# the first one is death rate of historical patients in icu, the second is death rate of historical patients out of icu
Ep_d_icu_noicu = {"29410": [0.33, 0.2], "V1087": [0.5, 0.3], "4011": [0.7, 0.6], "E8497": [0.2, 0.35],
                  "7847": [0.7, 0.5], "25080": [0.5, 0.67], "78009": [0.56, 0.3], "30000": [0.32, 0.2],
                  "V163": [0.6, 0.4], "V1254": [0.24, 0.45],
                  "27482": [0.33, 0.25], "4275": [0.67, 0.8], "E9308": [0.45, 0.5], "V4589": [0.35, 0.7],
                  "87364": [0.65, 0.4], "E9283": [0.57, 0.59], "V0259": [0.7, 0.6], "E9330": [0.7, 0.3],
                  "2749": [0.5, 0.25], "E8780": [0.8, 0.9],
                  "V451": [0.4, 0.57], "79029": [0.4, 0.36], "V162": [0.7, 0.55], "56400": [0.34, 0.44]}

### 5 incoming patients ###
# this is extracted from `diagnoses_icd` join `d_icd_diagnoses`
incoming_patient_disease = {1: [{"subject_id": "1", "seq_num": "27", "icd_code": "29410", "icd_version": "9",
                                 "long_title": "Dementia in conditions classified elsewhere without behavioral disturbance"},
                                {"subject_id": "1", "seq_num": "28", "icd_code": "V1087", "icd_version": "9",
                                 "long_title": "Personal history of malignant neoplasm of thyroid"}],
                            2: [{"subject_id": "2", "seq_num": "36", "icd_code": "4011", "icd_version": "9",
                                 "long_title": "Benign essential hypertension"},
                                {"subject_id": "2", "seq_num": "27", "icd_code": "E8497", "icd_version": "9",
                                 "long_title": "Accidents occurring in residential institution"}],
                            3: [{"subject_id": "3", "seq_num": "26", "icd_code": "7847", "icd_version": "9",
                                 "long_title": "Epistaxis"},
                                {"subject_id": "3", "seq_num": "27", "icd_code": "25080", "icd_version": "9",
                                 "long_title": "Diabetes with other specified manifestations, type II or unspecified type, not stated as uncontrolled"}],
                            4: [{"subject_id": "4", "seq_num": "27", "icd_code": "78009", "icd_version": "9",
                                 "long_title": "Other alteration of consciousness"},
                                {"subject_id": "4", "seq_num": "26", "icd_code": "30000", "icd_version": "9",
                                 "long_title": "Anxiety state, unspecified"}],
                            5: [{"subject_id": "5", "seq_num": "26", "icd_code": "V163", "icd_version": "9",
                                 "long_title": "Family history of malignant neoplasm of breast"},
                                {"subject_id": "5", "seq_num": "25", "icd_code": "V1254", "icd_version": "9",
                                 "long_title": "Personal history of transient ischemic attack (TIA), and cerebral infarction without residual deficits"}]}

# this is extracted from `admissions`
incoming_patient_info = {1: {"age": 66}, 2: {"age": 35}, 3: {"age": 75}, 4: {"age": 58}, 5: {"age": 64}}

# sofa score of incoming patients, extracted from `mimic_derived`
s_i = [18, 19, 17, 10, 12]

### 10 existing patient in icu ###
# this is extracted from `diagnoses_icd` join `d_icd_diagnoses`
existing_patient_disease = {1: [{"subject_id": "6", "seq_num": "25", "icd_code": "27482", "icd_version": "9",
                                 "long_title": "Gouty tophi of other sites, except ear"},
                                {"subject_id": "6", "seq_num": "26", "icd_code": "4275", "icd_version": "9",
                                 "long_title": "Cardiac arrest"}],
                            2: [{"subject_id": "7", "seq_num": "27", "icd_code": "E9308", "icd_version": "9",
                                 "long_title": "Other specified antibiotics causing adverse effects in therapeutic use"},
                                {"subject_id": "7", "seq_num": "31", "icd_code": "V4589", "icd_version": "9",
                                 "long_title": "Other postprocedural status"}],
                            3: [{"subject_id": "8", "seq_num": "25", "icd_code": "87364", "icd_version": "9",
                                 "long_title": "Open wound of tongue and floor of mouth, without mention of complication"},
                                {"subject_id": "8", "seq_num": "26", "icd_code": "E9283", "icd_version": "9",
                                 "long_title": "Human bite"}],
                            4: [{"subject_id": "9", "seq_num": "39", "icd_code": "V1254", "icd_version": "9",
                                 "long_title": "Personal history of transient ischemic attack (TIA), and cerebral infarction without residual deficits"},
                                {"subject_id": "9", "seq_num": "35", "icd_code": "V0259", "icd_version": "9",
                                 "long_title": "Carrier or suspected carrier of other specified bacterial diseases"}],
                            5: [{"subject_id": "10", "seq_num": "25", "icd_code": "E9330", "icd_version": "9",
                                 "long_title": "Antiallergic and antiemetic drugs causing adverse effects in therapeutic use"},
                                {"subject_id": "10", "seq_num": "32", "icd_code": "2749", "icd_version": "9",
                                 "long_title": "Gout, unspecified"}],
                            6: [{"subject_id": "11", "seq_num": "25", "icd_code": "E8780", "icd_version": "9",
                                 "long_title": "Surgical operation with transplant of whole organ causing abnormal patient reaction, or later complication, without mention of misadventure at time of operation"}],
                            7: [{"subject_id": "12", "seq_num": "28", "icd_code": "V4589", "icd_version": "9",
                                 "long_title": "Other postprocedural status"}],
                            8: [{"subject_id": "13", "seq_num": "32", "icd_code": "V4589", "icd_version": "9",
                                 "long_title": "Other postprocedural status"},
                                {"subject_id": "13", "seq_num": "26", "icd_code": "V451", "icd_version": "9",
                                 "long_title": "Renal dialysis status"}],
                            9: [{"subject_id": "14", "seq_num": "26", "icd_code": "79029", "icd_version": "9",
                                 "long_title": "Other abnormal glucose"},
                                {"subject_id": "14", "seq_num": "32", "icd_code": "V162", "icd_version": "9",
                                 "long_title": "Family history of malignant neoplasm of other respiratory and intrathoracic organs"}],
                            10: [{"subject_id": "15", "seq_num": "26", "icd_code": "56400", "icd_version": "9",
                                  "long_title": "Constipation, unspecified"}]}

# this is extracted from `admissions`
existing_patient_info = {1: {"age": 63}, 2: {"age": 18}, 3: {"age": 38}, 4: {"age": 16}, 5: {"age": 69}, 6: {"age": 63},
                         7: {"age": 48}, 8: {"age": 38}, 9: {"age": 91}, 10: {"age": 46}}

# sofa score of existing patients, extracted from `mimic_derived`
s_e = [19, 21, 16, 24, 22, 18, 11, 10, 8, 21]
