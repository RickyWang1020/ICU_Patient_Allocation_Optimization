import json
import random

def process(type, data):
    newdata = {}
    for patient in data:
        sid = patient["subject_id"]
        #type == 0: # incoming patients
        if sid not in newdata:
            newdata[sid] = {
                "status": type,
                "icd_code": {},
                "age": patient["age"],
                "SOFA": int(patient["sofa"]) #,random.randint(1, 24)
            }
        if type == 1 and patient["allocation_result"] == "INPATIENT": # existing patients
            newdata[sid]["status"] = 2 # existing patient in inpatient departments
        newdata[sid]["result"] = patient["allocation_result"]
        if patient["icd_diagnose"] not in newdata[sid]["icd_code"]:
            newdata[sid]["icd_code"][patient["icd_diagnose"]] = patient["diagnose_priority"]


    return newdata

if __name__ == "__main__":

    file = open('EP_21/incoming.json')
    data = []
    for patient_data in file.readlines():
        data.append(json.loads(patient_data))
    # data = json.load(file)
    # print(data)
    file.close()
    newdata = process(0, data)
    with open('EP_21/newindata.json', 'w') as f:
        json.dump(newdata, f, ensure_ascii=False, indent=4)

    file = open('EP_21/existing.json')
    data = []
    for patient_data in file.readlines():
        data.append(json.loads(patient_data))
    # data = json.load(file)
    file.close()
    newdata = process(1, data)
    with open('EP_21/newexdata.json', 'w') as f:
        json.dump(newdata, f, ensure_ascii=False, indent=4)
