### [API GATEWAY] ###
# managed service that lives outside the VPC

# The API Itself. HTTP API is the better choice!
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  tags = var.tags
}

# the private tunnel to the VPC
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${var.project_name}-vpc-link"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]

  tags = var.tags
}

# Security group for the VPC link
resource "aws_security_group" "vpc_link" {
  name        = "${var.project_name}-vpc-link-sg"
  description = "Controls traffic from API Gateway VPC Link to NLB"
  vpc_id      = var.vpc_id

# API Gateway lives outside the VPC, 0/0:80 is "acceptable"
# handles auth, throttling, and routing... public boundary
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from API Gateway"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound to NLB"
  }

  tags = var.tags
}

# wires the API to the VPC Link
resource "aws_apigatewayv2_integration" "main" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY" # forwards the request as is to the backend
  integration_method = "ANY" # forwards GET, POST, PUT, DELETE
  integration_uri    = var.nlb_listener_arn # to know where to send traffic through the VPC Link

# tells API Gateway to route through the VPC Link instead of the public internet
  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.main.id
}

# ROute
resource "aws_apigatewayv2_route" "main" {
  api_id    = aws_apigatewayv2_api.main.id
  # Any HTTP method, any path gets forwarded to the integration
  route_key = "ANY /{proxy+}" # for prod use GET /users or POST /orders, specific
  target    = "integrations/${aws_apigatewayv2_integration.main.id}"
}

# Deployment stage
# stage is a snapshot of the API deployment
resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = var.environment
  auto_deploy = true # Production setups use explicit deployments

  tags = var.tags
}