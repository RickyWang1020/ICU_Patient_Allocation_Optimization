# ICU Patient Allocation Optimization Model

## About

This is project for CS Capstone, which is a Linear Programming model design & implementation for a better ICU patient allocation. The model's effectiveness is evaluated using MIMIC-IV dataset.

## Usage

1. Run `query_updated.sql` to extract data from the MIMIC dataset (on Google Cloud Platform)
2. Run `process.py` to process the incoming and existing patients' JSON data
3. Run `historical_stat_process.py` to process the historical patients' JSON data
4. Run `model.py` to get the LP Allocation Result

