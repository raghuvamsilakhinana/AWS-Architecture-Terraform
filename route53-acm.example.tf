# OPTIONAL: custom DNS + HTTPS extension
#
# The active reference build intentionally uses the CloudFront default domain.
# For a real domain, create an ACM certificate in us-east-1, attach it to the
# CloudFront distribution, and then create a Route 53 alias to CloudFront.
#
# Example:
#
# data "aws_route53_zone" "primary" {
#   name         = "example.com"
#   private_zone = false
# }
#
# resource "aws_route53_record" "app" {
#   zone_id = data.aws_route53_zone.primary.zone_id
#   name    = "app.example.com"
#   type    = "A"
#
#   alias {
#     name                   = aws_cloudfront_distribution.app.domain_name
#     zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
#     evaluate_target_health = false
#   }
# }
#
# CloudFront custom domains also require an ACM certificate in us-east-1.
