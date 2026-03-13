output "api_endpoint" {
  description = "Public URL to invoke the API"
  value       = "${aws_apigatewayv2_stage.main.invoke_url}"
}