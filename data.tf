data "aws_ami" "fortios-on-demand" {
  most_recent = true
  filter {
    name   = "name"
    values = ["FortiGate-VM64-AWSONDEMAND*${var.fortios_version}*"]
  }
  owners = ["679593333241"] # Marketplace
}

data "aws_ami" "fortios-byol" {
  most_recent = true
  filter {
    name   = "name"
    values = ["FortiGate-VM64-AWS *${var.fortios_version}*"]
  }
  owners = ["679593333241"] # Marketplace
}