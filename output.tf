output "aws_region" {
  value = data.aws_region.current
}
output "aws_availability_zones" {
  value = length(data.aws_availability_zones.zones.names)
}
#
#output "target_group_arns" {
#  value = toset(module.this_alb[0].target_group_arns)
#}

output "subnets" {
  value = local.subnet_ids
}
output "definition" {
  value = aws_ecs_task_definition.demo-task-definition
}