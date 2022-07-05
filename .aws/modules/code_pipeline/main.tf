data "aws_partition" "current" {
}

data "aws_caller_identity" "current" {
}

locals {
  github_owner  = "enterprise-oss"
  github_repo   = "osso"
  github_branch = "docker"
}

resource "aws_s3_bucket" "source" {
  bucket        = "osso-source"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "source" {
  bucket = aws_s3_bucket.source.id
  acl    = "private"
}

data "aws_iam_policy_document" "codepipeline_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_role.json
}

/* policies */
data "aws_iam_policy_document" "codepipeline_policy" {
  statement {
    effect = "Allow"
    resources = [
      aws_s3_bucket.source.arn,
      "${aws_s3_bucket.source.arn}/*"
    ]
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:List*",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
  }
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]
  }
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ecs:*",
      "events:DescribeRule",
      "events:DeleteRule",
      "events:ListRuleNamesByTarget",
      "events:ListTargetsByRule",
      "events:PutRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfiles",
      "iam:ListRoles",
      "logs:CreateLogGroup",
      "logs:DescribeLogGroups",
      "logs:FilterLogEvents"
    ]
  }
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "iam:PassRole"
    ]
    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values = [
        "ecs-tasks.amazonaws.com"
      ]
    }
  }
  statement {
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:iam::*:role/ecsInstanceRole*"]
    actions = [
      "iam:PassRole"
    ]
    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values = [
        "ec2.${data.aws_partition.current.dns_suffix}"
      ]
    }
  }
  statement {
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:iam::*:role/ecsAutoscaleRole*"]
    actions = [
      "iam:PassRole"
    ]
    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values = [
        "application-autoscaling.${data.aws_partition.current.dns_suffix}"
      ]
    }
  }
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "iam:CreateServiceLinkedRole"
    ]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "spot.amazonaws.com",
        "spotfleet.amazonaws.com"
      ]
    }
  }
  statement {
    effect = "Allow"
    resources = [
      aws_codestarconnections_connection.github.arn
    ]
    actions = [
      "codestar-connections:UseConnection"
    ]
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "codepipeline_policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}

/*
/* CodeBuild
*/
data "aws_iam_policy_document" "codebuild_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild_role" {
  name               = "codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_role.json
}

data "aws_iam_policy_document" "codebuild_policy" {
  statement {
    effect = "Allow"
    resources = [
      aws_s3_bucket.source.arn,
      "${aws_s3_bucket.source.arn}/*"
    ]
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:List*",
      "s3:PutObject"
    ]
  }
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ecr:GetAuthorizationToken",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecs:RunTask",
      "iam:PassRole"
    ]
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name   = "codebuild-policy"
  role   = aws_iam_role.codebuild_role.id
  policy = data.aws_iam_policy_document.codebuild_policy.json
}

data "template_file" "buildspec" {
  template = file("${path.module}/buildspec.yml")

  vars = {
    cluster_name       = var.ecs_cluster_name
    subnet_id          = var.run_task_subnet_id
    security_group_ids = join(",", var.run_task_security_group_ids)
  }
}

resource "aws_codebuild_project" "osso_build" {
  name          = "osso-codebuild"
  build_timeout = "10"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0" // https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-available.html
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = var.repository_name
    }

    environment_variable {
      name  = "REPOSITORY_URI"
      value = var.repository_url
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = data.template_file.buildspec.rendered
  }
}

/* CodePipeline */
resource "aws_codestarconnections_connection" "github" {
  name          = "github-connection"
  provider_type = "GitHub"
}

resource "aws_codepipeline" "pipeline" {
  name     = "osso-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.source.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${local.github_owner}/${local.github_repo}"
        BranchName       = local.github_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source"]
      output_artifacts = ["imagedefinitions"]

      configuration = {
        ProjectName = "osso-codebuild"
      }
    }
  }

  stage {
    name = "Production"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["imagedefinitions"]
      version         = "1"

      configuration = {
        ClusterName = var.ecs_cluster_name
        ServiceName = var.ecs_service_name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}