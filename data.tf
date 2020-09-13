data "aws_ami" "fortios_on_demand" {
  most_recent = true
  filter {
    name   = "name"
    values = ["FortiGate-VM64-AWSONDEMAND*${var.fortios_version}*"]
  }
  owners = ["679593333241"] # Marketplace
}

data "aws_ami" "fortios_byol" {
  most_recent = true
  filter {
    name   = "name"
    values = ["FortiGate-VM64-AWS *${var.fortios_version}*"]
  }
  owners = ["679593333241"] # Marketplace
}