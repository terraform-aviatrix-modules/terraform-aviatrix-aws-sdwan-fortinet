variable "name" {
  description = "Custom name for VPC and sdwan headends"
  type        = string
  default     = ""
}

variable "region" {
  description = "The AWS region to deploy this module in"
  type        = string
}

variable "transit_gw" {
  description = "Transit gateway to attach spoke to"
  type        = string
}

variable "az1" {
  description = "Availability zone 1, for headend deployment"
  type        = string
  default     = "a"
}

variable "az2" {
  description = "Availability zone 2, for headend deployment"
  type        = string
  default     = "b"
}

variable "ha_gw" {
  description = "Boolean to determine if module will be deployed in HA or single mode"
  type        = bool
  default     = true
}

variable "fortios_version" {
  description = "Determines which FortiOS image version will be deployed."    
  type    = string
  default = "6.2.3" #Make sure the version is available in the Marketplace
}

variable "fortios_image_type" {
  description = "Determines whether byol or on-demand image should be used."    
  type    = string
  default = "on-demand"
}

variable "instance_size" {
  description = "AWS Instance size for the SDWAN gateways"
  type        = string
  default     = "t3.medium"
}

variable "fortigate_password" {
    description = "Password for FortiGate instances."
    type = string
    default = "Avtx#1234"
}

variable "tunnel_cidr" {
    description = "CIDR to be used to create tunnel addresses"
    type = string
    default = "172.31.255.0/28"
}

variable "aviatrix_asn" {
    description = "ASN To be used on Aviatrix Transit Gateway for BGP"
    type = string
    default = "65000"
}

variable "sdwan_asn" {
    description = "ASN To be used on SDWAN Gateway for BGP"
    type = string
    default = "65001"
}