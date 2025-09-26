# GitHub self-hosted runner EC2 instance

locals {
  github_runner_enabled = var.github_repository != null && var.github_runner_enabled
}

# Security group for the GitHub runner
resource "aws_security_group" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  name_prefix = "${var.interview_name}-github-runner-"
  description = "Security group for GitHub self-hosted runner"
  vpc_id      = aws_vpc.github_runner[0].id

  # Outbound traffic (for package downloads, GitHub API, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Optional: SSH access for debugging (remove in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this to your IP in production
  }

  tags = {
    Name        = "${var.interview_name}-github-runner-sg"
    Environment = "production"
    Project     = var.interview_name
  }
}

# IAM role for the EC2 instance
resource "aws_iam_role" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  name = "${var.interview_name}-github-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "production"
    Project     = var.interview_name
  }
}

# IAM instance profile
resource "aws_iam_instance_profile" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  name = "${var.interview_name}-github-runner-profile"
  role = aws_iam_role.github_runner[0].name
}

# IAM policy for ECR access (optional, if runner needs to push/pull images)
resource "aws_iam_role_policy" "github_runner_ecr" {
  count = local.github_runner_enabled ? 1 : 0

  name = "${var.interview_name}-github-runner-ecr"
  role = aws_iam_role.github_runner[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = [for repo in values(aws_ecr_repository.repo) : repo.arn]
      }
    ]
  })
}

# User data script to install Docker and GitHub runner
locals {
  github_runner_user_data = local.github_runner_enabled ? base64encode(templatefile("${path.module}/github_runner_userdata.sh", {
    github_repository = var.github_repository
    github_token      = var.github_runner_token
    runner_name       = "${var.interview_name}-runner"
    runner_labels     = "self-hosted,linux,x64,${var.interview_name}"
  })) : ""
}

# Launch template for the GitHub runner
resource "aws_launch_template" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  name_prefix   = "${var.interview_name}-github-runner-"
  image_id      = data.aws_ami.ubuntu[0].id
  instance_type = var.github_runner_instance_type
  key_name      = var.github_runner_key_name

  vpc_security_group_ids = [aws_security_group.github_runner[0].id]

  iam_instance_profile {
    name = aws_iam_instance_profile.github_runner[0].name
  }

  user_data = local.github_runner_user_data

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = var.github_runner_disk_size
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.interview_name}-github-runner"
      Environment = "production"
      Project     = var.interview_name
    }
  }

  tags = {
    Environment = "production"
    Project     = var.interview_name
  }
}

# Auto Scaling Group (maintains 1 instance)
resource "aws_autoscaling_group" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  name                      = "${var.interview_name}-github-runner-asg"
  vpc_zone_identifier       = [aws_subnet.github_runner[0].id]
  target_group_arns         = []
  health_check_type         = "EC2"
  health_check_grace_period = 300

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.github_runner[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.interview_name}-github-runner-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.interview_name
    propagate_at_launch = true
  }
}

# Data sources
data "aws_ami" "ubuntu" {
  count = local.github_runner_enabled ? 1 : 0

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC for GitHub runner
resource "aws_vpc" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.interview_name}-github-runner-vpc"
    Environment = "production"
    Project     = var.interview_name
  }
}

# Internet Gateway
resource "aws_internet_gateway" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  vpc_id = aws_vpc.github_runner[0].id

  tags = {
    Name        = "${var.interview_name}-github-runner-igw"
    Environment = "production"
    Project     = var.interview_name
  }
}

# Public subnet
resource "aws_subnet" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  vpc_id                  = aws_vpc.github_runner[0].id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = data.aws_availability_zones.available[0].names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.interview_name}-github-runner-subnet"
    Environment = "production"
    Project     = var.interview_name
  }
}

# Route table
resource "aws_route_table" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  vpc_id = aws_vpc.github_runner[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.github_runner[0].id
  }

  tags = {
    Name        = "${var.interview_name}-github-runner-rt"
    Environment = "production"
    Project     = var.interview_name
  }
}

# Route table association
resource "aws_route_table_association" "github_runner" {
  count = local.github_runner_enabled ? 1 : 0

  subnet_id      = aws_subnet.github_runner[0].id
  route_table_id = aws_route_table.github_runner[0].id
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  count = local.github_runner_enabled ? 1 : 0
  state = "available"
}
