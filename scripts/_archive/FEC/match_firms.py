import pandas as pd

def match_firms(year = None, columns = None):
    if not columns:
        columns = ["Instrument", "RIC", "PermID", "Business_Description", "HQ_State", "NAICS_Sector", "TRBC_Econ_Sector"]
    corporate_pacs = pd.read_csv("../data/cpac/corporate_pacs_2004_2024.csv")
    private_firms = pd.read_csv("../data/firms/private_firms.csv")
    private_firms = private_firms[columns]
    public_firms = pd.read_csv("../data/firms/public_firms.csv")
    public_firms = public_firms[columns]
    cpac_public = corporate_pacs.loc[(~corporate_pacs["RIC"].isna()), ].reset_index(drop=True)
    cpac_private = corporate_pacs.loc[(corporate_pacs["RIC"].isna()), ].reset_index(drop=True)
    cpac_public = pd.merge(cpac_public[["CMTE_ID", "RIC", "PermID", "Parent", "Website", "YEAR"]],
                           public_firms,
                           how = "left",
                           left_on = "RIC", right_on = "Instrument",
                           suffixes = ("", "_public"))
    cpac_private = pd.merge(cpac_private[["CMTE_ID", "RIC", "PermID", "Parent", "Website", "YEAR"]],
                            private_firms,
                            how = "left",
                            left_on = "PermID", right_on = "Instrument",
                            suffixes = ("", "_private"))
    cpac = pd.concat([cpac_public, cpac_private]).reset_index(drop=True).drop(columns=["RIC_public", "PermID_public", "RIC_private", "PermID_private"])
    if year:
        return cpac[cpac["YEAR"] == year]
    return cpac