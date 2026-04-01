package main

deny[msg] {
  input.kind == "Deployment"
  some i
  container := input.spec.template.spec.containers[i]
  not container.securityContext.runAsNonRoot
  msg := "Container must not run as root"
}

deny[msg] {
  input.kind == "Deployment"
  some i
  container := input.spec.template.spec.containers[i]
  not container.resources.limits
  msg := "Container must define resource limits"
}