# Infrastructure for the rdicidr app (FSL DevOps challenge, Part 2).
# One config serves BOTH environments via Terraform workspaces.
# The workspace name IS the environment name (devel / stage).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key     = "rdicidr/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_canonical_user_id" "current" {}
data "aws_cloudfront_log_delivery_canonical_user_id" "current" {}

locals {
  environment = terraform.workspace
  name        = "${var.project}-${local.environment}"
  account_id  = data.aws_caller_identity.current.account_id

  site_bucket = "${local.name}-site-${local.account_id}"
  log_bucket  = "${local.name}-logs-${local.account_id}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = local.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = contains(["devel", "stage"], terraform.workspace)
      error_message = "Select an environment first: terraform workspace select devel|stage"
    }
  }
}

resource "aws_s3_bucket" "site" {
  bucket        = local.site_bucket
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "logs" {
  bucket        = local.log_bucket
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  depends_on = [aws_s3_bucket_ownership_controls.logs]
  bucket     = aws_s3_bucket.logs.id

  access_control_policy {
    owner {
      id = data.aws_canonical_user_id.current.id
    }

    grant {
      grantee {
        type = "CanonicalUser"
        id   = data.aws_canonical_user_id.current.id
      }
      permission = "FULL_CONTROL"
    }

    grant {
      grantee {
        type = "CanonicalUser"
        id   = data.aws_cloudfront_log_delivery_canonical_user_id.current.id
      }
      permission = "FULL_CONTROL"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.log_retention_days
    }
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.name}-oac"
  description                       = "OAC for ${local.name} site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  depends_on          = [aws_s3_bucket_acl.logs]
  enabled             = var.distribution_enabled
  default_root_object = "index.html"
  price_class         = var.price_class
  comment             = local.name
  tags                = local.common_tags

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-${local.name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${local.name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    include_cookies = false
    prefix          = "cloudfront/"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "site" {
  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json
}