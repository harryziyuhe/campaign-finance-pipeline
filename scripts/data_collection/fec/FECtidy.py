import pandas as pd
from tqdm import tqdm
import os, sys, json
import re
import os
from pathlib import Path
tqdm.pandas() 

def clean_corp(text, stopwords):
    text = re.sub(r"\(.*?\)", " ", text)
    text = re.sub(r"[^\w\s]", " ", text)
    text = " ".join(word for word in text.split() if word.lower() not in stopwords)
    text = re.sub(r"\s+", " ", text).strip()
    return text

def preprocess(text, business = True, politics = True, symbol = True, period = False):
    text = text.lower().strip()
    text = re.sub(r'\([^)]*\)', ' ', text)
    if symbol:
        text = re.sub(r'[^a-zA-Z0-9\s]', ' ', text)
    if period:
        text = re.sub(r'\.', ' ', text)
    if business:
        text = re.sub(r'\b(inc|corp|corporation|ltd|llc|group|co|plc|limited|company|incorporated|the|and|holdings)\b', ' ', text)
    if politics:
        text = re.sub(r'\b(federal|political|committee|action|election|politi|politic|pac)\b', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text

SCRIPT_ROOT = Path(__file__).resolve().parents[3]


def _require_data_root() -> Path:
    value = os.environ.get("CAMPAIGNFINANCE_DATA_ROOT")
    if not value:
        raise RuntimeError(
            "CAMPAIGNFINANCE_DATA_ROOT is not set. Point it at the campaign-finance-data "
            "folder (contains data/ and outputs/), e.g.:\n"
            '  $env:CAMPAIGNFINANCE_DATA_ROOT = "C:\\Users\\<you>\\Dropbox\\campaign-finance-data"'
        )
    root = Path(value)
    if not root.is_dir():
        raise RuntimeError(f"CAMPAIGNFINANCE_DATA_ROOT does not exist: {root}")
    return root


DATA_ROOT = _require_data_root()
FEC_DATA_PATH = str(DATA_ROOT / "data" / "raw" / "fec_bulk") + "/"
COMMITTEES_FILE_PATH = str(DATA_ROOT / "data" / "raw" / "fec_bulk" / "committees") + "/"
CPAC_FILE_PATH = str(DATA_ROOT / "data" / "raw" / "fec_bulk" / "cpac") + "/"
YEARS = range(2004, 2026, 2)
BUS_STOPWORDS = ["corp", "inc", "corporation", "llc", "plc", "ltd", "holdings", "co", "incorporated", "corporate"]
PAC_STOPWORDS = ["political action committee", "pac"]
stopwords = BUS_STOPWORDS + PAC_STOPWORDS

class FECTidy:
    def __init__(self):
        self.committees_path = COMMITTEES_FILE_PATH
        self.cpac_path = CPAC_FILE_PATH
        self.years = YEARS
        self.stopwords = BUS_STOPWORDS + PAC_STOPWORDS

    def get_corporate_pacs(self):
        for year in self.years:
            committees = pd.read_parquet(f"{self.committees_path}committees_{year}.parquet")
            corporate = committees.loc[committees[f"ORG_TP"] == "C", ]
            connected_corp = corporate[corporate["CONNECTED_ORG_NM"].notna()].copy()
            connected_corp["CORPORATION"] = connected_corp["CONNECTED_ORG_NM"].apply(lambda x: clean_corp(x, stopwords))
            missing_corp = corporate[corporate["CONNECTED_ORG_NM"].isna()].copy()
            missing_corp["CORPORATION"] = ""
            pacs = pd.read_parquet(f"{self.committees_path}pacs_{year}.parquet")
            list1 = corporate.columns.tolist()
            list2 = pacs.columns.tolist()
            match_cols = [col for col in list1 if col in list2]

            connected_corp = pd.merge(connected_corp, pacs, on = match_cols)
            missing_corp = pd.merge(missing_corp, pacs, on = match_cols)

            connected_corp.to_csv(f"{self.committees_path}corporate_{year}.csv", index=False)
            missing_corp.to_csv(f"{self.committees_path}corporate_missing_{year}.csv", index=False)

    def merge_corporate_pacs(self):
        connected_cpacs = pd.DataFrame()
        missing_cpacs = pd.DataFrame()
        var_list = ["CMTE_ID", "CMTE_NM", "CONNECTED_ORG_NM", "CORPORATION", "TTL_RECEIPTS", "YEAR"]
        for year in self.years:
            connected_corp = pd.read_csv(f"{self.committees_path}corporate_{year}.csv")
            missing_corp = pd.read_csv(f"{self.committees_path}corporate_missing_{year}.csv")

            connected_corp["YEAR"] = year
            missing_corp["YEAR"] = year

            connected_cpacs = pd.concat([connected_cpacs, connected_corp[var_list]])
            missing_cpacs = pd.concat([missing_cpacs, missing_corp[var_list]])
            
        connected_cpacs_full = connected_cpacs.sort_values(by=["CMTE_ID", "YEAR"], ascending=True).reset_index(drop=True)
        connected_cpacs_short = connected_cpacs_full[["CMTE_ID", "CMTE_NM", "CONNECTED_ORG_NM", "CORPORATION"]].drop_duplicates(subset="CMTE_ID", keep = "last")
        missing_cpacs_full = missing_cpacs.sort_values(by = ["CMTE_ID", "YEAR"], ascending=True).reset_index(drop=True)

        connected_cpacs_full.to_csv(f"{self.committees_path}corporate_pacs_full.csv", index=False)
        connected_cpacs_short.to_csv(f"{self.committees_path}corporate_pacs.csv", index=False)
        missing_cpacs_full.to_csv(f"{self.committees_path}missing_cpacs.csv", index=False)

    def agg_corporate_pacs(self):
       
       """
       This is sort of a mess that requires using existing files to generate new file. The existing file is generated by merging 
       auto-matched and hand-matched. Need to check `company_match.ipynb` to maybe streamline this later
       """
       merge_vars = ["CMTE_ID", "CMTE_NM", "CONNECTED_ORG_NM", "CORPORATION", "YEAR"]
       current_cpac = pd.read_csv(f"{self.cpac_path}corporate_pacs_2004_2024.csv")
       connected_cpacs_full = pd.read_csv(f"{self.committees_path}corporate_pacs_full.csv")
       new_cpac = pd.merge(
           current_cpac,
           connected_cpacs_full,
           how = "left",
           on = merge_vars
       ).copy()
       new_cpac["CONNECTED_ORG_NM"] = new_cpac["CONNECTED_ORG_NM"].apply(preprocess)
       new_cpac["missing"] = ""

       missing_cpac = pd.read_csv(f"{self.committees_path}missing_cpacs.csv")
       missing_cpac["RIC", "PermID", "Parent", "Website"] = ""
       missing_cpac["missing"] = "1"

       full_cpac = pd.concat([new_cpac, missing_cpac])
       full_cpac.columns = full_cpac.columns.str.lower()
       full_cpac["cmte_nm"] = full_cpac["cmte_nm"].apply(preprocess)

       full_cpac = full_cpac.sort_values(by=["cmte_id", "year"], ascending=True).reset_index(drop=True)

       full_cpac.to_csv(f"{self.cpac_path}corporate_pacs_all.csv", index = False)

    def corporate_pac_list(self):
        """
        Get a dataframe of corporate pac ID and name list. Used for matching with Bonica data
        """
        connected_cpac = pd.read_csv(f"{self.committees_path}corporate_pacs_full.csv")
        missing_cpac = pd.read_csv(f"{self.committees_path}missing_cpacs.csv")
        full_cpac = pd.concat([connected_cpac, missing_cpac]).reset_index(drop = True)
        full_cpac = full_cpac[["CMTE_ID", "YEAR", "CMTE_NM", "CONNECTED_ORG_NM"]]
        full_cpac = full_cpac.sort_values(by=["CMTE_ID", "YEAR"], ascending=True).reset_index(drop=True)
        full_cpac.to_csv(f"{self.cpac_path}corporate_pacs_list.csv", index = False)

def reformat_txt(root, file, json_file):
    with open(f"{root}/{json_file}") as f:
        columns = json.load(f)
    column_names = columns.keys()
    df = pd.read_csv(f"{root}/{file}", delimiter="|", index_col = False,
                     names=column_names, dtype=columns, encoding="latin")
    df.to_parquet(f"{root}/{file.replace("txt", "parquet")}", engine="pyarrow", index=False, compression="snappy")

def reformat_folder(folder):
    for root, dirs, files in os.walk(f"{FEC_DATA_PATH}{folder}"):
        for file in files:
            if ".txt" in file:
                json_file = file.rsplit('_', 1)[0] + ".json"
                if json_file in files:
                    print(f"processing {file}")
                    try:
                        reformat_txt(root, file, json_file)
                    except Exception as e:
                        print(e)  

if __name__ == "__main__":
    tidy = FECTidy()
    #tidy.get_corporate_pacs()
    #tidy.merge_corporate_pacs()
    #tidy.agg_corporate_pacs()
    tidy.corporate_pac_list()
    #reformat_folder("contributions/committees")
