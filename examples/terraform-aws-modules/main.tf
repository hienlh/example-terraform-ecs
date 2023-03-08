# * Part 1 - Setup.
locals {
	container_name = "hello-world-container"
	container_port = 8080 # ! Must be same port from our Dockerfile that we EXPOSE
	example = "example-ecs-terraform-aws-modules"
}

provider "aws" {
	region = "ca-central-1"

	default_tags {
		tags = { example = local.example }
	}
}

# * Give Docker permission to pusher Docker Images to AWS.
data "aws_caller_identity" "this" {}
data "aws_ecr_authorization_token" "this" {}
data "aws_region" "this" {}
locals { ecr_address = format("%v.dkr.ecr.%v.amazonaws.com", data.aws_caller_identity.this.account_id, data.aws_region.this.name) }
provider "docker" {
	registry_auth {
		address  = local.ecr_address
		password = data.aws_ecr_authorization_token.this.password
		username = data.aws_ecr_authorization_token.this.user_name
	}
}

module "ecr" {
	source  = "terraform-aws-modules/ecr/aws"
	version = "~> 1.6.0"

	repository_force_delete = true
	repository_name = local.example
	repository_lifecycle_policy = jsonencode({
		rules = [{
			action = { type = "expire" }
			description = "Delete all images except a handful of the newest images"
			rulePriority = 1
			selection = {
				countNumber = 3
				countType = "imageCountMoreThan"
				tagStatus = "any"
			}
		}]
	})
}

# * Build our Image locally with the appropriate name to push our Image
# * to our Repository in AWS.
resource "docker_image" "this" {
	name = format("%v:%v", module.ecr.repository_url, formatdate("YYYY-MM-DD'T'hh-mm-ss", timestamp()))

	build { context = "." }
}

# * Push our Image to our Repository.
resource "docker_registry_image" "this" {
	keep_remotely = true # Do not delete the old image when a new image is built
	name = resource.docker_image.this.name
}

# * Part 3 - Create VPC
data "aws_availability_zones" "available" { state = "available" }
module "vpc" {
	source = "terraform-aws-modules/vpc/aws"
	version = "~> 3.19.0"

	azs = slice(data.aws_availability_zones.available.names, 0, 2) # Span subnetworks across multiple avalibility zones
	cidr = "10.0.0.0/16"
	create_igw = true # Expose public subnetworks to the Internet
	enable_nat_gateway = true # Hide private subnetworks behind NAT Gateway
	private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
	public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
}