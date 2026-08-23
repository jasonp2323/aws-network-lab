# bootstrap/ keeps local state, so downstream workspaces cannot read these
# with `tfe_outputs` or `terraform_remote_state`. They are copied by hand into
# HCP — once, since none of them change between sessions.
#
# `terraform output hcp_wiring` prints everything you need in one block.

output "oidc_provider_arn" {
  description = "IAM OIDC provider for HCP Terraform. Referenced by the run role's trust policy only."
  value       = aws_iam_openid_connect_provider.hcp.arn
}

output "run_role_arn" {
  description = "Value for TFC_AWS_RUN_ROLE_ARN in the OIDC variable set. Consumed by all four workspaces."
  value       = aws_iam_role.hcp_run.arn
}

output "run_role_name" {
  description = "Name of the run role, for `aws sts get-caller-identity` sanity checks."
  value       = aws_iam_role.hcp_run.name
}

output "hcp_workspace_subjects" {
  description = "The exact OIDC subject claims the trust policy accepts. Diff against a run's token when an assume-role fails."
  value       = local.workspace_subjects
}

output "route53_zone_id" {
  description = "Hosted zone ID. Consumed by envs/app for ACM DNS validation records and the ALB alias record."
  value       = aws_route53_zone.lab.zone_id
}

output "route53_zone_arn" {
  description = "Hosted zone ARN."
  value       = aws_route53_zone.lab.arn
}

output "route53_zone_name" {
  description = "Zone apex, e.g. lab.example.com. Consumed by envs/app for the ACM certificate's domain name."
  value       = aws_route53_zone.lab.name
}

output "route53_name_servers" {
  description = "Register these four NS records at your registrar against the parent domain. Do this once; they must never churn."
  value       = aws_route53_zone.lab.name_servers
}

output "hcp_wiring" {
  description = "Everything the four HCP workspaces need, ready to paste."
  value = {
    variable_set = {
      TFC_AWS_PROVIDER_AUTH              = "true"
      TFC_AWS_RUN_ROLE_ARN               = aws_iam_role.hcp_run.arn
      TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE = var.hcp_workload_identity_audience
      TFC_AWS_RUN_ROLE_SESSION_DURATION  = tostring(var.run_role_max_session_duration)
    }
    terraform_variables = {
      route53_zone_id   = aws_route53_zone.lab.zone_id
      route53_zone_name = aws_route53_zone.lab.name
    }
    attach_to_workspaces = var.hcp_workspace_names
  }
}
