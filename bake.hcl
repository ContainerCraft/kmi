# https://docs.docker.com/engine/reference/commandline/buildx_bake
# docker buildx create --driver docker-container --name builder --use
# FLAG=$(git rev-parse --short HEAD) docker buildx bake -f bake.hcl --builder builder --progress tty --load

variable "FLAG" {
  default = "dev"
}

variable "REPO" {
  default = ""
}

target "defaults" {
  dockerfile = "Containerfile"
  platforms = ["linux/arm64", "linux/amd64"]
  labels = {
    license = "GPLv3"
    distribution-scope = "public"
    description = "Kubevirt Machine Image | ContainerCraft.io Reference Image",
    "io.k8s.description" = "ContainerCraft.io Maintained Public Reference KMI"
    "org.opencontainers.image.description" = "Kubevirt Machine Image"
    "org.opencontainers.image.source" = "https://github.com/ContainerCraft/kmi/"
    "org.opencontainers.image.authors" = "ContainerCraft.io"
  }
}

function "tag" {
  params = [image, tag]
  result = equal("", REPO) ? "docker.io/containercraft/${image}:${tag}-${FLAG}" : "${REPO}/${image}:${tag}-${FLAG}"
}

target "ubuntu-22-04" {
  inherits = ["defaults"]
  tags = [
    tag("ubuntu", "22.04"),
    # tag("ubuntu", "jammy"),
  ]
  args = {
    FLAVOR = "ubuntu-22.04"
  }
}

target "fedora-37" {
  inherits = ["defaults"]
  tags = [
    tag("fedora", "37")
  ]
  args = {
    FLAVOR = "fedora-37"
  }
}

target "archlinux-latest" {
  inherits = ["defaults"]
  tags = [
    tag("archlinux", "latest")
  ]
  args = {
    FLAVOR = "archlinux-latest"
  }
}

target "debian-10" {
  inherits = ["defaults"]
  tags = [
    tag("debian", "10")
  ]
  args = {
    FLAVOR = "debian-10"
  }
}

target "debian-11" {
  inherits = ["defaults"]
  tags = [
    tag("debian", "11")
  ]
  args = {
    FLAVOR = "debian-11"
  }
}

target "debian-13" {
  inherits = ["defaults"]
  tags = [
    tag("debian", "13"),
    tag("debian", "trixie"),
  ]
  args = {
    FLAVOR = "debian-13"
  }
}

target "opensuse-leap-15" {
  inherits = ["defaults"]
  platforms = ["linux/amd64"]
  tags = [
    tag("opensuse", "leap-15")
  ]
  args = {
    FLAVOR = "opensuse-leap-15"
  }
}

target "opensuse-tumbleweed" {
  inherits = ["defaults"]
  platforms = ["linux/amd64"]
  tags = [
    tag("opensuse", "tumbleweed")
  ]
  args = {
    FLAVOR = "opensuse-tumbleweed"
  }
}

target "centos-8" {
  inherits = ["defaults"]
  tags = [
    tag("centos", "8")
  ]
  args = {
    FLAVOR = "centos-8"
  }
}

target "centos-9" {
  inherits = ["defaults"]
  tags = [
    tag("centos", "9")
  ]
  args = {
    FLAVOR = "centos-9"
  }
}

target "fcos-35" {
  inherits = ["defaults"]
  tags = [
    tag("fcos", "35")
  ]
  args = {
    FLAVOR = "fcos-35"
  }
}

target "freebsd-13" {
  inherits = ["defaults"]
  platforms = ["linux/amd64"]
  tags = [
    tag("freebsd", "13")
  ]
  args = {
    FLAVOR = "freebsd-13"
  }
}

target "almalinux-8" {
  inherits = ["defaults"]
  tags = [
    tag("almalinux", "8")
  ]
  args = {
    FLAVOR = "almalinux-8"
  }
}

target "rocky-8" {
  inherits = ["defaults"]
  tags = [
    tag("rocky", "8")
  ]
  args = {
    FLAVOR = "rocky-8"
  }
}

target "openwrt-21" {
  inherits = ["defaults"]
  platforms = ["linux/amd64"]
  tags = [
    tag("openwrt", "21"),
    tag("openwrt", "latest"),
  ]
  args = {
    FLAVOR = "openwrt-21"
  }
}
