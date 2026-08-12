data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]
  db_subnet_cidrs      = ["10.20.21.0/24", "10.20.22.0/24"]

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# -----------------------------
# VPC / NETWORK
# -----------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "application"
  }
}

resource "aws_subnet" "db" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.db_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.project_name}-db-${count.index + 1}"
    Tier = "database"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${var.project_name}-nat"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-db-rt"
  }
}

resource "aws_route_table_association" "db" {
  count          = 2
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# -----------------------------
# KMS
# -----------------------------

resource "aws_kms_key" "platform" {
  description             = "KMS key for the portfolio AWS reference platform"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-kms"
  }
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.platform.key_id
}

# -----------------------------
# SECURITY GROUPS
# -----------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Public ingress to the Application Load Balancer"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Application tier; accepts traffic only from ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Application HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "data" {
  name        = "${var.project_name}-data-sg"
  description = "Database and cache access from application tier"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL from application tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Redis from application tier"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# IAM / SSM
# -----------------------------

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# -----------------------------
# ALB
# -----------------------------

resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# -----------------------------
# EC2 / AUTO SCALING
# -----------------------------

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl enable nginx
    systemctl start nginx
    cat >/usr/share/nginx/html/index.html <<'HTML'
    <html>
      <head><title>Portfolio AWS Reference Architecture</title></head>
      <body style="font-family:Arial;background:#0b1020;color:#fff;padding:40px">
        <h1>AWS reference platform</h1>
        <p>Served by an EC2 Auto Scaling instance behind an Application Load Balancer.</p>
      </body>
    </html>
    HTML
  EOF
  )

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-app"
      Tier = "application"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.min_size
  vpc_zone_identifier = aws_subnet.private[*].id
  health_check_type   = "ELB"
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project_name}-cpu-scale"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 60
  }
}

# -----------------------------
# RDS POSTGRES
# -----------------------------

resource "aws_db_subnet_group" "app" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = aws_subnet.db[*].id

  tags = {
    Name = "${var.project_name}-db-subnets"
  }
}

resource "aws_db_instance" "app" {
  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.platform.arn

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.app.name
  vpc_security_group_ids = [aws_security_group.data.id]

  publicly_accessible    = false
  multi_az               = false
  backup_retention_period = 7
  deletion_protection    = false
  skip_final_snapshot    = true

  tags = {
    Name = "${var.project_name}-postgres"
    Tier = "database"
  }
}

# -----------------------------
# ELASTICACHE REDIS
# -----------------------------

resource "aws_elasticache_subnet_group" "app" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.project_name}-redis"
  description          = "Redis cache for the portfolio reference platform"

  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_clusters   = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.app.name
  security_group_ids   = [aws_security_group.data.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled  = true

  tags = {
    Name = "${var.project_name}-redis"
    Tier = "cache"
  }
}

# -----------------------------
# S3 / CLOUDFRONT
# -----------------------------

resource "aws_s3_bucket" "objects" {
  bucket_prefix = "${var.project_name}-objects-"

  tags = {
    Name = "${var.project_name}-objects"
    Tier = "storage"
  }
}

resource "aws_s3_bucket_public_access_block" "objects" {
  bucket = aws_s3_bucket.objects.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "objects" {
  bucket = aws_s3_bucket.objects.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "objects" {
  bucket = aws_s3_bucket.objects.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.platform.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "objects" {
  bucket = aws_s3_bucket.objects.id

  rule {
    id     = "transition-old-objects"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}

resource "aws_cloudfront_distribution" "app" {
  enabled = true
  comment = "${var.project_name} application edge distribution"

  origin {
    domain_name = aws_lb.app.dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    forwarded_values {
      query_string = true

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
    compress    = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# -----------------------------
# SNS / SQS
# -----------------------------

resource "aws_sns_topic" "notifications" {
  name = "${var.project_name}-notifications"

  tags = {
    Name = "${var.project_name}-notifications"
  }
}

resource "aws_sqs_queue" "jobs_dlq" {
  name                      = "${var.project_name}-jobs-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "jobs" {
  name                       = "${var.project_name}-jobs"
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.jobs_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sns_topic_subscription" "jobs" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.jobs.arn
}

resource "aws_sqs_queue_policy" "jobs" {
  queue_url = aws_sqs_queue.jobs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.jobs.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_sns_topic.notifications.arn
        }
      }
    }]
  })
}

# -----------------------------
# KINESIS / CLOUDWATCH
# -----------------------------

resource "aws_kinesis_stream" "events" {
  name             = "${var.project_name}-events"
  shard_count      = 1
  retention_period = 24

  encryption_type = "KMS"
  kms_key_id      = aws_kms_key.platform.arn

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/portfolio/${var.project_name}/app"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.platform.arn
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  alarm_description   = "High ALB 5xx responses"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name          = "${var.project_name}-asg-cpu"
  alarm_description   = "Application fleet CPU is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# -----------------------------
# OPTIONAL MEDIA PROCESSOR
# -----------------------------

data "archive_file" "media_lambda" {
  count       = var.enable_media_lambda ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/media_processor.py"
  output_path = "${path.module}/lambda/media_processor.zip"
}

resource "aws_iam_role" "media_lambda" {
  count = var.enable_media_lambda ? 1 : 0
  name  = "${var.project_name}-media-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "media_lambda_basic" {
  count      = var.enable_media_lambda ? 1 : 0
  role       = aws_iam_role.media_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "media_lambda_s3" {
  count = var.enable_media_lambda ? 1 : 0
  role  = aws_iam_role.media_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject"
      ]
      Resource = "${aws_s3_bucket.objects.arn}/*"
    }]
  })
}

resource "aws_lambda_function" "media_processor" {
  count = var.enable_media_lambda ? 1 : 0

  function_name = "${var.project_name}-media-processor"
  role          = aws_iam_role.media_lambda[0].arn
  handler       = "media_processor.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.media_lambda[0].output_path
  source_code_hash = data.archive_file.media_lambda[0].output_base64sha256
  timeout       = 30
  memory_size   = 256

  environment {
    variables = {
      BUCKET = aws_s3_bucket.objects.id
    }
  }
}

resource "aws_lambda_permission" "media_s3" {
  count = var.enable_media_lambda ? 1 : 0

  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.media_processor[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.objects.arn
}

resource "aws_s3_bucket_notification" "media" {
  count  = var.enable_media_lambda ? 1 : 0
  bucket = aws_s3_bucket.objects.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.media_processor[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "incoming/"
  }

  depends_on = [aws_lambda_permission.media_s3]
}

# Analytics security group. Kept separate so Redshift can use its own port.
resource "aws_security_group" "analytics" {
  count       = var.enable_analytics ? 1 : 0
  name        = "${var.project_name}-analytics-sg"
  description = "Analytics services access from the application VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Redshift from application tier"
    from_port       = 5439
    to_port         = 5439
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# OPTIONAL ANALYTICS FOUNDATION
# -----------------------------

resource "aws_glue_catalog_database" "analytics" {
  count = var.enable_analytics ? 1 : 0
  name  = replace("${var.project_name}-analytics", "_", "-")
}

resource "aws_redshift_subnet_group" "analytics" {
  count = var.enable_analytics ? 1 : 0
  name  = "${var.project_name}-redshift-subnets"

  subnet_ids = aws_subnet.private[*].id
}

resource "aws_redshift_cluster" "analytics" {
  count = var.enable_analytics ? 1 : 0

  cluster_identifier = "${var.project_name}-redshift"
  database_name      = "analytics"
  master_username    = var.db_username
  master_password    = var.db_password
  node_type          = "ra3.xlplus"
  cluster_type       = "single-node"
  number_of_nodes    = 1

  encrypted       = true
  kms_key_id      = aws_kms_key.platform.arn
  subnet_group_name    = aws_redshift_subnet_group.analytics[0].name
  vpc_security_group_ids = [aws_security_group.analytics[0].id]

  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-redshift"
    Tier = "analytics"
  }
}

# SageMaker and EMR are intentionally represented as an architecture extension
# rather than created by default. Their production configuration depends on
# model artifacts, datasets, IAM boundaries, subnet design and workload size.
