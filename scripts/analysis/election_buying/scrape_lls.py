import re, html, urllib.request, csv, sys

url = "https://redistricting.lls.edu/resources/maps-across-the-cycle-2010-congress/"
raw = urllib.request.urlopen(url, timeout=60).read().decode("utf-8", "ignore")

# isolate tables
tables = re.findall(r"<table.*?</table>", raw, flags=re.S|re.I)
print("tables found:", len(tables), file=sys.stderr)

def cells(row):
    cs = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, flags=re.S|re.I)
    out = []
    for c in cs:
        c = re.sub(r"<script.*?</script>|<style.*?</style>", "", c, flags=re.S|re.I)
        c = html.unescape(re.sub(r"<[^>]+>", " ", c))
        out.append(re.sub(r"\s+", " ", c).strip())
    return out

rows = []
for t in tables:
    for r in re.findall(r"<tr.*?</tr>", t, flags=re.S|re.I):
        c = cells(r)
        if len(c) >= 6 and c[0] and c[0].lower() != "state":
            rows.append(c[:6])

# dedupe, keep order
seen=set(); clean=[]
for r in rows:
    k=tuple(r)
    if k not in seen:
        seen.add(k); clean.append(r)

with open("lls_2010_congress.csv","w",newline="") as f:
    w=csv.writer(f)
    w.writerow(["state","drawn_by","party_control","finalized","effective_start","end_date"])
    w.writerows(clean)

print(f"rows written: {len(clean)}", file=sys.stderr)
