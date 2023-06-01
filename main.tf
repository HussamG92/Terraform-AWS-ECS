provider "aws" {
  region  = "us-south-1"
  #  access_key = var.access_key
  #  secret_key = var.secret_key

}

data "aws_region" "current" {}

data "aws_availability_zones" "zones" {}

resource "aws_vpc" "demo-vpc" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = {
    Name        = join("-", [var.project, var.environment])
    Environment = var.environment
  }
}

resource "aws_subnet" "demo-subnets" {
  for_each          = toset(data.aws_availability_zones.zones.names)
  vpc_id            = aws_vpc.demo-vpc.id
  cidr_block        = "10.0.${index(data.aws_availability_zones.zones.names, each.value)}.0/24"
  availability_zone = each.value
  tags              = {
    Name        = join("-", [var.project, var.environment, each.key])
    Environment = var.environment
  }
}

locals {
  subnet_ids = [
  for o in aws_subnet.demo-subnets : o.id
  ]
}

resource "aws_internet_gateway" "demo-ig" {
  vpc_id = aws_vpc.demo-vpc.id
  tags   = {
    Name        = join("-", [var.project, "ig", var.environment])
    Environment = var.environment
  }
}

resource "aws_route_table" "route-table" {
  vpc_id = aws_vpc.demo-vpc.id
  tags   = {
    Name        = join("-", [var.project, "rt", var.environment])
    Environment = var.environment
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo-ig.id
  }
}

resource "aws_route_table_association" "route-table-association" {
  route_table_id = aws_route_table.route-table.id
  for_each       = aws_subnet.demo-subnets
  subnet_id      = each.value.id
  depends_on     = [aws_subnet.demo-subnets]
}

resource "aws_security_group" "demo-sg" {
  name        = join("-", [var.project, var.environment, "sg"])
  description = "Security Group for ECS ${var.project} ${var.environment}"
  vpc_id      = aws_vpc.demo-vpc.id
  ingress {
    from_port   = 443
    protocol    = "tcp"
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8000
    protocol    = "tcp"
    to_port     = 8000
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name        = join("-", [var.project, var.environment, "sg"])
    Environment = var.environment
  }
}
resource "aws_iam_role" "ecs_task_definition_role" {
  name               = join("-", [var.project, "ecsTaskExecutionRole"])
  assume_role_policy = file("./role_policy.json")
}

resource "aws_iam_policy" "ecs_permissions" {
  name        = join("-", [var.project, "ecsPermissions"])
  description = "Permissions to enable CT"
  policy      = file("./permission.json")
}


resource "aws_iam_role_policy_attachment" "ecs_attachment" {
  role       = aws_iam_role.ecs_task_definition_role.name
  policy_arn = aws_iam_policy.ecs_permissions.arn
}

resource "aws_ecs_cluster" "demo" {
  name = join("-", [var.project, var.environment])
}
resource "aws_ecs_cluster_capacity_providers" "demo-capacity-provider" {
  cluster_name       = aws_ecs_cluster.demo.name
  capacity_providers = ["FARGATE"]
}
resource "aws_ecs_task_definition" "demo-task-definition" {
  for_each                 = var.task_defs
  family                   = join("-", [var.project, each.key, var.environment])
  requires_compatibilities = ["FARGATE"]
  task_role_arn            = aws_iam_role.ecs_task_definition_role.arn
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  runtime_platform {
    operating_system_family = "LINUX"
  }
  execution_role_arn    = aws_iam_role.ecs_task_definition_role.arn
  container_definitions = jsonencode([
    {
      name         = join("-", [var.project, "container", each.key, var.environment])
      image        = each.value.image_url
      cpu          = each.value.cpu
      memory       = each.value.memory
      essential    = each.value.essential
      #      secrets   = [
      #        {
      #          Name      = "DB_PASSWORD",
      #          ValueFrom = aws_ssm_parameter.db_password.arn
      #        }
      #      ]
      environment  = each.value.environment
      portMappings = [
        {
          containerPort = each.value.containerPort
          hostPort      = each.value.hostPort
        }
      ],
      logConfiguration = {
        logDriver = "awslogs",
        options   = {
          awslogs-group         = "demo",
          awslogs-region        = data.aws_region.current.name,
          awslogs-create-group  = "true",
          awslogs-stream-prefix = join("-", ["container", var.project, each.key, var.environment])
        }
      }
    }
  ])
}

resource "aws_lb" "loadbalancer" {
  name                       = "demo-lb-${var.environment}"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.demo-sg.id]
  subnets                    = local.subnet_ids
  enable_deletion_protection = false
  tags                       = {
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "target_groups" {
  for_each    = var.task_defs
  name        = join("-", [var.project, each.key, var.environment])
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.demo-vpc.id
  target_type = "ip"
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.loadbalancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
    #    target_group_arn = aws_lb_target_group.target_groups["root"].arn
  }
}

# resource "aws_lb_listener" "listener_https" {
#   load_balancer_arn = aws_lb.loadbalancer.arn
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.target_groups["root"].arn
#   }
#   port            = "443"
#   protocol        = "HTTPS"
#   certificate_arn = var.certificate_arn
#   ssl_policy      = "ELBSecurityPolicy-2016-08"
# }

#resource "aws_lb_listener_rule" "listener_rule" {
#  for_each     = var.task_defs
#  listener_arn = aws_lb_listener.listener.arn
#  action {
#    type             = "forward"
#    target_group_arn = aws_lb_target_group.target_groups[each.key].arn
#  }
#  condition {
#    path_pattern {
#      values = each.value.route
#    }
#  }
#}

# resource "aws_lb_listener_rule" "listener_rule_https" {
#   for_each     = var.task_defs
#   listener_arn = aws_lb_listener.listener_https.arn
#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.target_groups[each.key].arn
#   }
#   condition {
#     path_pattern {
#       values = each.value.route
#     }
#   }
# }

resource "aws_ecs_service" "demo-service" {
  for_each        = var.task_defs
  name            = join("-", [var.project, "service", each.key, var.environment])
  cluster         = aws_ecs_cluster.demo.id
  task_definition = aws_ecs_task_definition.demo-task-definition[each.key].arn
  desired_count   = each.value.number_of_tasks
  launch_type     = "FARGATE"
  load_balancer {
    target_group_arn = aws_lb_target_group.target_groups[each.key].arn
    container_name   = join("-", [var.project, "container", each.key, var.environment])
    container_port   = each.value.containerPort
  }
  network_configuration {
    subnets          = local.subnet_ids
    assign_public_ip = true
    security_groups  = [aws_security_group.demo-sg.id]
  }
  depends_on = [aws_lb.loadbalancer]
}