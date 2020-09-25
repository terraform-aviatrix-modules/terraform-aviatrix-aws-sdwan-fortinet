# terraform-aviatrix-aws-sdwan-fortinet

### Description
Deploys edge VPC with Fortinet SDWAN headends and creates tunnels to transit gateway.

### Diagram
\<Provide a diagram of the high level constructs thet will be created by this module>
<img src="<IMG URL>"  height="250">

### Compatibility
Module version | Terraform version | Controller version | Terraform provider version
:--- | :--- | :--- | :---
v1.0.0 | | |

### Usage Example
```
module "sdwan_edge" {
  source  = "terraform-aviatrix-modules/aws-sdwan-fortinet/aviatrix"
  version = "1.0.0"

  cidr = "10.1.0.0/20"
  region = "eu-west-1"
  transit_gw_obj = "transit_1"
}
```

### Variables
The following variables are required:

key | value
:--- | :---
cidr | x
region | x
transit_gw_obj | The name of the transit gateway we want to attach this SDWAN edge to.

The following variables are optional:

key | default | value 
:---|:---|:---
name | avx-\<region\>-sdwan-edge | When name is provided, avx-\<name\>-edge will be used.
az1 | "a" | Availability zone 1, for headend deployment.
az2 | "b" | Availability zone 2, for headend deployment.
ha_gw | true | Set to false te deploy a single sdwan headend. Make sure this matches the transit GW. They have to be both HA or both Single. Mix is not supported.
instance_size | t2.small | Instance size of the SDWAN GW's
fortios_version | 6.2.3 | Provide version number to deploy FortiGates with.
fortios_image_type | on-demand | Set to byol if you want to use your own license.
fortigate_password | Avtx#1234 | Password for FortiGate instances.
tunnel_cidr | 172.31.255.0/28 | CIDR for creation of tunnel IP's. At least /28 is required, even in non-HA. This is because the module will always carve out 4x /30.
aviatrix_asn | 65000 | ASN To be used on Aviatrix Transit Gateway for BGP
sdwan_asn | 65001 | ASN To be used on SDWAN Gateway for BGP
iam_role_name | | If no name is provided, a new IAM role will be created with policy to access S3 buckets. This is used to bootstrap the SDWAN gateway.

### Outputs
This module will return the following outputs:

key | description
:---|:---
\<keyname> | \<description of object that will be returned in this output>
