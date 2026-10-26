"""python -m src.setup_wizard — мастер настройки на http://localhost:8765 (закрывается после сохранения)."""

from __future__ import annotations

import os

import uvicorn

from src.setup_wizard.app import app


def main() -> None:
    port = int(os.environ.get("SETUP_PORT", "8765"))
    host = os.environ.get("SETUP_HOST", "0.0.0.0")  # в Docker порт и так проброшен только на 127.0.0.1
    server = uvicorn.Server(uvicorn.Config(app, host=host, port=port, log_level="warning"))
    app.state.server = server
    print(f"Мастер настройки открыт: http://localhost:{port}  (закроется сам после сохранения)", flush=True)
    server.run()


if __name__ == "__main__":
    main()
