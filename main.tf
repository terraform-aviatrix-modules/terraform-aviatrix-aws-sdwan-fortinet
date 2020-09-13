#Edge VPC
resource "aws_vpc" "sdwan" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = length(var.name) > 0 ? "avx-${var.name}-sdwan-edge" : "avx-${var.region}-sdwan-edge"
  }
}

#Subnets
resource "aws_subnet" "sdwan_1" {
  availability_zone = "${var.region}${var.az1}"
  vpc_id            = aws_vpc.sdwan.id
  cidr_block        = cidrsubnet(var.cidr, 1, 0)
}

resource "aws_subnet" "sdwan_2" {
  availability_zone = "${var.region}${var.az2}"
  vpc_id            = aws_vpc.sdwan.id
  cidr_block        = cidrsubnet(var.cidr, 1, 1)
}

#IGW
resource "aws_internet_gateway" "sdwan" {
  vpc_id = aws_vpc.sdwan.id
}

#Default route
resource "aws_route" "default_vpc1" {
  route_table_id         = aws_vpc.sdwan.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.sdwan.id
}

#Security Group
resource "aws_security_group" "sdwan" {
  name   = "all_traffic"
  vpc_id = aws_vpc.sdwan.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Random string for unique s3 bucket
resource "random_string" "bucket" {
  length  = 16
  special = false
}

#Random string for secret pre-shared-key
resource "random_string" "psk" {
  length  = 100
  special = false #Long key, without special chars to prevent issues.
}

#AWS Bootstrap environment for FortiGate
resource "aws_s3_bucket" "bootstrap" {
  bucket = "${var.name}-sdwan-bootstrap-${random_string.bucket}"
  acl    = "private"
}

#Create bootstrap configs based on template files
locals {
  template-single = templatefile("${path.module}/bootstrap/headend-single.tpl", {
    name           = length(var.name) > 0 ? var.name : var.region
    ASN            = var.aviatrix_asn
    REMASN         = var.sdwan_asn
    pre-shared-key = random_string.psk
    tunnel1_ip     = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 0), 2)
    tunnel1_rem    = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 0), 1)
    tunnel1_mask   = cidrnetmask(cidrsubnet(var.tunnel_cidr, 2, 0))
    tunnel2_ip     = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 1), 2)
    tunnel2_rem    = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 1), 1)
    tunnel2_mask   = cidrnetmask(cidrsubnet(var.tunnel_cidr, 2, 1))
    transit_gw     = data.aviatrix_transit_gateway.default.public_ip
    transit_gw_ha  = data.aviatrix_transit_gateway.default.ha_public_ip
    password       = var.fortigate_password
    }
  )
  template-1 = templatefile("${path.module}/bootstrap/headend-ha.tpl", {
    name           = length(var.name) > 0 ? var.name : var.region
    ASN            = var.aviatrix_asn
    REMASN         = var.sdwan_asn
    pre-shared-key = "${random_string.psk}-headend1"
    headend_nr     = 1
    tunnel1_ip     = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 0), 2)
    tunnel1_rem    = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 0), 1)
    tunnel1_mask   = cidrnetmask(cidrsubnet(var.tunnel_cidr, 2, 0))
    tunnel2_ip     = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 1), 2)
    tunnel2_rem    = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 1), 1)
    tunnel2_mask   = cidrnetmask(cidrsubnet(var.tunnel_cidr, 2, 1))
    peerip         = cidrhost(aws_subnet.sdwan_2.cidr_block, 10)
    transit_gw     = data.aviatrix_transit_gateway.default.public_ip
    transit_gw_ha  = data.aviatrix_transit_gateway.default.ha_public_ip
    password       = var.fortigate_password
    }
  )
  template-2 = templatefile("${path.module}/bootstrap/headend-ha.tpl", {
    name           = length(var.name) > 0 ? var.name : var.region
    ASN            = var.aviatrix_asn
    REMASN         = var.sdwan_asn
    pre-shared-key = "${random_string.psk}-headend2"
    headend_nr     = 2
    tunnel1_ip     = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 2), 2)
    tunnel1_rem    = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 2), 1)
    tunnel1_mask   = cidrnetmask(cidrsubnet(var.tunnel_cidr, 2, 2))
    tunnel2_ip     = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 3), 2)
    tunnel2_rem    = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 3), 1)
    tunnel2_mask   = cidrnetmask(cidrsubnet(var.tunnel_cidr, 2, 3))
    peerip         = cidrhost(aws_subnet.sdwan_1.cidr_block, 10)
    transit_gw     = data.aviatrix_transit_gateway.default.public_ip
    transit_gw_ha  = data.aviatrix_transit_gateway.default.ha_public_ip
    password       = var.fortigate_password
    }
  )
}

#Create the bootstrap files
resource "local_file" "template_single" {
  count    = var.ha_gw ? 0 : 1
  content  = local.template-single
  filename = "${path.module}/bootstrap/sdwan.conf"
}

resource "local_file" "template_1" {
  count    = var.ha_gw ? 1 : 0
  content  = local.template-1
  filename = "${path.module}/bootstrap/sdwan-1.conf"
}

resource "local_file" "template_2" {
  count    = var.ha_gw ? 1 : 0
  content  = local.template-2
  filename = "${path.module}/bootstrap/sdwan-2.conf"
}

#bootstrap config files for FortiGate SDWAN
resource "aws_s3_bucket_object" "config" {
  count  = var.ha_gw ? 0 : 1
  bucket = aws_s3_bucket.bootstrap.id
  key    = "sdwan_config.conf"
  source = local_file.template_single[0].filename
}

resource "aws_s3_bucket_object" "config_1" {
  count  = var.ha_gw ? 1 : 0
  bucket = aws_s3_bucket.bootstrap.id
  key    = "sdwan-a_config.conf"
  source = local_file.template_1[0].filename
}

resource "aws_s3_bucket_object" "config_2" {
  count  = var.ha_gw ? 1 : 0
  bucket = aws_s3_bucket.bootstrap.id
  key    = "sdwan-b_config.conf"
  source = local_file.template_2[0].filename
}

#SDWAN Headend (non-HA)
resource "aws_instance" "headend" {
  count                       = var.ha_gw ? 0 : 1
  ami                         = data.aws_ami.fortios-on-demand.id
  instance_type               = var.instance_size
  subnet_id                   = aws_subnet.sdwan_1.id
  associate_public_ip_address = true
  security_groups             = [aws_security_group.sdwan.id]
  lifecycle {
    ignore_changes = [security_groups]
  }
  iam_instance_profile = var.iam_role_name
  source_dest_check    = false
  private_ip           = cidrhost(aws_subnet.sdwan_1.cidr_block, 10)
  user_data            = <<EOF
  {
    "bucket" : "${aws_s3_bucket.bootstrap.bucket}",
    "region" : "${var.region}",
    "config" : "/${aws_s3_bucket_object.config.key}",
  }
  EOF

  depends_on = [aws_s3_bucket_object.config]
  tags = {
    Name = length(var.name) > 0 ? "${var.name}" : "avx-sdwan-edge-headend",
  }
}

#SDWAN Headend 1 (HA)
resource "aws_instance" "headend_1" {
  count                       = var.ha_gw ? 1 : 0
  ami                         = data.aws_ami.fortios-on-demand.id
  instance_type               = var.instance_size
  subnet_id                   = aws_subnet.sdwan_1.id
  associate_public_ip_address = true
  security_groups             = [aws_security_group.sdwan.id]
  lifecycle {
    ignore_changes = [security_groups]
  }
  iam_instance_profile = var.iam_role_name
  source_dest_check    = false
  private_ip           = cidrhost(aws_subnet.sdwan_1.cidr_block, 10)
  user_data            = <<EOF
  {
    "bucket" : "${aws_s3_bucket.bootstrap.bucket}",
    "region" : "${var.region}",
    "config" : "/${aws_s3_bucket_object.config_1.key}",
  }
  EOF

  depends_on = [aws_s3_bucket_object.config_1]
  tags = {
    Name = length(var.name) > 0 ? "${var.name}-headend1" : "avx-sdwan-edge-headend1",
  }
}

#SDWAN Headend 2 (HA)
resource "aws_instance" "headend_2" {
  count                       = var.ha_gw ? 1 : 0
  ami                         = data.aws_ami.fortios-on-demand.id
  instance_type               = var.instance_size
  subnet_id                   = aws_subnet.sdwan_2.id
  associate_public_ip_address = true
  security_groups             = [aws_security_group.sdwan.id]
  lifecycle {
    ignore_changes = [security_groups]
  }
  iam_instance_profile = var.iam_role_name
  source_dest_check    = false
  private_ip           = cidrhost(aws_subnet.sdwan_2.cidr_block, 10)
  user_data            = <<EOF
  {
    "bucket" : "${aws_s3_bucket.bootstrap.bucket}",
    "region" : "${var.region}",
    "config" : "/${aws_s3_bucket_object.config_2.key}",
  }
  EOF

  depends_on = [aws_s3_bucket_object.config_2]
  tags = {
    Name = length(var.name) > 0 ? "${var.name}-headend2" : "avx-sdwan-edge-headend2",
  }
}

resource "aws_eip" "headend_1" {
  vpc = true
}

resource "aws_eip" "headend_2" {
  count = var.ha_gw ? 1 : 0
  vpc   = true
}

resource "aws_eip_association" "eip_headend" {
  count         = var.ha_gw ? 0 : 1
  instance_id   = aws_instance.headend.id
  allocation_id = aws_eip.headend_1.id
}

resource "aws_eip_association" "eip_headend_1" {
  count         = var.ha_gw ? 1 : 0
  instance_id   = aws_instance.headend_1.id
  allocation_id = aws_eip.headend_1.id
}

resource "aws_eip_association" "eip_headend_2" {
  count         = var.ha_gw ? 1 : 0
  instance_id   = aws_instance.headend_2.id
  allocation_id = aws_eip.headend_2.id
}
