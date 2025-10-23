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

target "ubuntu-24-04" {
  inherits = ["defaults"]
  tags = [
    tag("ubuntu", "24.04"),
  ]
  args = {
    FLAVOR = "ubuntu-24-04"
  }
}

target "fedora-42" {
  inherits = ["defaults"]
  tags = [
    tag("fedora", "42")
  ]
  args = {
    FLAVOR = "fedora-42"
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

target "opensuse-leap-16" {
  inherits = ["defaults"]
  tags = [
    tag("opensuse", "leap-16")
  ]
  args = {
    FLAVOR = "opensuse-leap-16"
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

target "centos-10" {
  inherits = ["defaults"]
  tags = [
    tag("centos", "10")
  ]
  args = {
    FLAVOR = "centos-10"
  }
}

target "fcos-42" {
  inherits = ["defaults"]
  tags = [
    tag("fcos", "42")
  ]
  args = {
    FLAVOR = "fcos-42"
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

target "almalinux-10" {
  inherits = ["defaults"]
  tags = [
    tag("almalinux", "10")
  ]
  args = {
    FLAVOR = "almalinux-10"
  }
}

target "rocky-10" {
  inherits = ["defaults"]
  tags = [
    tag("rocky", "10")
  ]
  args = {
    FLAVOR = "rocky-10"
  }
}

target "openwrt-24" {
  inherits = ["defaults"]
  platforms = ["linux/arm64", "linux/amd64"]
  tags = [
    tag("openwrt", "24"),
    tag("openwrt", "latest"),
  ]
  args = {
    FLAVOR = "openwrt-24"
  }
}
