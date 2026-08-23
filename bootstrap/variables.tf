variable "aws_region" {
  description = "Region for the lab. Route53 is global, but the provider still needs one."
  type        = string
  default     = "us-east-1"
}

# --- HCP Terraform identity ------------------------------------------------

variable "hcp_hostname" {
  description = <<-EOT
    HCP Terraform hostname. Also used to build the IAM condition keys
    (`<hostname>:aud`, `<hostname>:sub`), so it must match the OIDC issuer
    exactly. Change only for Terraform Enterprise.
  EOT
  type        = string
  default     = "app.terraform.io"
}

variable "hcp_organization" {
  description = "HCP Terraform organization name. Appears verbatim in the OIDC token subject."
  type        = string

  validation {
    condition     = length(trimspace(var.hcp_organization)) > 0
    error_message = "hcp_organization must be set — it is what scopes the role to your org."
  }
}

variable "hcp_project" {
  description = <<-EOT
    HCP Terraform project containing the four workspaces. Part of the token
    subject. Use "Default" if you did not create a project. Set to "*" to
    match any project, at the cost of a looser trust policy.
  EOT
  type        = string
  default     = "Default"
}

variable "hcp_workspace_names" {
  description = <<-EOT
    Workspaces allowed to assume the run role. These are the four from the
    plan; the local bootstrap/ root is not a workspace and is not listed.
  EOT
  type        = list(string)
  default = [
    "aws-lab-platform",
    "aws-lab-network",
    "aws-lab-shared",
    "aws-lab-app",
  ]

  validation {
    condition     = length(var.hcp_workspace_names) > 0
    error_message = "At least one workspace must be allowed, or the role is unassumable."
  }
}

variable "hcp_run_phases" {
  description = <<-EOT
    Run phases the role may be assumed in. "plan" and "apply" is the useful
    pair; HCP also emits "pre_plan"/"post_plan" style phases for run tasks,
    which this lab does not use.
  EOT
  type        = list(string)
  default     = ["plan", "apply"]
}

variable "hcp_workload_identity_audience" {
  description = <<-EOT
    Value of TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE. Must match the `aud` claim in
    the token HCP presents. Leave at the default unless you override it in the
    variable set too.
  EOT
  type        = string
  default     = "aws.workload.identity"
}

# --- Run role --------------------------------------------------------------

variable "run_role_name" {
  description = "Name of the IAM role HCP Terraform assumes. Its ARN becomes TFC_AWS_RUN_ROLE_ARN."
  type        = string
  default     = "hcp-terraform-aws-lab"
}

variable "run_role_policy_arns" {
  description = <<-EOT
    Managed policies on the run role.

    AdministratorAccess by default, and that is a considered choice for this
    lab rather than laziness: the workspaces build VPCs, TGW, RDS, ALB, ACM,
    CloudTrail, IAM instance profiles and CloudWatch, and the whole point of
    the environment is that the *only* thing failing is the thing you broke on
    purpose. An AccessDenied mid-scenario is noise in exactly the signal you
    are practising on. This assumes the clean sandbox account the plan calls
    for; do not reuse this pattern in a shared account.
  EOT
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "run_role_max_session_duration" {
  description = <<-EOT
    Ceiling on the assumed-role session, in seconds. HCP requests 900s unless
    you set TFC_AWS_RUN_ROLE_SESSION_DURATION, and 900s is too short here — a
    full network destroy is four TGW attachments at roughly five minutes each.
  EOT
  type        = number
  default     = 3600

  validation {
    condition     = var.run_role_max_session_duration >= 3600 && var.run_role_max_session_duration <= 43200
    error_message = "Must be between 3600 and 43200 seconds (the IAM-imposed range)."
  }
}

# --- DNS -------------------------------------------------------------------

variable "dns_zone_name" {
  description = <<-EOT
    The delegated subdomain, e.g. "lab.example.com". Created here and never
    destroyed: recreating a hosted zone issues fresh NS records and forces
    re-delegation at the registrar.
  EOT
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", var.dns_zone_name))
    error_message = "dns_zone_name must be a bare lowercase FQDN with no trailing dot, e.g. lab.example.com."
  }
}

# --- Tagging ---------------------------------------------------------------

variable "tags" {
  description = "Default tags applied to everything this root module creates."
  type        = map(string)
  default = {
    Project   = "aws-lab"
    Component = "bootstrap"
    ManagedBy = "terraform-local-state"
    Lifecycle = "persistent"
  }
}
