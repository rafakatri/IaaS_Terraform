
resource "aws_launch_configuration" "launch" {
  name = "apps-katri"
  image_id = "ami-04cedafa3de954d3b"
  instance_type = "t2.micro"
  user_data = templatefile("./ec2/config.sh", { rds_endpoint = var.rds_endpoint})
  security_groups = var.app_security_group

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
        
  lifecycle {
    create_before_destroy = true
  }
}

resource aws_autoscaling_group "apps" {
  launch_configuration = aws_launch_configuration.launch.id
  min_size = 1
  max_size = 5
  desired_capacity = 2
  vpc_zone_identifier = var.subnet_lb_ids

  enabled_metrics = [
   "GroupTotalInstances",
   "GroupInServiceInstances",
   "GroupPendingInstances",
   "GroupStandbyInstances",
   "GroupTerminatingInstances",
   "GroupDesiredCapacity",
   "GroupMaxSize",
   "GroupMinSize",
   "GroupInServiceCapacity",
   "GroupPendingCapacity",
   "GroupStandbyCapacity",
   "GroupTerminatingCapacity",
   "GroupTotalCapacity"
 ]
}


resource "aws_iam_role" "ec2_role" {
  name = "ec2_role-katri"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ec2_policy" {
  name        = "ec2-cloudwatch-policy-katri"
  description = "A policy that allows EC2 instances to log to CloudWatch, access RDS information, and retrieve secrets."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "rds:Describe*",
           "cloudwatch:PutMetricData",
           "cloudwatch:GetMetricData",
           "cloudwatch:ListMetrics"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Effect   = "Allow",
        Resource = "*" // You may want to restrict this to specific secret ARNs
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile-katri"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

resource "aws_autoscaling_policy" "asg_policy_up" {
  name                 = "asg_policy_up-katri"
  autoscaling_group_name = aws_autoscaling_group.apps.name
  adjustment_type       = "ChangeInCapacity"
  scaling_adjustment    = 1
  cooldown              = 300
}

resource "aws_autoscaling_policy" "asg_policy_down" {
  name                 = "asg_policy_down-katri"
  autoscaling_group_name = aws_autoscaling_group.apps.name
  adjustment_type       = "ChangeInCapacity"
  scaling_adjustment    = -1
  cooldown              = 300
}


resource "aws_cloudwatch_metric_alarm" "highCPU" {
  alarm_name         = "highCPU-katri"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = "120"
  statistic          = "Average"
  threshold          = "10"
  alarm_description  = "This metric checks cpu utilization"
  alarm_actions      = [aws_autoscaling_policy.asg_policy_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.apps.name
  }
}

resource "aws_cloudwatch_metric_alarm" "lowCPU" {
  alarm_name         = "lowCPU-katri"
  comparison_operator = "LessThanThreshold"
  evaluation_periods = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/EC2"
  period             = "120"
  statistic          = "Average"
  threshold          = "5"
  alarm_description  = "This metric checks cpu utilization"
  alarm_actions      = [aws_autoscaling_policy.asg_policy_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.apps.name
  }
}


resource "aws_lb" "loadBalancer" {
  name               = "lb-katri"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.lb_security_group
  subnets            = var.subnet_lb_ids
}

resource "aws_lb_target_group" "target" {
  name      = "target-katri"
  port      = 80
  protocol  = "HTTP"
  vpc_id    = var.vpc_id
  health_check {
    enabled            = true
    port               = 80
    interval           = 30
    protocol           = "HTTP"
    path               = "/docs"
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