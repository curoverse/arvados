resource "aws_route53_record" "txt_record" {
  for_each = var.zone_records_TXT

  zone_id         = var.zone_id
  name            = lookup(each.value, "name", each.key)
  type            = "TXT"
  ttl             = lookup(each.value, "ttl", 600)

  records         = lookup(each.value, "records", null)
  allow_overwrite = lookup(each.value, "allow_overwrite", null)
}
