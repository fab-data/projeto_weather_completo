from __future__ import annotations

import json
import os
from datetime import date
from pathlib import Path

import requests

ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
LATITUDE = -16.6869
LONGITUDE = -49.2648
TIMEZONE = "America/Sao_Paulo"
HOURLY = [
    "temperature_2m",
    "relative_humidity_2m",
    "precipitation",
    "surface_pressure",
    "wind_speed_10m",
]
DATA_DIR = Path(os.getenv("WEATHER_DATA_DIR", "/opt/airflow/data"))


def extract_weather_data(start_date: date, end_date: date) -> Path:
    response = requests.get(
        ARCHIVE_URL,
        params={
            "latitude": LATITUDE,
            "longitude": LONGITUDE,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "hourly": ",".join(HOURLY),
            "timezone": TIMEZONE,
        },
        timeout=30,
    )
    response.raise_for_status()
    payload = response.json()

    if payload.get("error"):
        raise RuntimeError(payload.get("reason", "Open-Meteo retornou erro"))

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    output_path = DATA_DIR / f"weather_{start_date}_{end_date}.json"
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return output_path
