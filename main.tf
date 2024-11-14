provider "aws" {
  region = "us-west-2"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "main-vpc" }
}

# Public subnets in the VPC
data "aws_availability_zones" "available" {}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-${count.index}" }
}

# Add ACM Certificate
resource "aws_acm_certificate" "cert" {
  domain_name               = "lbls.xyz"
  subject_alternative_names = ["*.lbls.xyz"]
  validation_method         = "DNS"
  tags                      = { Name = "lbls.xyz Certificate" }
  lifecycle { create_before_destroy = true }
}

# Route 53 Hosted Zone and Validation Records
data "aws_route53_zone" "main" {
  name         = "lbls.xyz"
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      value   = dvo.resource_record_value
      zone_id = data.aws_route53_zone.main.zone_id
    }
  }
  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# API Gateway Configuration
resource "aws_apigatewayv2_api" "user_api" {
  name          = "UserAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_domain_name" "api_domain" {
  domain_name = "api.lbls.xyz"
  domain_name_configuration {
    certificate_arn = aws_acm_certificate.cert.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.user_api.id
  name        = "prod"
  auto_deploy = true
}

resource "aws_apigatewayv2_api_mapping" "custom_domain_mapping" {
  api_id      = aws_apigatewayv2_api.user_api.id
  domain_name = aws_apigatewayv2_domain_name.api_domain.domain_name
  stage       = aws_apigatewayv2_stage.prod.name
}

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.lbls.xyz"
  type    = "A"
  alias {
    name                   = aws_apigatewayv2_domain_name.api_domain.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api_domain.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# IAM Role and Policies for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "LambdaExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_access_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "secrets_manager_access_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "aurora_db_credentials"
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_admin,
    password = var.db_password
  })
}

# Aurora Database and Security Configuration
resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora-subnet-group"
  subnet_ids = aws_subnet.public[*].id
  tags       = { Name = "AuroraSubnetGroup" }
}

resource "aws_security_group" "aurora_sg" {
  name        = "aurora-security-group"
  description = "Allow access to Aurora PostgreSQL"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Adjust for security requirements
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_rds_cluster" "aurora_postgres" {
  cluster_identifier      = "aurora-serverless-pg-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = "13.12"
  database_name           = var.db_name
  master_username         = var.db_admin
  master_password         = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.aurora_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.aurora_sg.id]
  engine_mode             = "serverless"
  skip_final_snapshot     = true
  scaling_configuration {
    auto_pause             = true
    max_capacity           = 4
    min_capacity           = 2
    seconds_until_auto_pause = 300
  }
}

output "aurora_postgres_endpoint" {
  value = aws_rds_cluster.aurora_postgres.endpoint
}

# Attach policies to allow Lambda to interact with VPC resources and Secrets Manager
resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Inline policy for VPC access in Lambda
resource "aws_iam_role_policy" "lambda_vpc_inline_policy" {
  role = aws_iam_role.lambda_exec.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
        ],
        Resource = "*"
      }
    ]
  })
}

resource "null_resource" "package_lambda" {
  provisioner "local-exec" {
    command = <<EOT
      GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
      zip -j function.zip bootstrap
    EOT
  }

  triggers = {
    build_time = timestamp()
  }
}

# Lambda Function for User CRUD operations
resource "aws_lambda_function" "user_crud" {
  function_name = "UserCrudFunction"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "bootstrap"  # 'bootstrap' is required for Go functions using provided.al2 runtime
  runtime       = "provided.al2"
  filename      = "${path.module}/function.zip"  # Path to your packaged Lambda function
  timeout       = 60  # Increase the timeout (in seconds)

  environment {
    variables = {
      DATABASE_HOST      = aws_rds_cluster.aurora_postgres.endpoint
      DATABASE_PORT      = "5432"
      DATABASE_NAME      = var.db_name
      DATABASE_USER      = var.db_admin
      DATABASE_PASSWORD  = var.db_password
      DB_CREDENTIALS_ARN = aws_secretsmanager_secret.db_credentials.arn
    }
  }

  # Add VPC configuration to connect Lambda to the VPC
  vpc_config {
    subnet_ids         = aws_subnet.public[*].id
    security_group_ids = [aws_security_group.aurora_sg.id]
  }

  depends_on = [
    null_resource.package_lambda,
    aws_iam_role_policy_attachment.secrets_manager_access_policy
  ]
}

# API Gateway Integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.user_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.user_crud.invoke_arn
}

# API Gateway Routes for CRUD operations
resource "aws_apigatewayv2_route" "create_user" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "POST /users"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "get_user" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "GET /users/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "update_user" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "PUT /users/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "delete_user" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "DELETE /users/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Deploy the API Gateway
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.user_api.id
  name        = "$default"
  auto_deploy = true
}

# Additional GET route to retrieve all users
resource "aws_apigatewayv2_route" "list_users" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "GET /users"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}