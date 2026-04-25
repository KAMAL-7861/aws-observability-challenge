terraform {
  backend "s3" {
    bucket         = "obs-challenge-terraform-state"
    key            = "c2-us-west-2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "obs-challenge-terraform-locks"
    encrypt        = true
  }
}
