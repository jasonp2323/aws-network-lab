# aws-lab

A deliberately breakable AWS environment for practising cloud/SRE troubleshooting and root
cause analysis. This is **not** a product. Its purpose is that things go wrong in ways that
can be diagnosed from logs and metrics, so the design optimises for *evidence*, not uptime.

The central constraint: **Transit Gateway routing is load-bearing.** The WordPress app must
be unable to reach its database or the internet if TGW routing is wrong. Any change that
makes the app work regardless of TGW state (a peering connection, a NAT gateway in the app
VPC, a public subnet shortcut) defeats the entire point and must be rejected.

## Read this first

The full specification lives at **`plans/tgw-lab/plan.mdx`**. It contains the CIDR
allocation table, the four TGW route tables with their exact static routes, per-subnet VPC
route tables, module layout, apply order, cost model, observability wiring, and six failure
injection scenarios with their expected symptoms and proving log source. Read it before
writing any Terraform. Do not re-derive its decisions.

`preview.html` in that folder is a rendered copy of the same content, generated from the
MDX — never edit it by hand.

## Locked decisions

These are settled. Do not reopen them.

| | |
|---|---|
| Region | `us-east-1`, clean sandbox account |
| State | HCP Terraform, VCS-driven workspaces (not S3/DynamoDB) |
| AWS auth | OIDC dynamic credentials, no static keys anywhere |
| Access | SSM Session Manager only — no public IPs, no bastion, no SSH keys |
| Endpoints | Interface endpoints (ssm, ssmmessages, ec2messages, logs) in **every** VPC |
| DNS | A subdomain delegated to Route53; the hosted zone is persistent |
| Lifecycle | Everything destroyable; torn down between sessions to stop the meter |

CIDRs use the second octet as the VPC identifier so any address is placeable on sight:
egress hub `10.0.0.0/16`, app spoke `10.10.0.0/16`, shared spoke `10.20.0.0/16`,
dev spoke `10.30.0.0/16`.

## Answered design questions

All four are settled. Do not reopen them or offer alternatives.

1. **Fourth VPC (`dev` spoke): yes.** `10.30.0.0/16`, one t3.micro, one workload subnet, one
   `/28` attachment subnet, single AZ. It exists solely to make isolation provable — a curl
   that must time out plus a matching absence in the flow logs. `envs/network/` therefore
   builds **four** attachments and **four** TGW route tables. `tgw-rt-app` must have no route
   to `10.30.0.0/16`, and `tgw-rt-dev` no route to `10.10.0.0/16`; those two absences *are*
   the control being tested, which is why default association and default propagation stay
   disabled.
2. **WordPress: stateless.** No EFS for `wp-content`. Uploads are expected to die on instance
   replacement — that is intended, not a bug to fix mid-build.
3. **AMI: Amazon Linux 2023 + user-data.** Not Ubuntu, not a pre-baked Packer image.
   WordPress is fetched at boot on purpose: it keeps the NAT and TGW path load-bearing during
   instance launch, which is what failure scenario 2 depends on. A pre-baked AMI would delete
   that failure mode.
4. **Prometheus: scrape `node_exporter` on the app instances over the TGW.** Not local
   metrics only. This gives a second, independent witness whose Grafana view goes blank when
   shared→app routing breaks, exercising the return direction of the design.

## Working agreement

Build **one module at a time and stop.** Jason verifies each before the next begins. Do not
chain modules together or run ahead to a finished tree. Apply order and inter-module
dependencies are in the plan.

`bootstrap/` is first and is special: it uses **local state**, because it creates the IAM
OIDC role that HCP needs in order to authenticate at all. It also holds the Route53 hosted
zone, which must persist — recreating it issues new NS records and forces re-delegation at
the registrar every session.

## Cost

Roughly **$0.54/hr** with everything up — TGW attachments $0.200, interface endpoints
$0.160, NAT $0.045, EC2 $0.062, RDS $0.045, ALB $0.023. About $1.60 for a three-hour
session; near $390/month if left running. TGW attachments and interface endpoints bill
hourly whether or not traffic flows, which is why teardown between sessions is mandatory
rather than tidy.

## If you are running in a sandbox without AWS credentials

Expected — most of this work is authoring, not applying. Write the Terraform, then verify
as far as the environment allows:

```bash
terraform fmt -recursive
terraform init -backend=false && terraform validate
```

If the sandbox blocks the provider download, say so plainly and hand back unvalidated code
labelled as such. Do not fake a validation result, and do not attempt `terraform plan`
against real AWS.

## Danger: VCS-driven workspaces react to pushes

HCP workspaces watch this repo. A merge to `main` can trigger a real apply and start the
meter. Work on a branch and open a PR — that yields speculative plans, which are exactly
the review signal wanted. Confirm workspaces are set to **manual apply** before merging
anything that creates billable resources.
