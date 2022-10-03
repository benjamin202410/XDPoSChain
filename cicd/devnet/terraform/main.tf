terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
}

# This bucket had to be created before you can run the terraform init
resource "aws_s3_bucket" "terraform_s3_bucket" {
  bucket = "terraform-devnet-bucket"
  versioning {
    enabled = true
  }
}

# Bucket need to be created first. If first time run terraform init, need to comment out the below section
terraform {
  backend "s3" {
    bucket = "terraform-devnet-bucket"
    key    = "tf/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}

resource "aws_vpc" "devnet_vpc" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"
  
  tags = {
    Name = "TfDevnetVpc"
  }
}

resource "aws_subnet" "devnet_subnet" {
  vpc_id = aws_vpc.devnet_vpc.id
  cidr_block = "10.0.0.0/20"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
  
  tags = {
    Name = "TfDevnetVpcSubnet"
  }
}

resource "aws_internet_gateway" "devnet_gatewat" {
  vpc_id = aws_vpc.devnet_vpc.id

  tags = {
    Name = "TfDevnetGateway"
  }
}

resource "aws_route_table" "devnet_route_table" {
  vpc_id = aws_vpc.devnet_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devnet_gatewat.id
  }

  tags = {
    Name = "TfDevnetVpcRoutingTable"
  }
}

resource "aws_route_table_association" "devnet_route_table_association" {
  subnet_id      = aws_subnet.devnet_subnet.id
  route_table_id = aws_route_table.devnet_route_table.id
}

resource "aws_default_security_group" "devnet_xdcnode_security_group" {
  vpc_id = aws_vpc.devnet_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "TfDevnetNode"
  }
}

resource "aws_security_group" "devnet_efs_security_group" {
  name = "TfDevnetEfsSecurityGroup"
  description = "Allow HTTP in and out of devnet EFS"
  vpc_id = aws_vpc.devnet_vpc.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "TCP"
    security_groups = [aws_default_security_group.devnet_xdcnode_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "TfDevnetEfs"
  }
}

# IAM policies

data "aws_iam_policy_document" "xdc_ecs_tasks_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Create the role
resource "aws_iam_role" "devnet_xdc_ecs_tasks_execution_role" {
  name               = "devnet-xdc-ecs-task-execution-role"
  assume_role_policy = "${data.aws_iam_policy_document.xdc_ecs_tasks_execution_role.json}"
}

# Attached the AWS managed policies to the new role
resource "aws_iam_role_policy_attachment" "devnet_xdc_ecs_tasks_execution_role" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientFullAccess", 
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonElasticFileSystemsUtils"
  ])
  role       = aws_iam_role.devnet_xdc_ecs_tasks_execution_role.name
  policy_arn = each.value
}

# EFS
resource "aws_efs_file_system" "devnet_efs" {
   creation_token = "efs"
   performance_mode = "generalPurpose"
   throughput_mode = "bursting"
   encrypted = "true"
   tags = {
       Name = "TfDevnetEfs"
   }
 }

resource "aws_efs_mount_target" "alpha" {
  file_system_id = aws_efs_file_system.devnet_efs.id
  subnet_id      = aws_subnet.devnet_subnet.id
}