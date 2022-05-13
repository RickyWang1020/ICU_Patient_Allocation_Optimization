# ICU Patient Allocation Optimization Model

## About

This is project for CS Capstone, which is a Integer Linear Programming model design & implementation for a better ICU patient allocation. The model's effectiveness is evaluated using MIMIC-IV dataset.

## Usage

1. Run `query_updated.sql` to extract data from the MIMIC dataset (on Google Cloud Platform)
2. Run `process.py` to process the incoming and ICU existing patients' JSON data
3. Run `historical_stat_process.py` to process the historical patients' JSON data
4. Run `model.py` to get the ILP Allocation Result

## References

[1] MIMIC-IV Dataset: https://physionet.org/content/mimiciv/1.0/
