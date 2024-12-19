terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.64.0"
    } 
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_iam_policy_document" "change-data-capture-document-role-cluster-rds" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "change-data-capture-ducument-policy-cluster-rds" {
  statement {
    sid = "ChangeDataCapturePolicy"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]

    resources = [
      "arn:aws:lambda:us-east-1:AWS_ACCOUNT_NUMBER:function:${var.lambda_name}"
    ]
  }
}

resource "aws_iam_policy" "change-data-capture-policy-cluster-rds" {
  name = "change-data-capture-policy"
  policy = data.aws_iam_policy_document.change-data-capture-ducument-policy-cluster-rds.json
}

resource "aws_iam_role" "change-data-capture-role-cluster-rds" {
  name               = "change-data-capture-role"
  assume_role_policy = data.aws_iam_policy_document.change-data-capture-document-role-cluster-rds.json
}

resource "aws_iam_role_policy_attachment" "change-data-capture-role-attachment-cluster-rds" {
  policy_arn = aws_iam_policy.change-data-capture-policy-cluster-rds.arn
  role = aws_iam_role.change-data-capture-role-cluster-rds.name
}

module "aurora_postgresql_v2" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "9.10.0"

  name            = "change-data-capture" 
  database_name   = "cdcstore"
  engine          = "aurora-postgresql"
  engine_mode     = "provisioned"
  engine_version  = "16.1"
  instance_class  = "db.serverless"
  instances = {
    store = {
      identifier     = "store"
    }
  }

  serverlessv2_scaling_configuration = {
    max_capacity = 1.0
    min_capacity = 0.5
  }
  vpc_id               = "VPC_ID"
  db_subnet_group_name = "SUBNET_GROUP_NAME"
  security_group_name = "default"
  publicly_accessible  = true
  master_username = "cdcStoreDevTo"
  apply_immediately = true
  iam_roles = {
    lambda = {
      role_arn     = aws_iam_role.change-data-capture-role-cluster-rds.arn
      feature_name = "Lambda"
    }
  }

  security_group_rules = {
    ex1_ingress = {
      cidr_blocks = ["0.0.0.0/0"]
      from_port = "5432"
      to_port = "5432"
      protocol = "tcp"
      type = "ingress"
    }

    ex2_ingress = {
      cidr_blocks = ["0.0.0.0/0"]
      from_port = "443"
      to_port = "443"
      protocol = "tcp"
      type = "ingress"
    }

    ex3_egress = {
      cidr_blocks = ["0.0.0.0/0"]
      from_port = "443"
      to_port = "443"
      protocol = "tcp"
      type = "egress"
    }

    ex4_egress = {
      cidr_blocks = ["0.0.0.0/0"]
      from_port = "5432"
      to_port = "5432"
      protocol = "tcp"
      type = "egress"
    }     
  }

  storage_encrypted   = false
  monitoring_interval = 10
  skip_final_snapshot = true

  tags = {
    Environment = "dev-to"
    Terraform   = "true"
    Type        = "content writer"
  }
}


data "aws_iam_policy_document" "change-data-capture-document-lambda-role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "change-data-capture-ducument-policy-cloud-watch" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "change-data-capture-role-lambda" {
  name               = "change-data-capture-lambda-document"
  assume_role_policy = data.aws_iam_policy_document.change-data-capture-document-lambda-role.json
}

resource "aws_iam_policy" "change-data-capture-lambda-policy" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.change-data-capture-ducument-policy-cloud-watch.json
}

resource "aws_iam_role_policy_attachment" "change-data-capture-policy-attachment-lambda" {
  policy_arn = aws_iam_policy.change-data-capture-lambda-policy.arn
  role       = aws_iam_role.change-data-capture-role-lambda.name
}

data "archive_file" "change-data-capture-archive-file" {
  type        = "zip"
  source_dir  = "../src"
  output_path = "change-data-capture-function-payload.zip"
}

resource "aws_cloudwatch_log_group" "change-data-capture-cloudwatch" {
  name              = "/aws/lambda/${var.lambda_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "change-data-capture-function" {
  filename      = "change-data-capture-function-payload.zip"
  function_name = var.lambda_name
  role          = aws_iam_role.change-data-capture-role-lambda.arn
  handler       = "main.handler"
  source_code_hash = data.archive_file.change-data-capture-archive-file.output_base64sha256
  runtime = "nodejs20.x"
  depends_on = [ 
    aws_iam_role_policy_attachment.change-data-capture-policy-attachment-lambda, 
    aws_cloudwatch_log_group.change-data-capture-cloudwatch]
}