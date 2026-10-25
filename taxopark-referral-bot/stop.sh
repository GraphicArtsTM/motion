#!/usr/bin/env bash
cd "$(dirname "$0")" && docker compose --profile polling --profile webhook down
