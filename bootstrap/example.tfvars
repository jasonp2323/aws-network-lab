# Copy to terraform.tfvars (gitignored) and fill in.
#   cp example.tfvars terraform.tfvars

# Your HCP Terraform organization, exactly as it appears in the URL
# app.terraform.io/app/<organization>.
hcp_organization = "your-hcp-org"

# The project holding the four workspaces. "Default" if you have not made one.
# "*" matches any project, at the cost of a looser trust policy.
hcp_project = "Default"

# The subdomain you are delegating. No trailing dot.
dns_zone_name = "lab.example.com"

# --- Rarely changed --------------------------------------------------------

# aws_region                    = "us-east-1"
# run_role_name                 = "hcp-terraform-aws-lab"
# run_role_max_session_duration = 3600
# hcp_workspace_names           = ["aws-lab-platform", "aws-lab-network", "aws-lab-shared", "aws-lab-app"]
