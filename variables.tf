variable "aws_region" {
  description = "AWS region for the reference platform."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short project name used for resource naming."
  type        = string
  default     = "portfolio-aws-platform"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "portfolio"
}

variable "vpc_cidr" {
  description = "CIDR for the application VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability Zones. Two are enough for the reference build."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "instance_type" {
  description = "EC2 instance type for the web/application tier."
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum ASG capacity."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum ASG capacity."
  type        = number
  default     = 4
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the portfolio reference database."
  type        = string
  default     = "appadmin"
}

variable "db_password" {
  description = "Master password. Pass via TF_VAR_db_password or a secrets workflow; never commit it."
  type        = string
  sensitive   = true
}

variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "enable_media_lambda" {
  description = "Create the optional S3-triggered media processing Lambda scaffold."
  type        = bool
  default     = false
}

variable "enable_analytics" {
  description = "Create the optional analytics/ML foundation resources. Keep false for a low-cost portfolio demo."
  type        = bool
  default     = false
}

