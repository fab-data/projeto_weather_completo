from datetime import date, datetime, timedelta
import sys

from airflow.sdk import dag, task, get_current_context
from airflow.providers.standard.operators.bash import BashOperator

sys.path.insert(0, "/opt/airflow/src")

from extract_data import extract_weather_data
from load_data import load_weather_data


@dag(
    dag_id="weather_pipeline",
    default_args={
        "owner": "airflow",
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
    },
    description="Pipeline Open-Meteo -> Postgres -> dbt",
    schedule="0 6 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    params={"start_date": "", "end_date": ""},
    tags=["weather", "open-meteo", "dbt"],
)
def weather_pipeline():
    @task
    def extract():
        params = get_current_context()["params"]
        start = params.get("start_date")
        end = params.get("end_date")

        if start and end:
            start_date = date.fromisoformat(start)
            end_date = date.fromisoformat(end)
        else:
            end_date = date.today() - timedelta(days=2)
            start_date = end_date - timedelta(days=2)

        return str(extract_weather_data(start_date, end_date))

    @task
    def load(json_path: str):
        return load_weather_data(json_path)

    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=(
            "dbt build "
            "--project-dir /opt/airflow/dbt "
            "--profiles-dir /opt/airflow/dbt"
        ),
    )

    extract_task = extract()
    load_task = load(extract_task)
    extract_task >> load_task >> dbt_build


weather_pipeline()
