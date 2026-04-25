terraform {
  backend "s3" {
    bucket         = "obs-challenge-terraform-state"
    key            = "c1-us-east-1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "obs-challenge-terraform-locks"
    encrypt        = true
  }
}
