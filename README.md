# AWS Reference Architecture — Terraform

A portfolio-ready AWS reference architecture inspired by a typical enterprise web platform.

## What this project demonstrates

- Multi-AZ VPC design
- Public and private subnet separation
- Internet Gateway + NAT Gateway
- Application Load Balancer
- EC2 Auto Scaling
- Systems Manager instead of public SSH
- Private RDS PostgreSQL
- ElastiCache Redis
- S3 object storage with KMS encryption and lifecycle rules
- CloudFront edge delivery
- SNS + SQS asynchronous processing
- Kinesis event streaming
- CloudWatch logs and alarms
- Optional S3 -> Lambda media-processing scaffold
- Optional Glue + Redshift analytics foundation
- Clear extension points for EMR and SageMaker

## Architecture

```text
Users
  |
Route 53 (optional DNS)
  |
CloudFront
  |
ALB
  |
EC2 Auto Scaling Group
  |
  +---- RDS PostgreSQL
  |
  +---- ElastiCache Redis
  |
  +---- S3 object storage
  |
  +---- SNS -> SQS -> async workers
  |
  +---- Kinesis -> analytics pipeline
                 |
                 +-- Glue
                 +-- EMR
                 +-- Redshift
                 +-- SageMaker / ML (extension)
```

## Important portfolio note

This repository is a **reference architecture**, not a claim that every service is required for every workload.

The core web platform is deployable. Analytics/ML and media-processing components are optional because services such as Redshift, EMR and SageMaker can create meaningful AWS cost. They are intentionally disabled by default.

## Deploy

1. Install Terraform 1.6+.
2. Configure AWS credentials using your normal AWS authentication method.
3. Copy `terraform.tfvars.example` to `terraform.tfvars`.
4. Supply the database password through an environment variable:

```bash
export TF_VAR_db_password='REPLACE_WITH_A_SECRET'
```

5. Initialize:

```bash
terraform init
```

6. Review:

```bash
terraform fmt -recursive
terraform validate
terraform plan
```

7. Apply only when you are ready:

```bash
terraform apply
```

8. When finished testing, destroy the environment:

```bash
terraform destroy
```

## Cost / safety notes

- The default design uses one NAT Gateway to keep the example simple. A production design can use one NAT Gateway per AZ or a more cost-optimized egress pattern depending on availability and traffic requirements.
- RDS, Redis, NAT Gateway and CloudFront have real AWS costs.
- Keep `enable_analytics = false` unless you specifically want the analytics layer.
- Never commit database passwords, access keys, or other secrets.
- For production, add HTTPS from CloudFront to the ALB, WAF, tighter IAM policies, multi-AZ database/cache choices, centralized logging, backup/restore testing, and CI/CD policy checks.

## Why these services are separated

### Edge
Route 53 and CloudFront provide the global entry layer and reduce direct exposure of the application tier.

### Application
The ALB and EC2 Auto Scaling Group keep the application horizontally scalable and replace unhealthy instances automatically.

### Data
RDS stores relational state, Redis handles low-latency cached data, and S3 handles durable objects and data-lake content.

### Events
SNS broadcasts events, SQS buffers asynchronous work, and Kinesis captures streaming events.

### Analytics
Glue provides catalog/ETL foundations, EMR represents distributed processing, and Redshift represents the warehouse layer.

### Operations
CloudWatch provides metrics, logs and alarms. KMS is used for encryption of selected data services.

## How I would evolve this for a real enterprise workload

- Add AWS WAF at the edge.
- Use ACM certificates and HTTPS end-to-end.
- Add VPC endpoints where appropriate to reduce NAT dependency.
- Replace broad security-group egress with workload-specific controls where practical.
- Add AWS Backup policies and tested restore procedures.
- Add centralized CloudWatch / OpenSearch / SIEM integration.
- Add CI/CD with Terraform fmt, validate, tflint, tfsec/checkov and plan review.
- Add separate dev / test / prod state and accounts.
- Use Secrets Manager for database credentials.
- Add Multi-AZ RDS and a multi-node Redis topology where availability requirements justify it.
- Add EMR/SageMaker only when the data and ML use cases require them.

## Portfolio positioning

This project is meant to demonstrate how I approach cloud architecture:

**Assess -> Design -> Migrate -> Automate -> Observe -> Optimize**

It complements hands-on AWS migration work by showing the infrastructure-as-code and architecture side of the same discipline.
