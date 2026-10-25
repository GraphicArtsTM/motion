"""structlog JSON (R10): без ПД, ключей и токенов."""

from __future__ import annotations

import logging
import re
from typing import Any

import structlog

from src.config import get_config

SENSITIVE_KEYS = {"phone", "driver_license", "license", "token", "api_key", "password", "full_name", "text",
                  "x-api-key", "authorization", "bot_token", "secret"}
PHONE_RE = re.compile(r"\+?998\d{9}")


def _scrub(_: Any, __: str, event: dict[str, Any]) -> dict[str, Any]:
    for k in list(event):
        if k.lower() in SENSITIVE_KEYS:
            event[k] = "***"
        elif isinstance(event[k], str):
            event[k] = PHONE_RE.sub("+998*********", event[k])
    return event


def setup_logging() -> None:
    cfg = get_config()
    level = getattr(logging, cfg.log_level.upper(), logging.INFO)
    logging.basicConfig(level=level, format="%(message)s")
    structlog.configure(
        processors=[structlog.contextvars.merge_contextvars, structlog.processors.add_log_level,
                    structlog.processors.TimeStamper(fmt="iso", utc=True), _scrub,
                    structlog.processors.format_exc_info, structlog.processors.JSONRenderer(ensure_ascii=False)],
        wrapper_class=structlog.make_filtering_bound_logger(level),
    )
    if cfg.sentry_dsn:
        import sentry_sdk
        sentry_sdk.init(dsn=cfg.sentry_dsn, environment=cfg.environment, send_default_pii=False)
