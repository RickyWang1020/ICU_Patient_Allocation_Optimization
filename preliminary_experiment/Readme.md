## Preliminary Experiment on 4.3

### Features:
- Implemented the calculation of SOFA score (S), mortality rate mapping (M), life expectancy (L), estimated treatment effectiveness (E), and medical effectiveness value (V)
- Using scipy to do optimization, and derived the selection among ICU, general inpatient unit, and ICU wait-list, for each of the incoming patients and existing patients in ICU

### More To-do:
- The distinction between ICU and ICU wait-list
- A better data structure for handling a large influx of patient data
- Data loader script for pre-processing raw MIMIC data
