# The delegated public hosted zone.
#
# This lives in bootstrap/ rather than in envs/app/ for one reason: a hosted
# zone gets a fresh set of NS records every time it is created. If the zone
# were owned by a workspace that gets destroyed between sessions, every
# session would begin with a manual re-delegation at the registrar and a wait
# for the parent zone's TTL. Created once, kept forever, costs $0.50/month.

resource "aws_route53_zone" "lab" {
  name    = var.dns_zone_name
  comment = "aws-lab: persistent delegated zone. NS records are registered at the registrar — never recreate."

  # Refuse to delete a zone that still holds records. Combined with the
  # lifecycle block below this is belt and braces, which is proportionate for
  # the one resource in this repo whose recreation costs manual work.
  force_destroy = false

  tags = {
    Name = var.dns_zone_name
  }

  lifecycle {
    # `terraform destroy` in this directory will fail here, on purpose.
    # bootstrap/ is never destroyed. If you genuinely mean it, remove this
    # block in a commit you have to justify to yourself.
    prevent_destroy = true
  }
}
