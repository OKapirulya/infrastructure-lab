terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = "ssh://hools-terraform"
}

resource "docker_image" "ubuntu" {
  name = "ubuntu:24.04"
}

resource "docker_container" "ansible_target" {
  name    = "ansible-hardening-lab"
  image   = docker_image.ubuntu.image_id
  command = ["sleep", "infinity"]
}
