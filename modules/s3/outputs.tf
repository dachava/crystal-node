output "bucket_id" {
  value = aws_s3_bucket.main.id
}

output "bucket_arn" {
  description = "Used in IAM policies to grant pod access via IRSA"
  value       = aws_s3_bucket.main.arn
}