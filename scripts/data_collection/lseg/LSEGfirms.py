import pandas as pd
pd.set_option('future.no_silent_downcasting', True)

import json
import os
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[3]
CONFIG_PATH = str(SCRIPT_ROOT / "config")
os.environ["LD_LIB_CONFIG_PATH"] = CONFIG_PATH

import lseg.data as ld
from lseg.data.content import search

ld.open_session()


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
LSEG_PATH = str(Path(__file__).resolve().parent) + "/"
DATA_PATH = str(DATA_ROOT / "data" / "raw" / "lseg") + "/"
COLLAPSE_COLS = ["TRBC_ID", "TRBC_Econ_Sector", "TRBC_Business_Sector", "TRBC_Industry_Group",
                 "TRBC_Industry", "TRBC_Activity", "NAICS_ID", "NAICS_Sector", "NAICS_Subsector",
                 "NAICS_Industry_Group", "NAICS_International_Industry", "NAICS_National_Industry"]

def collapse(x):
    x = [v for v in x if pd.notnull(v) and v != '']
    return x if x else None

class LSEGfirms:
    def __init__(self):
        self.lseg_path = LSEG_PATH
        with open(f"{self.lseg_path}data_fields.json", "r") as f:
            data_fields = json.load(f)
            self.fields = list(data_fields.keys())
            self.col_names = list(data_fields.values())
        self.agg_dict = {
            col: collapse if col in COLLAPSE_COLS else "first" 
            for col in self.col_names
        }
    
    def load_pacs(self, path):
        self.cpacs = pd.read_csv(path, dtype={"permid": str})
        self.rics = self.cpacs["ric"].dropna().unique().tolist()
        self.permids = self.cpacs["permid"].dropna().unique().tolist()
        self.parents = self.cpacs["parent"].dropna().unique().tolist()

    def load_existing_data(self):
        if os.path.exists(f"{DATA_PATH}all_firms.csv"):
            self.all_firms = pd.read_csv(f"{DATA_PATH}all_firms.csv", dtype={"permid": str, "parent_permid": str})
            self.existing_instruments = self.all_firms["instrument"].dropna().tolist()
        else:
            self.all_firms = pd.DataFrame()
            self.existing_instruments = []
    
    def query_lseg(self):
        self.rics = [ric for ric in self.rics if ric not in self.existing_instruments]
        self.permids = [id for id in self.permids if id not in self.existing_instruments]
        self.parents = [parent for parent in self.parents if parent not in self.existing_instruments]
        df_RICs = ld.get_data(universe = self.rics, fields = self.fields)
        df_PermIDs = ld.get_data(universe = self.permids, fields = self.fields)
        df_Parents = ld.get_data(universe = self.parents, fields = self.fields)
        
        df_RICs.columns = ["instrument"] + self.col_names
        df_PermIDs.columns = ["instrument"] + self.col_names
        df_Parents.columns = ["instrument"] + self.col_names

        df_RICs = df_RICs.groupby("instrument", as_index=False).agg(self.agg_dict).reset_index()
        df_PermIDs = df_PermIDs.groupby("instrument", as_index=False).agg(self.agg_dict).reset_index()
        df_Parents = df_Parents.groupby("instrument", as_index=False).agg(self.agg_dict).reset_index()

        self.all_firms = pd.concat([self.all_firms, df_RICs, df_PermIDs, df_Parents], ignore_index=True)

        self.all_firms.to_csv(f"{DATA_PATH}LSEG_firms.csv", index=False)

if __name__ == "__main__":
    lseg_firms = LSEGfirms()
    lseg_firms.load_pacs(f"{DATA_PATH}corporate_pacs.csv")
    lseg_firms.load_existing_data()
    lseg_firms.query_lseg()
        
