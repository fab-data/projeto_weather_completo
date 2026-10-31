# AGENTS.md

Weather pipeline: Open-Meteo API → PostgreSQL (raw JSONB) → dbt, orchestrated by Airflow 3.
Everything runs in Docker; the container is the only supported execution environment.

## Run and verify

- `docker compose up -d --build` — first boot runs Airflow migrations and takes ~1 min before
  the UI responds (`http://localhost:8080`, `airflow` / `airflow`). The DAG
  `weather_pipeline` is created unpaused.
- Whole pipeline without UI: `docker compose exec airflow airflow dags test weather_pipeline`
  (default window: `end_date = today - 2`, `start_date = end_date - 2`). To pick a window use
  the DAG UI config `{"start_date": "YYYY-MM-DD", "end_date": "YYYY-MM-DD"}`.
- dbt only: `docker compose exec airflow dbt build --project-dir /opt/airflow/dbt --profiles-dir /opt/airflow/dbt`
  (both flags are required; `profiles.yml` sits inside the project dir, not `~/.dbt`).
- Check the raw load: `docker compose exec postgres psql -U weather_user -d weather_bd -c "select count(*) from raw.weather_history_json;"`

There is no lint config, no unit-test suite and no CI. `dbt build` (which also runs the dbt
tests in `models/**/*.yml` and `tests/`) is the only verification; do not invent pytest/lint steps.

## Host vs container

- `pyproject.toml` / `uv.lock` describe a minimal host env (requests only). There is no
  `psycopg2` and no dbt-postgres adapter on the host, so `load_data.py` and `dbt build` cannot
  run there — use the container. `[project.scripts]` points at a module that does not exist.
- Container deps: the Airflow base image already provides `requests` and `psycopg2`;
  `requirements-airflow.txt` only pins `dbt-core`/`dbt-postgres` 1.11. Rebuild only when that
  file changes — code edits need no rebuild.
- Bind mounts: `weather-project/airflow/dags` → `/opt/airflow/dags`,
  `weather-project/src` → `/opt/airflow/src`, `weather-project/dbt_weather` → `/opt/airflow/dbt`,
  plus `data/`, `logs/`, `config/`. The DAG inserts `/opt/airflow/src` into `sys.path`, so `src`
  files are imported flat (`from extract_data import ...`), not as a package.

## Airflow 3 specifics

- Use the Airflow 3 API: `from airflow.sdk import dag, task, get_current_context` and
  `airflow.providers.standard.operators.bash.BashOperator`. `airflow.operators.*` no longer exists.
- Task deps are set with `>>`; the DAG has no `airflow-init`/scheduler split — a single
  `airflow standalone` container runs api-server, scheduler, dag-processor and triggerer.

## Data and database facts

- Postgres is exposed on host port **5433** (container 5432). Data DB is **`weather_bd`**
  (`weather_user` / `123456`); the metastore DB is `airflow` (`airflow` / `airflow`).
  The spec under `docs/superpowers/` still says `aula_weather` — that is stale, ignore it.
- `init-db/01-init-weather-bd.sql` runs only on first boot with an empty volume. Changing it
  requires `docker compose down -v`, which wipes metastore + weather data; confirm with the
  user before doing that.
- `raw.weather_history_json` is append-only JSONB (one row per extraction). `stg_weather_history`
  explodes the `hourly` arrays with `jsonb_array_elements_text ... with ordinality` and dedupes
  via `row_number()` over `(latitude, longitude, timezone_name, weather_at_local)` ordered by
  `loaded_at desc, ingestion_id desc`. Re-running a window is safe; the newest ingestion wins.
- dbt writes to schemas `staging`, `intermediate`, `marts` because `macros/generate_schema_name.sql`
  uses the custom schema verbatim (no `<target>_<custom>` prefix). The profile schema (`public`)
  only applies where no `+schema` is set.
- `dim_date` generates every day of every year spanned by staging data, so one extra date can
  widen the mart to a full year.

## Layout

- `weather-project/airflow/dags/weather_dag.py` — extract → load → `dbt build`.
- `weather-project/src/extract_data.py` — Open-Meteo archive request, writes
  `data/weather_<start>_<end>.json` (dir overridable via `WEATHER_DATA_DIR`).
- `weather-project/src/load_data.py` — inserts the whole payload into `raw.weather_history_json`.
- `weather-project/dbt_weather/` — staging (view) → intermediate (view) → marts (table);
  `tests/assert_temperature.sql` asserts all hourly arrays have the same length as `time`.
- `data/` and `logs/` contain generated output and are gitignored; don't commit them.
