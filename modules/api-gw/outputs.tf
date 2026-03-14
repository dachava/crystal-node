output "api_endpoint" {
  description = "Public URL to invoke the API"
  value       = "${aws_apigatewayv2_stage.main.invoke_url}"
}

output "api_id" {
  description = "API Gateway ID used by Route53 module for custom domain mapping"
  value       = aws_apigatewayv2_api.main.id
}