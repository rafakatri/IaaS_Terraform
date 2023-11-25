
resource "aws_launch_configuration" "launch" {
    name = "apps"
    image_id = "ami-0914c6b22d85d1b96"
    instance_type = "t2.micro"
    user_data = file("./ec2/config.sh")
    security_groups = var.app_security_group
        
    lifecycle {
        create_before_destroy = true
    }
}

resource aws_autoscaling_group "apps" {
    launch_configuration = aws_launch_configuration.launch.id
    min_size = 1
    max_size = 3
    desired_capacity = 2
    vpc_zone_identifier = var.subnet_lb_ids
}


resource "aws_lb" "loadBalancer" {
  name               = "lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.lb_security_group
  subnets            = var.subnet_lb_ids
}

resource "aws_lb_target_group" "target" {
    name      = "target"
    port      = 80
    protocol  = "HTTP"
    vpc_id    = var.vpc_id
    health_check {
      enabled            = true
      port               = 81
      interval           = 30
      protocol           = "HTTP"
      path               = "/health"
      matcher            = "200"
      healthy_threshold  = 3
      unhealthy_threshold = 3
    }
}

resource "aws_lb_listener" "listener" {
    load_balancer_arn = aws_lb.loadBalancer.arn
    port             = "80"
    protocol         = "HTTP"
    default_action {
      type            = "forward"
      target_group_arn = aws_lb_target_group.target.arn
    }
}

resource "aws_autoscaling_attachment" "asg_attach" {
 autoscaling_group_name = aws_autoscaling_group.apps.name
 lb_target_group_arn  = aws_lb_target_group.target.arn
}