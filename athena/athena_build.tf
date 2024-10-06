terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
  required_version = ">= 0.12"
}

provider "aws" {
  region = "us-east-1"  # Adjust to your preferred AWS region
}

# S3 Bucket Name
variable "s3_bucket_name" {
  default = "kafkatos3than"  # Ensure this matches your bucket name
}

# Step 1: Import the ARN of the manually created IAM Role
variable "glue_role_arn" {
  description = "The ARN of the manually created Glue role."
  default     = "arn:aws:iam::534030821312:role/glue-service-role"
}

# Step 2: Create Glue Database
resource "aws_glue_catalog_database" "finance_data_db" {
  name = "finance_data_db"
}

# Step 3: Create Glue Crawler to Scan S3 Data
resource "aws_glue_crawler" "finance_data_crawler" {
  name           = "finance-data-crawler"
  role           = var.glue_role_arn
  database_name  = aws_glue_catalog_database.finance_data_db.name
  table_prefix   = "finance_data_"

  s3_target {
    path = "s3://${var.s3_bucket_name}/topics/finance-data/partition=0/"
  }

  # You can adjust the schedule as needed or remove it for manual runs
  schedule = "cron(0/15 * * * ? *)"
}

# Step 4: Optionally Trigger the Glue Crawler After Creation
resource "null_resource" "start_glue_crawler" {
  provisioner "local-exec" {
    command = "aws glue start-crawler --name finance-data-crawler"
  }

  depends_on = [aws_glue_crawler.finance_data_crawler]
}

# Step 5: Create Athena Database
resource "aws_athena_database" "finance_data_athena_db" {
  name   = "finance_data_athena_db"
  bucket = var.s3_bucket_name
}

# Step 6: Create Athena Named Query to Define Table Schema
resource "aws_athena_named_query" "create_table_finance_data" {
  name      = "CreateFinanceDataTable"
  database  = aws_athena_database.finance_data_athena_db.name
  query     = <<QUERY
CREATE EXTERNAL TABLE `finance_data`(
  `price_change` string,
  `symbol` string,
  `percent_change` string,
  `options_call_volume_percent` string,
  `options_put_call_volume_ratio` string,
  `options_put_volume_percent` string,
  `symbol_type` int,
  `has_options` string,
  `symbol_code` string,
  `trade_time` string,
  `options_implied_volatility_rank1y` string,
  `options_total_volume` string,
  `symbol_name` string,
  `last_price` string
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
LOCATION 's3://${var.s3_bucket_name}/topics/finance-data/partition=0/';
QUERY
}

# Step 7: Debugging Outputs (Remove After Testing)
output "glue_role_arn" {
  value = var.glue_role_arn
}

output "glue_crawler_name" {
  value = aws_glue_crawler.finance_data_crawler.name
}
