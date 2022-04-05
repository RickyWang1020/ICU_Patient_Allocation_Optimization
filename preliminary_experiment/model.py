from scipy.optimize import linprog
from test_data import *


### Mapping from a patient's SOFA score to mortality percentage ###
def mapping_sofa_to_mortality(sofa_score):
    # statistics of sofa score mapping to mortality rate
    # 0 to 6	< 10%
    # 7 to 9	15 - 35%
    # 10 to 12	40 - 50%
    # 13 to 15	55 - 75%
    # 16 to 24	> 80%
    # we use a linear mapping
    assert 0 <= sofa_score <= 24
    if 0 <= sofa_score <= 6:
        mortality = 0.1 / sofa_score
    elif 7 <= sofa_score <= 9:
        return 0.1 * sofa_score - 0.55
    elif 10 <= sofa_score <= 12:
        return 0.05 * sofa_score - 0.1
    elif 13 <= sofa_score <= 15:
        return 0.1 * sofa_score - 0.75
    else:
        return 0.025 * sofa_score + 0.4
    return round(mortality, 3)


### normalize a patient's age into a [0,1] float ###
def normalize_age(patient_age):
    return patient_age / 100


### calculate a patient's life expectancy value (L) ###
def calculate_l_p(patient_list, s_list, patient_id, noicu_flag=0):
    # 1 - M(S) + w_d1 * Ep_d1_ICU + w_d2 * Ep_d2_ICU +...
    # this is a weighted sum of all the Ep_d values (d means one disease that the patient is diagnosed with),
    # where the weight is decided by the patient's diagnosis priority of multiple diseases
    pri_Ep_d_icu = []
    weights = 0
    for record in patient_list[patient_id]:
        pri_Ep_d_icu += [[int(record["seq_num"]), Ep_d_icu_noicu[record["icd_code"]][noicu_flag]]]
        weights += 1 / int(record["seq_num"])
    sum = 0
    for pair in pri_Ep_d_icu:
        sum += (1 / weights) * (1 / pair[0]) * pair[1]
    l_p = min(1 - mapping_sofa_to_mortality(s_list[patient_id - 1]) + sum, 1)
    l_p = max(0, l_p)
    return l_p


### calculate a patient's medical effectiveness value (V) ###
def calculate_v_p(patient_info, patient_id, l_p):
    # w1 and w2 can be customized by the hospital, depending on its valuation of the parameters
    return w1 * l_p + w2 * normalize_age(patient_info[patient_id]["age"])


def extract_result_from_optim_result(optim):
    arr = optim.x
    result = {"icu": [], "general inpatient": [], "icu waitlist": [], "allocation error": []}
    # currently, we first processed incoming patient data, then existing patient
    for i in range(Pi):
        incoming_patient_subject_id = incoming_patient_disease[i + 1][0]["subject_id"]
        # first idx means whether to icu
        if arr[i*3] == 1:
            result["icu"].append(incoming_patient_subject_id)
        # second idx means whether to general inpatient unit
        elif arr[i*3+1] == 1:
            result["general inpatient"].append(incoming_patient_subject_id)
        # third idx means whether to icu waitlist
        elif arr[i*3+2] == 1:
            result["icu waitlist"].append(incoming_patient_subject_id)
        # see if error happens
        else:
            result["allocation error"].append(incoming_patient_subject_id)
    for j in range(Pe):
        existing_patient_subject_id = existing_patient_disease[j + 1][0]["subject_id"]
        # first idx means whether to icu
        if arr[j * 3] == 1:
            result["icu"].append(existing_patient_subject_id)
        # second idx means whether to general inpatient unit
        elif arr[j * 3 + 1] == 1:
            result["general inpatient"].append(existing_patient_subject_id)
        # third idx means whether to icu waitlist
        elif arr[j * 3 + 2] == 1:
            result["icu waitlist"].append(existing_patient_subject_id)
        # see if error happens
        else:
            result["allocation error"].append(existing_patient_subject_id)

    return result

if __name__ == "__main__":
    print("mortality rate of incoming and existing patients:")
    m_i = list(map(mapping_sofa_to_mortality, s_i))
    m_e = list(map(mapping_sofa_to_mortality, s_e))
    print(m_i, m_e)

    '''
    Maximize sum(X_p1 * V_ICU + X_p2 * V_NOICU + X_p3 * 0) 
    Subject to:
    X_i1 + X_i2 + X_i3 = 1 for i = 1,2…Pi
    0 < X_i1 < 1
    0 < X_i2 < 1
    0 < X_i3 < 1
    X_j1 + X_j2 + X_j3 = 1 for j = 1,2…Pe
    0 < X_j1 < 1
    0 < X_j2 < 1
    0 < X_j3 < 1
    0 < X_11+....X_P1 < Ricu * Umax
    0 < (X_12+....X_P2)+(X_13+....X_P3) < Ricuout
    '''

    obj = []
    for i in range(Pi):
        obj.append(
            -1 * calculate_v_p(incoming_patient_info, i + 1, calculate_l_p(incoming_patient_disease, s_i, i + 1, 0)))
        obj.append(
            -1 * calculate_v_p(incoming_patient_info, i + 1, calculate_l_p(incoming_patient_disease, s_i, i + 1, 1)))
        obj.append(0)
    for i in range(Pe):
        obj.append(
            -1 * calculate_v_p(existing_patient_info, i + 1, calculate_l_p(existing_patient_disease, s_e, i + 1, 0)))
        obj.append(
            -1 * calculate_v_p(existing_patient_info, i + 1, calculate_l_p(existing_patient_disease, s_e, i + 1, 1)))
        obj.append(0)

    lhs = []
    lhs.append([1, 0, 0] * (Pi + Pe))
    lhs.append([0, 1, 1] * (Pi + Pe))
    rhs = [int(R_icu * Umax), R_noicu]

    lhs_eq = []
    rhs_eq = []
    for i in range(Pi):
        lhs_eq.append([0] * i * 3 + [1, 1, 1] + [0] * (3 * (Pi + Pe - i) - 3))
        rhs_eq.append(1)
    for i in range(Pe):
        lhs_eq.append([0] * (Pi + i) * 3 + [1, 1, 1] + [0] * (3 * (Pe - i) - 3))
        rhs_eq.append(1)

    bnd = []
    for i in range(3 * (Pi + Pe)):
        bnd.append((0, 1))

    print("default (interior-point) optimization result:")
    optimization = linprog(c=obj, A_ub=lhs, b_ub=rhs, A_eq=lhs_eq, b_eq=rhs_eq, bounds=bnd)
    print(optimization)
    print()

    print("simplex optimization result:")
    simplex_optimization = linprog(c=obj, A_ub=lhs, b_ub=rhs, A_eq=lhs_eq, b_eq=rhs_eq, bounds=bnd, method='simplex')
    print(simplex_optimization)
    print()

    print("revised simplex optimization result:")
    revised_optimization = linprog(c=obj, A_ub=lhs, b_ub=rhs, A_eq=lhs_eq, b_eq=rhs_eq, bounds=bnd, method='revised simplex')
    print(revised_optimization)

    print(extract_result_from_optim_result(simplex_optimization))