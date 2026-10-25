"""Нормализация и валидация регистрационных данных (3.2)."""

from __future__ import annotations

import re
from dataclasses import dataclass

UZ_COUNTRY = "998"
UZ_NATIONAL_LEN = 9
NAME_MIN_WORDS, NAME_MAX_WORDS = 2, 3
NAME_MIN_LEN, NAME_MAX_LEN = 5, 100
LICENSE_FALLBACK_RE = re.compile(r"^[A-Z0-9]{6,12}$")


def normalize_phone(raw: str | None) -> str | None:
    """→ +998XXXXXXXXX или None."""
    if not raw:
        return None
    digits = re.sub(r"\D", "", raw)
    if len(digits) == UZ_NATIONAL_LEN:
        digits = UZ_COUNTRY + digits
    if len(digits) != len(UZ_COUNTRY) + UZ_NATIONAL_LEN or not digits.startswith(UZ_COUNTRY):
        return None
    return "+" + digits


def normalize_license(raw: str | None) -> str | None:
    """Верхний регистр, без пробелов и дефисов: 'ab 123-4567' → 'AB1234567'."""
    if not raw:
        return None
    value = re.sub(r"[\s\-–—]", "", raw).upper()
    return value or None


@dataclass
class LicenseCheck:
    value: str | None
    ok: bool
    needs_admin_flag: bool = False


def validate_license(raw: str | None, regex: str) -> LicenseCheck:
    lic = normalize_license(raw)
    if not lic:
        return LicenseCheck(None, False)
    if re.fullmatch(regex, lic):
        return LicenseCheck(lic, True)
    if LICENSE_FALLBACK_RE.fullmatch(lic):
        return LicenseCheck(lic, True, needs_admin_flag=True)
    return LicenseCheck(lic, False)


def validate_full_name(raw: str | None) -> str | None:
    if not raw:
        return None
    name = " ".join(raw.split())
    words = name.split(" ")
    if not (NAME_MIN_LEN <= len(name) <= NAME_MAX_LEN):
        return None
    if not (NAME_MIN_WORDS <= len(words) <= NAME_MAX_WORDS):
        return None
    if any(ch.isdigit() for ch in name):
        return None
    return name


def mask_phone(phone: str | None) -> str:
    """+998 91 *** ** 89"""
    if not phone or len(phone) < len(UZ_COUNTRY) + UZ_NATIONAL_LEN + 1:
        return phone or ""
    return f"{phone[:4]} {phone[4:6]} *** ** {phone[-2:]}"


def format_phone(phone: str | None) -> str:
    """+998 90 123 45 67"""
    if not phone or len(phone) != len(UZ_COUNTRY) + UZ_NATIONAL_LEN + 1:
        return phone or ""
    return f"{phone[:4]} {phone[4:6]} {phone[6:9]} {phone[9:11]} {phone[11:]}"


def short_name(full_name: str | None) -> str:
    """«Каримов Азиз Бахтиёрович» → «Каримов А.»"""
    if not full_name:
        return ""
    parts = full_name.split()
    return parts[0] if len(parts) == 1 else f"{parts[0]} {parts[1][0]}."
