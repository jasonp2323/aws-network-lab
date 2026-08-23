# IAM OIDC trust for HCP Terraform dynamic credentials.
#
# The four workspaces set TFC_AWS_PROVIDER_AUTH=true and TFC_AWS_RUN_ROLE_ARN
# to the role below. HCP mints a short-lived OIDC token per run phase, AWS
# validates it against the provider below, and the run gets temporary keys.
# No static access keys exist anywhere in this lab.

data "tls_certificate" "hcp" {
  url = "https://${var.hcp_hostname}"
}

resource "aws_iam_openid_connect_provider" "hcp" {
  url            = "https://${var.hcp_hostname}"
  client_id_list = [var.hcp_workload_identity_audience]

  # AWS ignores the thumbprint for issuers backed by a well-known CA, but the
  # API still accepts one and deriving it beats hardcoding a fingerprint that
  # rotates. Requires egress to app.terraform.io from wherever you run this.
  thumbprint_list = [data.tls_certificate.hcp.certificates[0].sha1_fingerprint]

  tags = {
    Name = "hcp-terraform-oidc"
  }
}

locals {
  # Subject claim format:
  #   organization:<org>:project:<project>:workspace:<workspace>:run_phase:<phase>
  #
  # Enumerated rather than wildcarded on the workspace segment, so a fifth
  # workspace created by accident in this org cannot assume the role.
  workspace_subjects = flatten([
    for ws in var.hcp_workspace_names : [
      for phase in var.hcp_run_phases :
      "organization:${var.hcp_organization}:project:${var.hcp_project}:workspace:${ws}:run_phase:${phase}"
    ]
  ])
}

data "aws_iam_policy_document" "hcp_assume_role" {
  statement {
    sid     = "HCPTerraformDynamicCredentials"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.hcp.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.hcp_hostname}:aud"
      values   = [var.hcp_workload_identity_audience]
    }

    # StringLike, not StringEquals: it lets hcp_project be set to "*" for an
    # org that has not organised its workspaces into projects yet.
    condition {
      test     = "StringLike"
      variable = "${var.hcp_hostname}:sub"
      values   = local.workspace_subjects
    }
  }
}

resource "aws_iam_role" "hcp_run" {
  name                 = var.run_role_name
  description          = "Assumed by HCP Terraform runs for the aws-lab workspaces via OIDC."
  assume_role_policy   = data.aws_iam_policy_document.hcp_assume_role.json
  max_session_duration = var.run_role_max_session_duration

  tags = {
    Name = var.run_role_name
  }
}

resource "aws_iam_role_policy_attachment" "hcp_run" {
  for_each = toset(var.run_role_policy_arns)

  role       = aws_iam_role.hcp_run.name
  policy_arn = each.value
}

# --- Guardrail over the two things bootstrap/ owns -------------------------
#
# The run role is an administrator, which means an `envs/` workspace could in
# principle delete the hosted zone or this role itself. Both are the things
# that must survive every teardown, so an explicit Deny fences them off. A
# Deny beats the Allow in AdministratorAccess, and unwinding it is a
# deliberate local `terraform apply` here rather than a downstream accident.
#
# Record-level writes inside the zone stay allowed — envs/app needs them for
# ACM DNS validation and the ALB alias.

data "aws_iam_policy_document" "protect_bootstrap" {
  statement {
    sid    = "ProtectPersistentHostedZone"
    effect = "Deny"
    actions = [
      "route53:DeleteHostedZone",
      "route53:UpdateHostedZoneComment",
    ]
    resources = [aws_route53_zone.lab.arn]
  }

  statement {
    sid    = "ProtectOIDCProvider"
    effect = "Deny"
    actions = [
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
    ]
    resources = [aws_iam_openid_connect_provider.hcp.arn]
  }

  statement {
    sid    = "ProtectRunRoleFromItself"
    effect = "Deny"
    actions = [
      "iam:DeleteRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = [aws_iam_role.hcp_run.arn]
  }
}

resource "aws_iam_role_policy" "protect_bootstrap" {
  name   = "protect-bootstrap-resources"
  role   = aws_iam_role.hcp_run.id
  policy = data.aws_iam_policy_document.protect_bootstrap.json
}
