output "vpc" {
  description = "The created VPC with all of it's attributes"
  value       = aws_vpc.sdwan
}

output "subnet1" {
  description = "The created subnet1 and all of it's attributes"
  value       = aws_subnet.sdwan_1
}

output "subnet2" {
  description = "The created subnet2 and all of it's attributes"
  value       = aws_subnet.sdwan_2
}
