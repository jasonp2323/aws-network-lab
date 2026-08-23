# bootstrap/

The chicken-and-egg root module. Runs **locally, with local state, once**, and is
**never destroyed**.

It creates exactly two things:

| Resource | Why it is here and not in a workspace |
|---|---|
| IAM OIDC provider + run role for HCP Terraform | HCP needs this role in order to authenticate to AWS. A workspace cannot create the credential it needs in order to run. |
| Route53 public hosted zone for the delegated subdomain | Recreating a zone issues fresh NS records, forcing re-delegation at the registrar every session. The zone outlives every teardown. |

Nothing else belongs in this directory. VPCs, TGW, RDS, ALB and the rest are
built by the four HCP workspaces described in `plans/tgw-lab/plan.mdx`.

## Prerequisites

- Terraform >= 1.9.
- Admin credentials for the sandbox account in your shell (SSO profile or
  `AWS_PROFILE`) — these are used **only** for this one apply. Every later
  apply runs in HCP under the OIDC role this creates.
- A domain you control at a registrar, so you can add NS records for the
  subdomain.
- Outbound HTTPS to `app.terraform.io`, so the OIDC thumbprint can be read
  from its certificate at plan time.

## Apply

```bash
cd bootstrap
cp example.tfvars terraform.tfvars    # then edit: hcp_organization, hcp_project, dns_zone_name

terraform init
terraform fmt -recursive
terraform validate
terraform plan  -var-file=terraform.tfvars -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Expect 6 resources: the OIDC provider, the role, one managed-policy
attachment, the inline guardrail policy, and the hosted zone.

Then commit the lock file so provider versions are pinned for everyone:

```bash
git add .terraform.lock.hcl && git commit -m "bootstrap: pin provider versions"
```

`terraform.tfstate` and `terraform.tfvars` are gitignored. The state file
describes an IAM role that can administer the account — keep it off GitHub and
off shared drives.

## Delegate the subdomain — the manual step

```bash
terraform output -json route53_name_servers
```

Four hostnames come back, like `ns-1234.awsdns-56.org`. At your **registrar**,
in the DNS records for the *parent* domain, add four `NS` records for the
subdomain label:

```
lab    NS    ns-1234.awsdns-56.org.
lab    NS    ns-567.awsdns-01.net.
lab    NS    ns-89.awsdns-11.com.
lab    NS    ns-2012.awsdns-60.co.uk.
```

Use the label only (`lab`), not the FQDN, unless your registrar asks for the
full name. Trailing dots as shown.

Verify from a resolver that is not your own cache:

```bash
dig +short NS lab.example.com @8.8.8.8
```

You want the four AWS nameservers back, and nothing else. Until this
resolves, **stop** — ACM DNS validation in `envs/app` will hang for the full
72-hour window rather than fail fast, and you will spend that time debugging
the wrong layer.

Two common ways this goes wrong:

- **Records added at the child zone instead of the parent.** Putting NS
  records for `lab.example.com` *inside* the `lab.example.com` zone does
  nothing. Delegation is always a record in the parent.
- **Parent zone TTL.** If you previously had an NXDOMAIN or a different
  delegation for that label, the negative cache can outlast your patience.
  `dig +trace lab.example.com` shows you which nameserver in the chain is
  still answering with the old data.

## Wire up HCP Terraform

```bash
terraform output hcp_wiring
```

1. Create the four workspaces — `aws-lab-platform`, `aws-lab-network`,
   `aws-lab-shared`, `aws-lab-app` — as VCS-driven against this repo, each
   with its **working directory** set to the matching `envs/` path. The
   workspace names must match `hcp_workspace_names` exactly; they are baked
   into the role's trust policy.
2. Create a **variable set** scoped to those four workspaces, with these
   *environment* variables:

   | Key | Value |
   |---|---|
   | `TFC_AWS_PROVIDER_AUTH` | `true` |
   | `TFC_AWS_RUN_ROLE_ARN` | `run_role_arn` output |
   | `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE` | `aws.workload.identity` |
   | `TFC_AWS_RUN_ROLE_SESSION_DURATION` | `3600` |

   The session duration matters. HCP requests 900 seconds unless told
   otherwise, and a full `envs/network` destroy is four TGW attachments at
   roughly five minutes each. A run whose credentials expire mid-destroy
   leaves half-deleted infrastructure and a state file that disagrees with
   reality.
3. Set **manual apply** on all four before merging anything to `main`. These
   workspaces watch this repo; a merge can otherwise start the meter without
   you.
4. Enable **remote state sharing** on `aws-lab-network` and `aws-lab-shared`,
   so the downstream `tfe_outputs` data sources resolve. Without it the
   consumer gets a 404 that reads like a permissions problem.
5. Set `route53_zone_id` and `route53_zone_name` as Terraform variables on
   `aws-lab-app`. Local state means downstream cannot read them automatically.

Confirm the trust actually works before building anything expensive: queue a
plan on `aws-lab-platform` and check the run log shows credentials for the
role. If it fails, compare the token's `sub` against the
`hcp_workspace_subjects` output — a project name mismatch is the usual cause.

## What downstream consumes

| Output | Consumed by | Used for |
|---|---|---|
| `run_role_arn` | all four workspaces | `TFC_AWS_RUN_ROLE_ARN` |
| `route53_zone_id` | `envs/app` | ACM DNS validation records, ALB alias record |
| `route53_zone_name` | `envs/app` | ACM certificate domain name |
| `route53_name_servers` | your registrar | the delegation above, once |
| `oidc_provider_arn` | nothing | reference and troubleshooting |

## The guardrail

The run role is an administrator — a considered choice, argued in
`variables.tf`. It carries one inline `Deny` covering `DeleteHostedZone` on
this zone, deletion or thumbprint changes on the OIDC provider, and deletion
or trust-policy edits on the role itself. A `Deny` beats
`AdministratorAccess`, so a downstream workspace cannot remove the two things
that must survive teardown.

Record-level writes inside the zone stay allowed. `envs/app` needs them.

## Teardown

There isn't one. `terraform destroy` here fails on the hosted zone's
`prevent_destroy`, which is the intended behaviour. Destroy runs go
`app → shared → network → platform` in HCP and stop there.
