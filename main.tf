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
  upper   = false
}

#Random string for secret pre-shared-key
resource "random_string" "psk" {
  length  = 100
  special = false #Long key, without special chars to prevent issues.
}

#AWS Bootstrap environment for FortiGate
resource "aws_s3_bucket" "bootstrap" {
  bucket = "sdwan-bootstrap-${random_string.bucket.result}"
  acl    = "private"
  lifecycle {
    ignore_changes = [
      bucket,
    ]
  }
}

#Create bootstrap configs based on template files
locals {

  tunnel_subnetmask    = cidrnetmask(cidrsubnet(var.tunnel_cidr, 2, 0))
  tunnel_masklength    = split("/", cidrsubnet(var.tunnel_cidr, 2, 0))[1]
  gw1_tunnel1_avx_ip   = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 0), 1)
  gw1_tunnel1_sdwan_ip = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 0), 2)
  gw1_tunnel2_avx_ip   = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 1), 1)
  gw1_tunnel2_sdwan_ip = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 1), 2)
  gw2_tunnel1_avx_ip   = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 2), 1)
  gw2_tunnel1_sdwan_ip = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 2), 2)
  gw2_tunnel2_avx_ip   = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 3), 1)
  gw2_tunnel2_sdwan_ip = cidrhost(cidrsubnet(var.tunnel_cidr, 2, 3), 2)

  template_single = templatefile("${path.module}/bootstrap/headend-single.tpl", {
    name           = length(var.name) > 0 ? var.name : var.region
    ASN            = var.sdwan_asn
    REMASN         = var.aviatrix_asn
    pre-shared-key = random_string.psk.result
    tunnel1_ip     = local.gw1_tunnel1_sdwan_ip
    tunnel1_rem    = local.gw1_tunnel1_avx_ip
    tunnel1_mask   = local.tunnel_subnetmask
    tunnel2_ip     = local.gw1_tunnel2_sdwan_ip
    tunnel2_rem    = local.gw1_tunnel2_avx_ip
    tunnel2_mask   = local.tunnel_subnetmask
    transit_gw     = var.transit_gw_obj.eip
    transit_gw_ha  = var.transit_gw_obj.ha_eip
    password       = var.fortigate_password
    }
  )
  template_1 = templatefile("${path.module}/bootstrap/headend-ha.tpl", {
    name           = length(var.name) > 0 ? var.name : var.region
    ASN            = var.sdwan_asn
    REMASN         = var.aviatrix_asn
    pre-shared-key = "${random_string.psk.result}-headend1"
    headend_nr     = 1
    tunnel1_ip     = local.gw1_tunnel1_sdwan_ip
    tunnel1_rem    = local.gw1_tunnel1_avx_ip
    tunnel1_mask   = local.tunnel_subnetmask
    tunnel2_ip     = local.gw1_tunnel2_sdwan_ip
    tunnel2_rem    = local.gw1_tunnel2_avx_ip
    tunnel2_mask   = local.tunnel_subnetmask
    peerip         = cidrhost(aws_subnet.sdwan_2.cidr_block, 10)
    transit_gw     = var.transit_gw_obj.eip
    transit_gw_ha  = var.transit_gw_obj.ha_eip
    password       = var.fortigate_password
    }
  )
  template_2 = templatefile("${path.module}/bootstrap/headend-ha.tpl", {
    name           = length(var.name) > 0 ? var.name : var.region
    ASN            = var.sdwan_asn
    REMASN         = var.aviatrix_asn
    pre-shared-key = "${random_string.psk.result}-headend2"
    headend_nr     = 2
    tunnel1_ip     = local.gw2_tunnel1_sdwan_ip
    tunnel1_rem    = local.gw2_tunnel1_avx_ip
    tunnel1_mask   = local.tunnel_subnetmask
    tunnel2_ip     = local.gw2_tunnel2_sdwan_ip
    tunnel2_rem    = local.gw2_tunnel2_avx_ip
    tunnel2_mask   = local.tunnel_subnetmask
    peerip         = cidrhost(aws_subnet.sdwan_1.cidr_block, 10)
    transit_gw     = var.transit_gw_obj.eip
    transit_gw_ha  = var.transit_gw_obj.ha_eip
    password       = var.fortigate_password
    }
  )
}

#Create the bootstrap files
resource "local_file" "template_single" {
  count    = var.ha_gw ? 0 : 1
  content  = local.template_single
  filename = "${path.module}/bootstrap/sdwan.conf"
}

resource "local_file" "template_1" {
  count    = var.ha_gw ? 1 : 0
  content  = local.template_1
  filename = "${path.module}/bootstrap/sdwan-1.conf"
}

resource "local_file" "template_2" {
  count    = var.ha_gw ? 1 : 0
  content  = local.template_2
  filename = "${path.module}/bootstrap/sdwan-2.conf"
}

#bootstrap config files for FortiGate SDWAN
resource "aws_s3_bucket_object" "config" {
  count  = var.ha_gw ? 0 : 1
  bucket = aws_s3_bucket.bootstrap.id
  key    = "sdwan_config.conf"
  source = local_file.template_single[0].filename
  lifecycle {
    ignore_changes = [source]
  }
}

resource "aws_s3_bucket_object" "config_1" {
  count  = var.ha_gw ? 1 : 0
  bucket = aws_s3_bucket.bootstrap.id
  key    = "sdwan-a_config.conf"
  source = local_file.template_1[0].filename
  lifecycle {
    ignore_changes = [source]
  }
}

resource "aws_s3_bucket_object" "config_2" {
  count  = var.ha_gw ? 1 : 0
  bucket = aws_s3_bucket.bootstrap.id
  key    = "sdwan-b_config.conf"
  source = local_file.template_2[0].filename
  lifecycle {
    ignore_changes = [source]
  }
}

#SDWAN Headend (non-HA)
resource "aws_instance" "headend" {
  count                       = var.ha_gw ? 0 : 1
  ami                         = length(regexall("on-demand", lower(var.fortios_image_type))) > 0 ? data.aws_ami.fortios_on_demand.id : data.aws_ami.fortios_byol.id
  instance_type               = var.instance_size
  subnet_id                   = aws_subnet.sdwan_1.id
  associate_public_ip_address = true
  security_groups             = [aws_security_group.sdwan.id]
  lifecycle {
    ignore_changes = [security_groups]
  }
  iam_instance_profile = length(var.iam_role_name) > 0 ? var.iam_role_name : aws_iam_role.bootstrap[0].name
  source_dest_check    = false
  private_ip           = cidrhost(aws_subnet.sdwan_1.cidr_block, 10)
  user_data            = <<EOF
  {
    "bucket" : "${aws_s3_bucket.bootstrap.bucket}",
    "region" : "${var.region}",
    "config" : "/${aws_s3_bucket_object.config[0].key}",
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
  ami                         = length(regexall("on-demand", lower(var.fortios_image_type))) > 0 ? data.aws_ami.fortios_on_demand.id : data.aws_ami.fortios_byol.id
  instance_type               = var.instance_size
  subnet_id                   = aws_subnet.sdwan_1.id
  associate_public_ip_address = true
  security_groups             = [aws_security_group.sdwan.id]
  lifecycle {
    ignore_changes = [security_groups]
  }
  iam_instance_profile = length(var.iam_role_name) > 0 ? var.iam_role_name : aws_iam_role.bootstrap[0].name
  source_dest_check    = false
  private_ip           = cidrhost(aws_subnet.sdwan_1.cidr_block, 10)
  user_data            = <<EOF
  {
    "bucket" : "${aws_s3_bucket.bootstrap.bucket}",
    "region" : "${var.region}",
    "config" : "/${aws_s3_bucket_object.config_1[0].key}",
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
  ami                         = length(regexall("on-demand", lower(var.fortios_image_type))) > 0 ? data.aws_ami.fortios_on_demand.id : data.aws_ami.fortios_byol.id
  instance_type               = var.instance_size
  subnet_id                   = aws_subnet.sdwan_2.id
  associate_public_ip_address = true
  security_groups             = [aws_security_group.sdwan.id]
  lifecycle {
    ignore_changes = [security_groups]
  }
  iam_instance_profile = length(var.iam_role_name) > 0 ? var.iam_role_name : aws_iam_role.bootstrap[0].name
  source_dest_check    = false
  private_ip           = cidrhost(aws_subnet.sdwan_2.cidr_block, 10)
  user_data            = <<EOF
  {
    "bucket" : "${aws_s3_bucket.bootstrap.bucket}",
    "region" : "${var.region}",
    "config" : "/${aws_s3_bucket_object.config_2[0].key}",
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
  instance_id   = aws_instance.headend[0].id
  allocation_id = aws_eip.headend_1.id
}

resource "aws_eip_association" "eip_headend_1" {
  count         = var.ha_gw ? 1 : 0
  instance_id   = aws_instance.headend_1[0].id
  allocation_id = aws_eip.headend_1.id
}

resource "aws_eip_association" "eip_headend_2" {
  count         = var.ha_gw ? 1 : 0
  instance_id   = aws_instance.headend_2[0].id
  allocation_id = aws_eip.headend_2[0].id
}

#Aviatrix VPN Tunnels
resource "aviatrix_transit_external_device_conn" "sdwan" {
  vpc_id                    = var.transit_gw_obj.vpc_id
  connection_name           = "SDWAN-${var.region}"
  gw_name                   = var.transit_gw_obj.gw_name
  connection_type           = "bgp"
  ha_enabled                = var.ha_gw
  bgp_local_as_num          = var.aviatrix_asn
  bgp_remote_as_num         = var.sdwan_asn
  backup_bgp_remote_as_num  = var.ha_gw ? var.sdwan_asn : null
  remote_gateway_ip         = aws_eip.headend_1.public_ip
  backup_remote_gateway_ip  = var.ha_gw ? aws_eip.headend_2[0].public_ip : null
  pre_shared_key            = var.ha_gw ? "${random_string.psk.result}-headend1" : random_string.psk.result
  backup_pre_shared_key     = var.ha_gw ? "${random_string.psk.result}-headend2" : null
  local_tunnel_cidr         = var.ha_gw ? "${local.gw1_tunnel1_avx_ip}/${local.tunnel_masklength},${local.gw1_tunnel2_avx_ip}/${local.tunnel_masklength}" : "${local.gw1_tunnel1_avx_ip}/${local.tunnel_masklength}"
  remote_tunnel_cidr        = var.ha_gw ? "${local.gw1_tunnel1_sdwan_ip}/${local.tunnel_masklength},${local.gw1_tunnel2_sdwan_ip}/${local.tunnel_masklength}" : "${local.gw1_tunnel1_sdwan_ip}/${local.tunnel_masklength}"
  backup_local_tunnel_cidr  = var.ha_gw ? "${local.gw2_tunnel1_avx_ip}/${local.tunnel_masklength},${local.gw2_tunnel2_avx_ip}/${local.tunnel_masklength}" : null
  backup_remote_tunnel_cidr = var.ha_gw ? "${local.gw2_tunnel1_sdwan_ip}/${local.tunnel_masklength},${local.gw2_tunnel2_sdwan_ip}/${local.tunnel_masklength}" : null
}

#Create IAM role and policy for the SDWAN instance to access the bucket.
resource "aws_iam_role" "bootstrap" {
  count              = length(var.iam_role_name) > 0 ? 0 : 1
  name               = "bootstrap-${random_string.bucket.result}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_iam_policy" "bootstrap" {
  count  = length(var.iam_role_name) > 0 ? 0 : 1
  name   = "bootstrap-${random_string.bucket.result}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:Get*",
                "s3:List*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_iam_role_policy_attachment" "policy_role" {
  count      = length(var.iam_role_name) > 0 ? 0 : 1
  role       = aws_iam_role.bootstrap[0].name
  policy_arn = aws_iam_policy.bootstrap[0].arn
}

resource "aws_iam_instance_profile" "instance_role" {
  count = length(var.iam_role_name) > 0 ? 0 : 1
  name  = "bootstrap-${random_string.bucket.result}"
  role  = aws_iam_role.bootstrap[0].name
}
