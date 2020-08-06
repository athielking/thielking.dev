# Configure Terraform
terraform {
  required_version = ">= 0.12"

  # Configure the remote backend using an azure storage container 
  backend "azurerm" {
    storage_account_name = "terraformstorage501"
    container_name       = "terraform"
    key                  = "thielking.dev.tfstate"
  }
}

locals {
    dns_name = "thielking.dev"
    s3_origin_id = "s3-${local.dns_name}"
}

provider "aws" {
    version = "~> 3.0"
    region = "us-east-1"
}

data "aws_acm_certificate" "cert" {
 provider = "aws"
 domain = "*.${local.dns_name}"
 statuses = ["ISSUED"]
}

resource "aws_s3_bucket" "b" {
    bucket = local.dns_name
    
    website {
        index_document = "index.html"
        error_document = "not-found.html"
    }
    policy = <<POLICY
{
"Version": "2012-10-17",
"Id": "Policy1565527662639",
"Statement": [
    {
        "Sid": "Stmt1565527657378",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::${local.dns_name}/*"
    }
]
}
  POLICY
}


resource "aws_s3_bucket_public_access_block" "b" {
    bucket = "${aws_s3_bucket.b.id}"

    block_public_policy = false
    block_public_acls = true
    ignore_public_acls = true
}

resource "aws_route53_zone" "primary" {
    name = "thielking.dev"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  
  aliases = [local.dns_name]
  origin {
      domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
      origin_id = "${local.s3_origin_id}"
  }

  default_cache_behavior {
      allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods = ["GET", "HEAD"]
      target_origin_id = "${local.s3_origin_id}"
      min_ttl = 0
      default_ttl = 86400
      max_ttl = 31536000
      viewer_protocol_policy = "redirect-to-https"
      forwarded_values {
          query_string = false

          cookies {
              forward = "none"
          }
      }
  }
  
  restrictions {
      geo_restriction {
        restriction_type = "none"
      }
  }

  viewer_certificate {
    acm_certificate_arn = "${data.aws_acm_certificate.cert.arn}"
    ssl_support_method = "sni-only"
  }
  
  default_root_object = "index.html"
  price_class = "PriceClass_200"
  enabled = true
  is_ipv6_enabled = true
  
}

resource "aws_route53_record" "route" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = local.dns_name
  type = "A"
  
  alias {
      name = "${aws_cloudfront_distribution.s3_distribution.domain_name}"
      zone_id = "${aws_cloudfront_distribution.s3_distribution.hosted_zone_id}"
      evaluate_target_health = false
  }
}