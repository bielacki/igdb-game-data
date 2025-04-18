terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.26.0"
    }
  }
}

provider "google" {
  credentials = var.credentials
  project     = var.project_id
  region      = var.project_region
}


locals {
  dag_content = file("../airflow/dags/igdb_pipeline.py")
  docker_compose_content = file("../airflow/docker-compose.yml")
  dockerfile_content = file("../airflow/Dockerfile")
  requirements_content = file("../airflow/requirements.txt")
  airflow_sa = file("../secrets/airflow-sa.json")
}

resource "google_storage_bucket" "igdb-game-data" {
  name          = var.gcs_bucket_name
  location      = var.project_region
  storage_class = "STANDARD"
  force_destroy = true
}

resource "google_storage_bucket_object" "spark_gcs_to_bq" {
  name   = "spark_gcs_to_bq.py"
  source = "../pyspark/spark_gcs_to_bq.py"
  bucket = google_storage_bucket.igdb-game-data.id
}

resource "google_storage_bucket_object" "dlt_cloud_function_object" {
  name   = "igdb-dlt-pipeline-source.zip"
  bucket = google_storage_bucket.igdb-game-data.name
  source = "../dlt-pipeline/igdb-dlt-pipeline-source.zip"
}

resource "google_cloudfunctions2_function" "dlt_cloud_function" {
  name        = "igdb-dlt-pipeline"
  location    = var.project_region

  build_config {
    runtime     = "python310"
    entry_point = "load_igdb"
    source {
      storage_source {
        bucket = google_storage_bucket.igdb-game-data.name
        object = google_storage_bucket_object.dlt_cloud_function_object.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "1Gi"
    timeout_seconds    = 3000

    secret_environment_variables {
      key        = "IGDB_BEARER_TOKEN"
      project_id = var.project_id
      secret     = "IGDB_BEARER_TOKEN"
      version    = "latest"
    }

    secret_environment_variables {
      key        = "IGDB_CLIENT_ID"
      project_id = var.project_id
      secret     = "IGDB_CLIENT_ID"
      version    = "latest"
    }

    secret_environment_variables {
      key        = "SLACK_INCOMING_HOOK"
      project_id = var.project_id
      secret     = "SLACK_INCOMING_HOOK"
      version    = "latest"
    }
  }
  
}

resource "google_cloud_run_v2_job" "dbt_runner" {
  name     = "dbt-runner"
  location = var.project_region

  template {
    template {
      containers {
        image = "europe-west2-docker.pkg.dev/course-data-engineering/igdb-dbt-repo/igdb-dbt-image:latest"
        resources {
          limits = {
            cpu    = "2"
            memory = "1024Mi"
          }
        }
      }
    }
  }
}

resource "google_bigquery_dataset" "igdb_bq_source_dataset" {
  dataset_id  = "igdb_source"
  project     = var.project_id
  location    = var.project_region
  description = "BigQuery dataset for IGDB source data"
}

resource "google_bigquery_dataset" "igdb_bq_dwh_dataset" {
  dataset_id  = "igdb_dwh"
  project     = var.project_id
  location    = var.project_region
  description = "BigQuery dataset for IGDB transformed data"
}

resource "google_dataproc_cluster" "igdb-dataproc-cluster" {
  name   = "igdb-dataproc-cluster"
  region = var.project_region

  cluster_config {
    gce_cluster_config {
      zone = var.project_zone
    }
    master_config {
      num_instances = 1
      machine_type  = "e2-standard-4"
      disk_config {
        boot_disk_type    = "pd-balanced"
        boot_disk_size_gb = 50
      }
    }
    software_config {
      image_version = "2.2.51-debian12"
      override_properties = {
        "dataproc:dataproc.allow.zero.workers" = "true"
      }
    }
  }
}

resource "google_compute_instance" "igdb-airflow-instance" {
  name         = "igdb-airflow-instance"
  machine_type = "e2-standard-2"
  zone         = var.project_zone
  tags         = ["http-server", "https-server"]


  boot_disk {
    initialize_params {
      image = "ubuntu-2404-noble-amd64-v20250313"
      size  = 50
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    user-data = <<-EOF
    #!/bin/bash
    
    sudo apt-get update -y
    sudo apt-get install ca-certificates curl -y
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y

    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

    sudo mkdir -p /home/${var.vmuser}/airflow-docker/secrets
    chmod -R 755 /home/${var.vmuser}
    
    cd /home/${var.vmuser}/airflow-docker

    sudo mkdir -p ./dags ./logs ./plugins ./config
    sudo chown -R 1001:1001 ./dags ./logs ./plugins ./config
    chmod -R 775 ./dags ./logs ./plugins ./config

    echo '${base64encode(local.airflow_sa)}' | base64 -d > /home/${var.vmuser}/airflow-docker/secrets/airflow-sa.json
    echo '${base64encode(local.docker_compose_content)}' | base64 -d > /home/${var.vmuser}/airflow-docker/docker-compose.yml
    echo '${base64encode(local.dockerfile_content)}' | base64 -d > /home/${var.vmuser}/airflow-docker/Dockerfile
    echo '${base64encode(local.requirements_content)}' | base64 -d > /home/${var.vmuser}/airflow-docker/requirements.txt
    echo '${base64encode(local.dag_content)}' | base64 -d > /home/${var.vmuser}/airflow-docker/dags/igdb_pipeline.py

    sudo usermod -aG docker ${var.vmuser}
    newgrp docker
    docker compose up airflow-init
    sleep 10
    docker compose up
  EOF
  }
}

resource "google_compute_firewall" "allow_8080" {
  name    = "allow-8080"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  target_tags = ["http-server"]
}
