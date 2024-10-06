provider "aws" {
  region = "us-east-1"
}

# Use the existing VPC named "vpc-for-kafka"
data "aws_vpc" "vpc_for_kafka" {
  filter {
    name   = "tag:Name"
    values = ["vpc-for-kafka"]
  }
}

# Reference the existing subnet 'subnet-for-kafka'
data "aws_subnet" "subnet_1" {
  filter {
    name   = "tag:Name"
    values = ["subnet-for-kafka"]  # Correct name of the subnet
  }
  vpc_id = data.aws_vpc.vpc_for_kafka.id
}

# Reference the existing subnet 'subnet-for-kafka 2'
data "aws_subnet" "subnet_2" {
  filter {
    name   = "tag:Name"
    values = ["subnet-for-kafka 2"]  # Correct name of the second subnet
  }
  vpc_id = data.aws_vpc.vpc_for_kafka.id
}

# Security Group allowing public traffic to MSK Brokers
resource "aws_security_group" "msk_security_group" {
  name        = "msk-security-group"
  vpc_id      = data.aws_vpc.vpc_for_kafka.id
  description = "Allow MSK traffic"

  # Allow traffic on Kafka's plaintext and TLS ports
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# MSK Cluster configuration
resource "aws_msk_cluster" "msk_cluster" {
  cluster_name           = "msk-cluster"
  kafka_version          = "2.6.1"
  number_of_broker_nodes = 2

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [data.aws_subnet.subnet_1.id, data.aws_subnet.subnet_2.id]  # Use existing subnets
    security_groups = [aws_security_group.msk_security_group.id]
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  client_authentication {
    unauthenticated = true
    tls {}
  }

  configuration_info {
    arn      = aws_msk_configuration.msk_configuration.arn
    revision = aws_msk_configuration.msk_configuration.latest_revision
  }

  tags = {
    Name = "msk-cluster"
  }
}

# MSK Configuration (Kafka properties)
resource "aws_msk_configuration" "msk_configuration" {
  name            = "msk-configuration"
  kafka_versions  = ["2.6.1"]

  server_properties = <<PROPERTIES
auto.create.topics.enable = true
delete.topic.enable = true
log.retention.hours = 168
log.retention.bytes = 1073741824
log.segment.bytes = 1073741824
PROPERTIES
}

# Get availability zones
data "aws_availability_zones" "available" {}

# Output for Kafka Bootstrap Servers (Plaintext)
output "kafka_bootstrap_servers" {
  description = "Plaintext bootstrap servers for the Kafka cluster"
  value       = aws_msk_cluster.msk_cluster.bootstrap_brokers
}

# Output for Kafka Bootstrap Servers (TLS)
output "kafka_bootstrap_servers_tls" {
  description = "TLS bootstrap servers for the Kafka cluster"
  value       = aws_msk_cluster.msk_cluster.bootstrap_brokers_tls
}
