from __future__ import annotations

import json
import os
from pathlib import Path

import psycopg2
from psycopg2.extras import Json


def load_weather_data(json_path: str) -> int:
    payload = json.loads(Path(json_path).read_text(encoding="utf-8"))

    with psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "postgres"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "weather_bd"),
        user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                insert into raw.weather_history_json (payload)
                values (%s)
                returning ingestion_id
                """,
                (Json(payload),),
            )
            return cursor.fetchone()[0]
