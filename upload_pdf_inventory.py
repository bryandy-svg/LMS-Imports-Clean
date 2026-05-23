import json
import os
import re
import sys
import uuid
from datetime import datetime, timezone
from urllib import request, error

from pypdf import PdfReader


ROOT = os.path.dirname(os.path.abspath(__file__))
PDFS = [
    r"C:\Users\bryan\OneDrive\Documents\Inven222.pdf",
    r"C:\Users\bryan\OneDrive\Documents\Inventory 111.pdf",
]


def clean(text):
    return re.sub(r"\s+", " ", str(text or "")).strip()


def number(value, default=0):
    if value is None or value == "":
        return default
    try:
        return float(str(value).replace(",", ""))
    except ValueError:
        return default


def today_iso():
    return datetime.now(timezone.utc).isoformat()


def stable_id(seed):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "mall-lot-inventory:" + seed.lower()))


def normalize_key(name, sku=""):
    return clean(sku or name).lower()


def unit(value):
    value = clean(value).lower()
    mapping = {
        "ea": "each",
        "pc": "each",
        "pcs": "each",
        "pc/s": "each",
        "bx": "box",
        "rl": "roll",
        "rolls": "roll",
        "roll/s": "roll",
        "gallons": "gal",
        "set": "set",
        "bag": "bag",
        "case": "case",
        "box": "box",
        "roll": "roll",
    }
    return mapping.get(value, value or "each")


def infer_category(name, description=""):
    text = f"{name} {description}".lower()
    checks = [
        ("Furniture", ["chair", "desk", "table", "drawer"]),
        ("Appliances", ["refrigerator", "microwave", "stove", "ac", "air cooler"]),
        ("Safety", ["fire extinguisher"]),
        ("Erosion Control", ["wattle", "sediment", "erosion", "silt fence", "coir", "excelsior", "straw"]),
        ("Landscape", ["fertilizer", "turf", "seed", "peat moss", "tree stake", "edging", "weed", "ground cover"]),
        ("Flooring", ["flooring", "vinyl", "laminate", "carpet", "molding", "skirting", "reducer"]),
        ("Electrical", ["conduit", "utility box"]),
        ("Plumbing / Irrigation", ["valve", "meter", "hunter", "spray", "rotor", "fip"]),
        ("Building Materials", ["insulation", "ceiling", "adhesive", "fabric", "nails"]),
    ]
    for category, words in checks:
        if any(word in text for word in words):
            return category
    return "General"


def pdf_lines(path):
    for page in PdfReader(path).pages:
        for line in (page.extract_text() or "").splitlines():
            line = clean(line)
            if line and line not in {"Photos", "Item Description Qty UOM Cost Price Invoice Number Delivered Bin #", "Photos Description Qty"}:
                yield line


def parse_inven222(path):
    rows = []
    for line in pdf_lines(path):
        match = re.match(r"^(?P<name>.*?)(?P<qty>\d+)$", line)
        if not match:
            continue
        name = clean(match.group("name"))
        qty = number(match.group("qty"))
        if not name:
            continue
        rows.append({
            "name": name,
            "sku": f"PDF-A-{stable_id(name)[:8].upper()}",
            "quantity": qty,
            "unit": "each",
            "category": infer_category(name),
            "location": "Mall Lot",
            "bin": "",
            "supplier": "",
            "supplierContact": "",
            "poNumber": "",
            "sourceFrom": "Inven222.pdf",
            "unitCost": 0,
            "sellPrice": 0,
            "receivedDate": "",
            "notes": "Imported from Inven222.pdf.",
        })
    return rows


FULL_ROW = re.compile(
    r"^(?P<prefix>.+?)\s+(?P<qty>\d+(?:,\d{3})*\.\d{2})\s+"
    r"(?P<uom>[A-Za-z/]+)\s+(?P<cost>\d+(?:,\d{3})*(?:\.\d+)?)\s+"
    r"(?P<price>\d+(?:,\d{3})*(?:\.\d+)?)\s+(?P<invoice>INV\S+)\s+"
    r"(?P<delivered>\d{1,2}/\d{1,2}/\d{4})\s+(?P<bin>.+)$"
)

SIMPLE_ROW = re.compile(
    r"^(?P<prefix>.+?)\s+(?P<qty>\d+(?:,\d{3})*\.\d{2})\s+"
    r"(?P<uom>[A-Za-z/]+)(?:\s+(?P<cost>\d+(?:,\d{3})*(?:\.\d+)?))?\s+(?P<bin>[A-Z0-9][A-Z0-9 ,/-]*\d*)$"
)


def split_prefix(prefix):
    prefix = clean(prefix)
    parts = prefix.split(" ", 1)
    if len(parts) == 2 and re.search(r"\d|[-_/]", parts[0]) and len(parts[0]) <= 24:
        sku = parts[0]
        rest = parts[1]
    else:
        sku = ""
        rest = prefix
    words = rest.split()
    midpoint = max(2, min(len(words), 6))
    name = rest
    description = rest
    if sku:
        name = rest[:90]
    elif len(words) > midpoint and " ".join(words[:midpoint]).lower() in rest.lower():
        name = " ".join(words[:midpoint])
    return clean(name), sku, clean(description)


def parse_inventory111(path):
    rows = []
    buffer = ""
    for line in pdf_lines(path):
        buffer = clean(f"{buffer} {line}")
        match = FULL_ROW.match(buffer) or SIMPLE_ROW.match(buffer)
        if not match:
            continue
        data = match.groupdict()
        name, sku, description = split_prefix(data["prefix"])
        qty = number(data["qty"])
        row = {
            "name": name,
            "sku": sku or f"PDF-B-{stable_id(name + description)[:8].upper()}",
            "barcode": "",
            "category": infer_category(name, description),
            "quantity": qty,
            "unit": unit(data["uom"]),
            "reorderPoint": 0,
            "targetStock": qty,
            "unitCost": number(data.get("cost")),
            "sellPrice": number(data.get("price")),
            "location": "Mall Lot",
            "bin": clean(data.get("bin")),
            "supplier": "",
            "supplierContact": "",
            "poNumber": data.get("invoice") or "",
            "sourceFrom": "Inventory 111.pdf",
            "owner": "",
            "status": "Active",
            "lot": "",
            "serial": "",
            "receivedDate": data.get("delivered") or "",
            "expiryDate": "",
            "tags": "pdf import",
            "documentUrl": "",
            "notes": description,
        }
        rows.append(row)
        buffer = ""
    if buffer:
        sys.stderr.write("Unparsed tail: " + buffer[:300] + "\n")
    return rows


def build_items():
    raw = parse_inven222(PDFS[0]) + parse_inventory111(PDFS[1])
    merged = {}
    now = today_iso()
    for row in raw:
        key = normalize_key(row["name"], row.get("sku"))
        item = merged.get(key)
        if item:
            item["quantity"] = number(item["quantity"]) + number(row["quantity"])
            item["targetStock"] = max(number(item.get("targetStock")), number(row.get("targetStock")))
            item["notes"] = clean((item.get("notes") or "") + " | " + (row.get("notes") or ""))
            if row.get("bin") and row["bin"] not in (item.get("bin") or ""):
                item["bin"] = clean((item.get("bin") or "") + "; " + row["bin"])
            continue
        seed = row.get("sku") or row["name"]
        row.setdefault("barcode", "")
        row.setdefault("reorderPoint", 0)
        row.setdefault("targetStock", row["quantity"])
        row.setdefault("owner", "")
        row.setdefault("status", "Active")
        row.setdefault("lot", "")
        row.setdefault("serial", "")
        row.setdefault("expiryDate", "")
        row.setdefault("tags", "pdf import")
        row.setdefault("documentUrl", "")
        row["id"] = stable_id(seed)
        row["photoData"] = ""
        row["createdAt"] = now
        row["updatedAt"] = now
        row["movements"] = [{
            "date": now,
            "amount": row["quantity"],
            "reason": f"Imported from {row.get('sourceFrom', 'PDF')}",
        }]
        merged[key] = row
    return list(merged.values())


def supabase_record(item):
    return {
        "id": item["id"],
        "payload": item,
        "sku": item.get("sku"),
        "name": item.get("name"),
        "quantity": item.get("quantity", 0),
        "po_number": item.get("poNumber"),
        "source_from": item.get("sourceFrom"),
        "issue_type": item.get("issueType"),
        "issued_to": item.get("issuedTo"),
        "issued_from": item.get("issuedFrom"),
        "issued_quantity": item.get("issuedQuantity", 0),
        "issue_purpose": item.get("issuePurpose"),
        "approved_by": item.get("approvedBy"),
        "signature_name": item.get("signatureName"),
        "signature_data": item.get("signatureData"),
        "issue_po_number": item.get("issuePoNumber"),
        "company": item.get("company"),
        "authorization_ref": item.get("authorizationRef"),
        "return_date": item.get("returnDate") or None,
        "returned_date": item.get("returnedDate") or None,
        "condition_out": item.get("conditionOut"),
        "condition_in": item.get("conditionIn"),
        "return_status": item.get("returnStatus"),
        "updated_at": item.get("updatedAt"),
    }


def http_json(method, url, key, payload=None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    req = request.Request(url, data=body, method=method)
    req.add_header("apikey", key)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Prefer", "resolution=merge-duplicates,return=minimal")
    with request.urlopen(req, timeout=60) as response:
        data = response.read().decode("utf-8")
        return json.loads(data) if data else None


def upload(items):
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_ANON_KEY", "")
    table = os.environ.get("SUPABASE_TABLE", "inventory_items")
    if not url or not key:
        raise SystemExit("Set SUPABASE_URL and SUPABASE_ANON_KEY first.")
    endpoint = f"{url}/rest/v1/{table}"
    records = [supabase_record(item) for item in items]
    for i in range(0, len(records), 100):
        http_json("POST", endpoint, key, records[i:i + 100])
    return len(records)


if __name__ == "__main__":
    items = build_items()
    out = os.path.join(ROOT, "pdf-inventory-upload.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"items": items, "requests": [], "exportedAt": today_iso()}, f, indent=2)
    print(f"Prepared {len(items)} inventory items")
    print(f"Saved preview/import file: {out}")
    if "--upload" in sys.argv:
        print(f"Uploaded {upload(items)} inventory items to Supabase")
