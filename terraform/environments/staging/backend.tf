# Terraform state stored in Scaleway Object Storage (S3-compatible).
# Credentials via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars.
terraform {
  backend "s3" {
    bucket                      = "sciath-terraform-state"
    key                         = "staging/terraform.tfstate"
    region                      = "fr-par"
    endpoints                   = { s3 = "https://s3.fr-par.scw.cloud" }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
