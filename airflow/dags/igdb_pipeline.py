from airflow import DAG
from airflow.providers.http.operators.http import SimpleHttpOperator
from airflow.providers.google.cloud.operators.dataproc import DataprocSubmitJobOperator
from airflow.providers.google.cloud.operators.cloud_run import CloudRunExecuteJobOperator
import google.oauth2.id_token
import google.auth.transport.requests
from datetime import datetime

# Generate an OAuth 2.0 token for authentication
request = google.auth.transport.requests.Request()
# replace with your Cloud Function URL
audience = 'https://europe-west2-course-data-engineering.cloudfunctions.net/igdb-dlt-pipeline'
TOKEN = google.oauth2.id_token.fetch_id_token(request, audience)


# Define default arguments for the DAG
default_args = {
    "owner": "airflow",
    "depends_on_past": False
}

# Define the DAG
with DAG(
    "igdb_pipeline",
    default_args=default_args,
    description="Run Cloud Function, Dataproc job, and dbt models",
    schedule_interval="0 4 * * *",  # Runs daily at 4:00 AM
    start_date=datetime(2025, 4, 6),
    catchup=False,
) as dag:

    # Task 1: Run a script in Google Cloud Functions
    run_cloud_function = SimpleHttpOperator(
        task_id="run_cloud_function",
        http_conn_id="http_functions",
        # replace with your Cloud Function ID
        endpoint="igdb-dlt-pipeline",
        method="POST",
        headers={'Authorization': f"Bearer {TOKEN}", "Content-Type": "application/json"},
        data={},
    )

    # Task 2: Submit a job to a Dataproc cluster
    dataproc_job = {
        "reference": {"project_id": "course-data-engineering"},
        "placement": {"cluster_name": "igdb-dataproc-cluster"},
        "pyspark_job": {
            # replace with your Cloud Storage bucket name
            "main_python_file_uri": "gs://igdb-game-data/spark_gcs_to_bq.py",
        },
    }

    submit_dataproc_job = DataprocSubmitJobOperator(
        task_id="submit_dataproc_job",
        job=dataproc_job,
        # replace with your region and project ID
        region="europe-west2",
        project_id="course-data-engineering",
    )

    # Task 3: Run dbt models

    execute_cloud_run_job = CloudRunExecuteJobOperator(
        task_id="execute_cloud_run_job",
        # replace with your region and project ID
        project_id="course-data-engineering",
        region="europe-west2",
        job_name="dbt-runner",
        dag=dag,
        deferrable=False,
    )

    # Define task dependencies
    run_cloud_function >> submit_dataproc_job >> execute_cloud_run_job
