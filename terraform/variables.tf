variable "ssh_host" {
  description = "SSH alias or hostname of the Docker host"
  type        = string
  default     = "hools-terraform"
}

variable "container_image" {
  description = "Docker image used as a disposable test target for developing Ansible playbooks before they run against production"
  type        = string
  default     = "ubuntu:24.04"
}

variable "container_name" {
  description = "Name of the container on the Docker host"
  type        = string
  default     = "ansible-hardening-lab"
}
