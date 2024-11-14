# Project Name

Line By Line Services

## Description

This project contains a Lambda function using the Echo framework for a user CRUD API on AWS. It uses Terraform for infrastructure as code and Ent for database modeling.

## Prerequisites

- Go installed
- AWS CLI configured
- Terraform installed

## Setup

1. Clone the repository and navigate to the project directory.

2. Install dependencies:

   ```bash
   go mod tidy
   ```

## Deployment

### Step 1: Build and Package Lambda

To build the Go binary for Lambda and package it into a zip file:

```bash
GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
zip function.zip bootstrap
```

### Step 2: Deploy with Terraform

Ensure Terraform is initialized:

```bash
terraform init
```

Apply the Terraform configuration to create the necessary AWS infrastructure:

```bash
terraform apply
```

### Step 3: Update Lambda Function Code

After any code changes, re-build and upload the Lambda zip file:

```bash
GOOS=linux GOARCH=amd64 go build -o bootstrap main.go
zip function.zip bootstrap

aws lambda update-function-code --function-name UserCrudFunction --zip-file fileb://function.zip
```

## Testing

### Testing Locally

To test locally using `curl`, ensure the API Gateway endpoint is accessible. For example:

```bash
curl -X GET "https://api.lbls.xyz/users"
```

Or, for a POST request:

```bash
curl -X POST "https://api.lbls.xyz/users" -H "Content-Type: application/json" -d '{"name": "John Doe", "email": "john@example.com"}'
```

### Testing Lambda Directly

To test the Lambda function directly:

1. Go to the AWS Lambda console.
2. Use a test JSON event, e.g., for GET /users:
   ```json
   {
     "httpMethod": "GET",
     "path": "/users",
     "headers": {
       "Content-Type": "application/json"
     },
     "pathParameters": {},
     "queryStringParameters": {}
   }
   ```

## Directory Structure

```
- README.md
- .terraform/
- bootstrap
- config/
- ent/
- function.zip
- go.mod
- go.sum
- handlers/
- main.go
- terraform.tfstate
- terraform.tfstate.backup
```

## License

Proprietary License

This project and its contents are proprietary and confidential. Unauthorized copying, distribution, or modification of any files, via any medium, is strictly prohibited. All rights reserved by Line By Line, LLC.

Usage of this project is allowed only with explicit permission from Line By Line, LLC.
