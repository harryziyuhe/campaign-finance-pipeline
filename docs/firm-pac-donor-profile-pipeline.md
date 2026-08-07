# Firm PAC Donor Profile Pipeline

This pipeline links individuals who contribute to corporate PACs to broader FEC individual contribution behavior. It is intentionally staged so employer aliases can be manually reviewed before the raw FEC master files are searched.

## Revised Workflow

1. Extract observed individual-employer-PAC triads from `data/processed/fec/individual_to_firm_pac_contributions`.
2. Produce `employer_pac_alias_review.csv` for manual review of whether each observed employer-PAC pair refers to the PAC sponsor.
3. Convert manually approved rows into an employer-PAC-firm alias crosswalk.
4. Search raw FEC individual files using only approved employer aliases.
5. Resolve person-firm-cycle identities within approved firm affiliations.
6. Link PAC donors to outside giving and build the comparison pool.

## Manual Review Gate

The manual review file should be edited before later stages run. Its key column is `manual_status`.

Accepted statuses:

- `own_firm`
- `subsidiary_or_affiliate`

Review or rejected statuses:

- `retiree_or_former_employee`
- `not_own_firm`
- `unclear`
- `invalid_placeholder`

Only accepted statuses become raw-file employer aliases.

## Important Assumptions

- Employer aliases should come from observed PAC-donor records, not from every raw FEC employer string.
- Raw FEC addresses are supporting evidence only; they should not be required for identity matching.
- Person identities are scoped to `firm_id + cycle + normalized name`; they are not global national identities.
- Retirees, family-like records, and board/executive-like records should be flagged and reviewed rather than silently mixed into the main analysis population.

## Script

Use:

```powershell
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage extract-employer-pac-review --cycles 2004
```

Then edit:

```text
data/processed/fec/firm_pac_donor_profiles/employer_pac_alias_review.csv
```

Subsequent stages:

```powershell
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage build-approved-aliases
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage search-raw-employees --cycles 2004
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage resolve-identities --cycles 2004
.\.venv\Scripts\python.exe scripts\data_collection\fec\FECfirmPacDonorProfiles.py --stage link-outside-giving --cycles 2004
```
