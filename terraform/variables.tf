variable "credentials" {
  description = "My Terraform SA key"
  default     = "../secrets/terraform-sa.json"
}

variable "project_id" {
  description = "My GCP Project ID"
  default     = "course-data-engineering"
}

variable "project_location" {
  description = "My GCP Project Location"
  default     = "EU"
}

variable "project_region" {
  description = "My GCP Project Region"
  default     = "europe-west2"
}

variable "project_zone" {
  description = "My GCP Project Region"
  default     = "europe-west2-a"
}

variable "gcs_bucket_name" {
  description = "My GCS Bucket Name"
  default     = "igdb-game-data"
}

variable "vmuser"{
    description = "GCE VM user"
    default = "vmuser"
}