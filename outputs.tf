output "cloudfront_domain_name" {
  description = "CloudFront distribution URL."
  value       = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name for direct testing."
  value       = aws_lb.app.dns_name
}

output "vpc_id" {
  description = "Application VPC ID."
  value       = aws_vpc.this.id
}

output "rds_endpoint" {
  description = "Private RDS endpoint."
  value       = aws_db_instance.app.address
}

output "redis_primary_endpoint" {
  description = "Private Redis primary endpoint."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "s3_bucket_name" {
  description = "Private object storage bucket."
  value       = aws_s3_bucket.objects.id
}

output "sns_topic_arn" {
  description = "SNS notifications topic ARN."
  value       = aws_sns_topic.notifications.arn
}

output "sqs_queue_url" {
  description = "SQS job queue URL."
  value       = aws_sqs_queue.jobs.url
}

output "kinesis_stream_name" {
  description = "Kinesis event stream."
  value       = aws_kinesis_stream.events.name
}

output "media_lambda_name" {
  description = "Optional media Lambda name."
  value       = try(aws_lambda_function.media_processor[0].function_name, null)
}

output "analytics_database" {
  description = "Optional Glue catalog database."
  value       = try(aws_glue_catalog_database.analytics[0].name, null)
}

output "redshift_endpoint" {
  description = "Optional Redshift endpoint."
  value       = try(aws_redshift_cluster.analytics[0].endpoint, null)
}
