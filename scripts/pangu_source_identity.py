#!/usr/bin/env python3
"""Audit D19 item-to-model identity against locally supplied resource inventories.

Inputs are private, already decoded source archives. This tool does not decrypt,
execute JavaScript, contact a server, or copy original scripts/assets to output.
It emits only source digests, item identifiers, model paths, and catalog matches.
An absent catalog match is not permission to substitute an older weapon model.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile


COLLECTION_MEMBER = "scripts/features/collection/entities/collections.js"
ITEMS_MEMBER = "scripts/features/items/entities/items.js"
CATALOG_MEMBER = "research/android_bundle_catalog.jsonl"
IOS_PATHS_MEMBER = "audit/resource_paths.json"
COLLECTION_KEY = "D_LEGENDARY_WPN_TWOHANDEDAXE_02"
MAX_MEMBER_BYTES = 32_000_000
MAX_CATALOG_RECORDS = 100_000


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def member(archive: zipfile.ZipFile, name: str) -> bytes:
    matches = [item for item in archive.infolist() if item.filename == name]
    if len(matches) != 1 or matches[0].file_size > MAX_MEMBER_BYTES:
        raise ValueError(f"Missing, duplicate, or oversized source member: {name}")
    # ZipFile.read verifies the original member CRC as well as decompression.
    return archive.read(matches[0])


def quoted_end(text: str, start: int) -> int:
    quote = text[start]
    index = start + 1
    while index < len(text):
        if text[index] == "\\":
            index += 2
        elif text[index] == quote:
            return index + 1
        else:
            index += 1
    raise ValueError("Unterminated quoted source value")


def skip_comment(text: str, start: int) -> int | None:
    if text.startswith("//", start):
        end = text.find("\n", start + 2)
        return len(text) if end < 0 else end
    if text.startswith("/*", start):
        end = text.find("*/", start + 2)
        if end < 0:
            raise ValueError("Unterminated source comment")
        return end + 2
    return None


def group_end(text: str, start: int) -> int:
    pairs = {"{": "}", "[": "]", "(": ")"}
    if text[start] not in pairs:
        raise ValueError("Expected a source group")
    stack = [pairs[text[start]]]
    index = start + 1
    while index < len(text):
        char = text[index]
        if char in "\"'`":
            index = quoted_end(text, index)
            continue
        comment = skip_comment(text, index)
        if comment is not None:
            index = comment
            continue
        if char in pairs:
            stack.append(pairs[char])
        elif char in "}])":
            if not stack or stack.pop() != char:
                raise ValueError("Mismatched source group")
            if not stack:
                return index + 1
        index += 1
    raise ValueError("Unterminated source group")


def record(text: str, key: str, constructor: bool = False) -> str:
    expression = (
        r"(?<![\w$])" + re.escape(key) + r"\s*:\s*"
        + (r"new\s+Collection\s*\(\s*" if constructor else "") + r"\{"
    )
    matches = list(re.finditer(expression, text))
    if len(matches) != 1:
        raise ValueError(f"Expected one declaration for {key}, found {len(matches)}")
    start = matches[0].end() - 1
    return text[start:group_end(text, start)]


def properties(object_text: str) -> dict[str, str]:
    """Read top-level property boundaries without evaluating source expressions."""
    if not object_text.startswith("{") or group_end(object_text, 0) != len(object_text):
        raise ValueError("Expected exactly one object literal")
    result: dict[str, str] = {}
    index = 1
    while index < len(object_text) - 1:
        if object_text[index].isspace() or object_text[index] == ",":
            index += 1
            continue
        comment = skip_comment(object_text, index)
        if comment is not None:
            index = comment
            continue
        match = re.match(r"([A-Za-z_$][\w$]*)\s*:", object_text[index:])
        if not match:
            raise ValueError("Unsupported top-level source property syntax")
        key = match[1]
        if key in result:
            raise ValueError(f"Duplicate property: {key}")
        index += match.end()
        start = index
        while index < len(object_text) - 1:
            char = object_text[index]
            if char in "\"'`":
                index = quoted_end(object_text, index)
                continue
            comment = skip_comment(object_text, index)
            if comment is not None:
                index = comment
                continue
            if char in "{[(":
                index = group_end(object_text, index)
                continue
            if char == ",":
                break
            index += 1
        result[key] = object_text[start:index].strip()
    return result


def integer(fields: dict[str, str], key: str) -> int:
    value = fields.get(key, "")
    if not re.fullmatch(r"[0-9]+", value):
        raise ValueError(f"Expected an explicit unsigned integer: {key}")
    return int(value)


def string(fields: dict[str, str], key: str) -> str:
    value = json.loads(fields[key])
    if not isinstance(value, str) or not value:
        raise ValueError(f"Expected an explicit nonempty string: {key}")
    return value


def inventory_strings(row: dict) -> list[str]:
    # Do not search hashes or arbitrary JSON text: hex digests can contain "d19".
    names = row.get("bundle_names", [])
    paths = row.get("paths", [])
    if not isinstance(names, list) or not isinstance(paths, list):
        raise ValueError("Invalid catalog row")
    return [*names, *(item["path"] for item in paths)]


def matches_model(path: str, model: str) -> bool:
    path, model = path.lower(), model.lower()
    bundle_name = "resources-content-items-models-" + model.replace("/", "-")
    asset_prefix = "assets/gamedata/resources/content/items/models/" + model + "/"
    resource_prefix = "content/items/models/" + model + "/"
    return path == bundle_name or path.startswith((asset_prefix, resource_prefix))


def audit(config_zip: Path, android_zip: Path, ios_zip: Path | None) -> dict:
    with zipfile.ZipFile(config_zip) as archive:
        collection_bytes = member(archive, COLLECTION_MEMBER)
        items_bytes = member(archive, ITEMS_MEMBER)
        version_bytes = member(archive, "version.json")
    collection = properties(record(collection_bytes.decode("utf-8"), COLLECTION_KEY, True))
    if string(collection, "aliasKey") != "D19":
        raise ValueError("Collection is not explicitly identified as D19")
    bucket = collection["bucket"]
    symbols = re.findall(r"ItemModels\.([A-Za-z0-9_]+)\.ID", bucket)
    stripped = re.sub(r"ItemModels\.[A-Za-z0-9_]+\.ID", "", bucket)
    if not symbols or not re.fullmatch(r"new\s+ItemListBunch\s*\([\s\[\],]*\)", stripped):
        raise ValueError("Unsupported collection bucket expression")
    if len(set(symbols)) != len(symbols):
        raise ValueError("Repeated item symbol in collection")
    with zipfile.ZipFile(android_zip) as archive:
        catalog_bytes = member(archive, CATALOG_MEMBER)
    catalog = [json.loads(line) for line in catalog_bytes.splitlines() if line]
    if len(catalog) > MAX_CATALOG_RECORDS:
        raise ValueError("Oversized catalog")
    if len({row["file"] for row in catalog}) != len(catalog):
        raise ValueError("Duplicate catalog file")
    ios_bytes = None
    ios = []
    if ios_zip is not None:
        with zipfile.ZipFile(ios_zip) as archive:
            ios_bytes = member(archive, IOS_PATHS_MEMBER)
        ios = json.loads(ios_bytes)
        if not isinstance(ios, list) or len(ios) > MAX_CATALOG_RECORDS:
            raise ValueError("Invalid iOS resource inventory")
    items_text = items_bytes.decode("utf-8")
    items = []
    for symbol in symbols:
        fields = properties(record(items_text, symbol))
        model = string(fields, "Model")
        tags = json.loads(fields["Tags"])
        if not isinstance(tags, list) or not any(
            tag.startswith("SET_DYNASTY_19_") for tag in tags if isinstance(tag, str)
        ):
            raise ValueError(f"Missing explicit D19 equipment tag: {symbol}")
        matched = [
            {"file": row["file"], "bytes": row["bytes"], "sha256": row["sha256"]}
            for row in catalog if any(matches_model(path, model) for path in inventory_strings(row))
        ]
        items.append({
            "symbol": symbol, "itemID": integer(fields, "ID"), "model": model,
            "maskColorChannels": integer(fields, "MaskColorChannels"),
            "equipmentTags": [tag for tag in tags if tag.startswith("SET_DYNASTY_19_")],
            "androidMatches": matched,
            "iosPathMatches": [row["path"] for row in ios if matches_model(row["path"], model)],
        })
    sources = [
        {"member": COLLECTION_MEMBER, "bytes": len(collection_bytes), "sha256": sha256(collection_bytes)},
        {"member": ITEMS_MEMBER, "bytes": len(items_bytes), "sha256": sha256(items_bytes)},
        {"member": CATALOG_MEMBER, "bytes": len(catalog_bytes), "sha256": sha256(catalog_bytes)},
    ]
    if ios_bytes is not None:
        sources.append({"member": IOS_PATHS_MEMBER, "bytes": len(ios_bytes), "sha256": sha256(ios_bytes)})
    return {
        "schemaVersion": 1,
        "sourceVersion": json.loads(version_bytes)["full"],
        "sourceMembers": sources,
        "collection": {"key": COLLECTION_KEY, "id": integer(collection, "ID"), "alias": "D19"},
        "catalogRecords": len(catalog), "iosResourceRecords": len(ios), "items": items,
        "conclusion": (
            "Only explicit model-path matches are reported. Empty matches mean the supplied inventories "
            "do not contain this model; they do not establish absence from the live game or permit a substitute."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-zip", required=True, type=Path)
    parser.add_argument("--android-source-zip", required=True, type=Path)
    parser.add_argument("--ios-resource-checkpoint", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report = audit(args.config_zip, args.android_source_zip, args.ios_resource_checkpoint)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "sourceVersion": report["sourceVersion"], "items": len(report["items"]),
        "catalogRecords": report["catalogRecords"], "iosResourceRecords": report["iosResourceRecords"],
        "matchedItems": sum(bool(item["androidMatches"] or item["iosPathMatches"]) for item in report["items"]),
    }))


if __name__ == "__main__":
    main()
