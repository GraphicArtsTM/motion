"""Генерация Postman-коллекции admin API из OpenAPI-схемы FastAPI: python -m scripts.export_postman"""

from __future__ import annotations

import json
from pathlib import Path

from src.web import app


def main() -> None:
    spec = app.openapi()
    folders: dict[str, list] = {}
    for path, methods in spec["paths"].items():
        if not path.startswith("/admin/api"):
            continue
        section = path.split("/")[3]
        for method, op in methods.items():
            item = {"name": op.get("summary") or f"{method.upper()} {path}",
                    "request": {"method": method.upper(),
                                "header": [{"key": "Authorization", "value": "Bearer {{token}}"}],
                                "url": {"raw": "{{base_url}}" + path, "host": ["{{base_url}}"],
                                        "path": path.strip("/").split("/")}}}
            body = op.get("requestBody", {}).get("content", {}).get("application/json", {}).get("schema")
            if body:
                ref = body.get("$ref", "").split("/")[-1]
                props = spec["components"]["schemas"].get(ref, {}).get("properties", {})
                example = {k: v.get("default", f"<{v.get('type', 'value')}>") for k, v in props.items()}
                item["request"]["body"] = {"mode": "raw", "raw": json.dumps(example, ensure_ascii=False, indent=2),
                                           "options": {"raw": {"language": "json"}}}
            folders.setdefault(section, []).append(item)
    collection = {
        "info": {"name": "Taxopark Referral — Admin API",
                 "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
        "variable": [{"key": "base_url", "value": "https://bot.example.uz"}, {"key": "token", "value": ""}],
        "item": [{"name": k, "item": v} for k, v in sorted(folders.items())],
    }
    out = Path("docs/postman_collection.json")
    out.write_text(json.dumps(collection, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{out}: {sum(len(v) for v in folders.values())} requests")


if __name__ == "__main__":
    main()
