variable "project" {
  default = "demo"
}

variable "environment" {
  description = "Type of Environment which will be added as a tag and will be added in names across"
}


variable "number_of_tasks" {
  default = 1
}

# variable "certificate_arn" {
#   default = ""
# }


variable "task_defs" {
  default = {
    "root" : {
      "cpu" : 2
      "memory" : 256
      "image_url" : "nginx:latest",
      "containerPort" : 8000
      "hostPort" : 8000,
      "essential" : true,
      "number_of_tasks" : 1,
      "environment" : [
        {
          Name  = "PORT"
          Value = "80"
        }
      ],
      route : ["/"]
    },
    "n" : {
      "cpu" : 2
      "memory" : 256
      "image_url" : "nginx:latest",
      "containerPort" : 8000
      "hostPort" : 8000,
      "essential" : true,
      "number_of_tasks" : 1,
      "environment" : [
        {
          Name  = "PORT"
          Value = "80"
        }
      ],
      route : ["/n"]
    },
    "ng" : {
      "cpu" : 2
      "memory" : 256
      "image_url" : "nginx:latest",
      "containerPort" : 8000
      "hostPort" : 8000,
      "essential" : true,
      "number_of_tasks" : 1,
      "environment" : [
        {
          Name  = "PORT"
          Value = "80"
        }
      ],
      route : ["/ng"]
    }
  }
}