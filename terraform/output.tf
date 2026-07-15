output "environment" {
  description = "Active environment (workspace name)."
  value       = local.environment
}

output "site_bucket_name" {
  description = "S3 bucket the built app is uploaded to."
  value       = aws_s3_bucket.site.bucket
}

output "log_bucket_name" {
  description = "S3 bucket receiving CloudFront access logs."
  value       = aws_s3_bucket.logs.bucket
}

output "cloudfront_distribution_id" {
  description = "Distribution ID, used for cache invalidation."
  value       = aws_cloudfront_distribution.site.id
}

output "url" {
  description = "Public URL of the deployed app."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}