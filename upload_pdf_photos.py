import base64
import json
import os
import re
import uuid
from datetime import datetime, timezone
from io import BytesIO
from urllib import parse, request

from PIL import Image
from pypdf import PdfReader

from upload_pdf_inventory import (
    FULL_ROW,
    PDFS,
    SIMPLE_ROW,
    clean,
    infer_category,
    number,
    split_prefix,
    stable_id,
)


ROOT = os.path.dirname(os.path.abspath(__file__))


def image_to_data_url(raw):
    image = Image.open(BytesIO(raw))
    if image.mode not in ("RGB", "L"):
        image = image.convert("RGB")
    elif image.mode == "L":
        image = image.convert("RGB")
    image.thumbnail((900, 900))
    out = BytesIO()
    image.save(out, format="JPEG", quality=72, optimize=True)
    encoded = base64.b64encode(out.getvalue()).decode("ascii")
    return "data:image/jpeg;base64," + encoded


def page_images(path):
    pages = {}
    for page_number, page in enumerate(PdfReader(path).pages, start=1):
        usable = []
        for image in page.images:
            try:
                with Image.open(BytesIO(image.data)) as parsed:
                    width, height = parsed.size
                if width * height < 20_000:
                    continue
                usable.append(image_to_data_url(image.data))
            except Exception:
                continue
        pages[page_number] = usable
    return pages


def page_lines(path):
    for page_number, page in enumerate(PdfReader(path).pages, start=1):
        lines = []
        for line in (page.extract_text() or "").splitlines():
            line = clean(line)
            if line and line not in {
                "Photos",
                "Item Description Qty UOM Cost Price Invoice Number Delivered Bin #",
                "Photos Description Qty",
            }:
                lines.append(line)
        yield page_number, lines


def inven222_item_pages(path):
    result = {}
    for page_number, lines in page_lines(path):
        rows = []
        for line in lines:
            match = re.match(r"^(?P<name>.*?)(?P<qty>\d+)$", line)
            if not match:
                continue
            name = clean(match.group("name"))
            rows.append(stable_id(f"PDF-A-{stable_id(name)[:8].upper()}"))
        result[page_number] = rows
    return result


def inventory111_item_pages(path):
    result = {}
    buffer = ""
    buffer_page = None
    for page_number, lines in page_lines(path):
        for line in lines:
            if not buffer:
                buffer_page = page_number
            buffer = clean(f"{buffer} {line}")
            match = FULL_ROW.match(buffer) or SIMPLE_ROW.match(buffer)
            if not match:
                continue
            data = match.groupdict()
            name, sku, description = split_prefix(data["prefix"])
            generated_sku = sku or f"PDF-B-{stable_id(name + description)[:8].upper()}"
            item_id = stable_id(generated_sku)
            result.setdefault(buffer_page or page_number, []).append(item_id)
            buffer = ""
            buffer_page = None
    return result


def build_photo_map():
    mapping = {}
    for path, item_pages_builder in [
        (PDFS[0], inven222_item_pages),
        (PDFS[1], inventory111_item_pages),
    ]:
        images_by_page = page_images(path)
        items_by_page = item_pages_builder(path)
        for page_number, ids in items_by_page.items():
            images = images_by_page.get(page_number, [])
            for item_id, data_url in zip(ids, images):
                mapping[item_id] = data_url
    return mapping


def http_json(method, url, key, payload=None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    req = request.Request(url, data=body, method=method)
    req.add_header("apikey", key)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Prefer", "return=representation")
    with request.urlopen(req, timeout=60) as response:
        data = response.read().decode("utf-8")
        return json.loads(data) if data else None


def upload_photos(photo_map):
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_ANON_KEY", "")
    table = os.environ.get("SUPABASE_TABLE", "inventory_items")
    if not url or not key:
        raise SystemExit("Set SUPABASE_URL and SUPABASE_ANON_KEY first.")
    base = f"{url}/rest/v1/{table}"
    updated = 0
    for item_id, data_url in photo_map.items():
        row_url = f"{base}?id=eq.{parse.quote(item_id)}&select=payload"
        rows = http_json("GET", row_url, key) or []
        if not rows:
            continue
        payload = rows[0].get("payload") or {}
        payload["photoData"] = data_url
        payload["updatedAt"] = datetime.now(timezone.utc).isoformat()
        patch_url = f"{base}?id=eq.{parse.quote(item_id)}"
        result = http_json("PATCH", patch_url, key, {"payload": payload, "updated_at": payload["updatedAt"]})
        if result:
            updated += len(result)
    return updated


if __name__ == "__main__":
    photo_map = build_photo_map()
    preview_path = os.path.join(ROOT, "pdf-photo-map-summary.json")
    with open(preview_path, "w", encoding="utf-8") as f:
        json.dump({"photoItemCount": len(photo_map), "itemIds": list(photo_map)}, f, indent=2)
    print(f"Prepared photos for {len(photo_map)} items")
    print(f"Saved photo summary: {preview_path}")
    if "--upload" in os.sys.argv:
        print(f"Uploaded photos to {upload_photos(photo_map)} items")
