terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./authorized_key.json"
  folder_id                = var.folder_id
  zone                     = "ru-central1-a"
}

/* Конфигурация ресурсов */

resource "yandex_vpc_network" "foo" {
  // Requires 'vpc.privateAdmin' role https://cloud.yandex.ru/docs/vpc/security
}

resource "yandex_vpc_subnet" "foo" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.foo.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

# FIXME: unused container registry
resource "yandex_container_registry" "registry1" {
  name = "registry1"
}

variable "folder_id" {
  type = string
}
variable "registry_id" {
  type = string
}
variable "container_port" {
  type = string
}

locals {
  service-accounts = toset([
    "catgpt-sa", "catgpt-ig-sa"
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
  catgpt-ig-sa-roles = toset([
    "compute.editor",
    "iam.serviceAccounts.user",
    "load-balancer.admin", // create load balancer
    "vpc.publicAdmin",  // Permission denied to resource-manager.folder
    "vpc.user", // "Permission to use subnet denied"
    # "vpc.privateAdmin",
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  // Requires 'iam.serviceAccounts.admin' role https://cloud.yandex.ru/docs/iam/security
  for_each = local.service-accounts
  name     = "${var.folder_id}-${each.key}"
  // folder_id = defaults to provider folder_id
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  // Requires 'resource-manager.admin' role https://cloud.yandex.ru/docs/resource-manager/security
  for_each  = local.catgpt-sa-roles
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa"].id}"
  role      = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-ig-roles" {
  for_each  = local.catgpt-ig-sa-roles
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-ig-sa"].id}"
  role      = each.key
}

/*------------------------------DATABASE-------------------------------------*/
// https://cloud.yandex.com/en/docs/compute/concepts/image
data "yandex_compute_image" "debian" {
  // List of images `yc compute image list --folder-id standard-images`
  family = "debian-10"
}

resource "yandex_compute_instance" "db-inst-1" {
    hostname = "postgres"
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores         = 2
      memory        = 1 # Gb
      // Гарантированная доля CPU: доля может временно повышаться, но не будет меньше
      core_fraction = 5 # %
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      subnet_id = "${yandex_vpc_subnet.foo.id}"
      nat = true
    }
    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.debian.id
      }
    }
    metadata = {
      # docker-compose = file("${path.module}/docker-compose.yaml")
      // Для доступа к ВМ через SSH сгенерируйте пару SSH-ключей и передайте
      // публичную часть ключа на ВМ в параметре ssh-keys блока metadata.
      // https://cloud.yandex.ru/docs/compute/operations/vm-connect/ssh#creating-ssh-keys
      // Пользователь ВМ Container Optimized Image - ubuntu. Можно указать любого другого?
      ssh-keys  = "ubuntu:${file("./ssh_key.pub")}"
    }
}

resource "yandex_compute_instance" "db-inst-2" {
    # hostname = "postgres-repl"
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores         = 2
      memory        = 1 # Gb
      // Гарантированная доля CPU: доля может временно повышаться, но не будет меньше
      core_fraction = 5 # %
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      subnet_id = "${yandex_vpc_subnet.foo.id}"
      nat = true
    }
    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.debian.id
      }
    }
    metadata = {
      # docker-compose = file("${path.module}/docker-compose.yaml")
      // Для доступа к ВМ через SSH сгенерируйте пару SSH-ключей и передайте
      // публичную часть ключа на ВМ в параметре ssh-keys блока metadata.
      // https://cloud.yandex.ru/docs/compute/operations/vm-connect/ssh#creating-ssh-keys
      // Пользователь ВМ Container Optimized Image - ubuntu. Можно указать любого другого?
      ssh-keys  = "ubuntu:${file("./ssh_key.pub")}"
    }
}
/*---------------------------------------------------------------------------*/

// https://cloud.yandex.com/en/docs/cos/tutorials/coi-with-terraform
data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

resource "yandex_compute_instance" "bingo-db-init" {
    # Start with `terraform plan -target yandex_compute_instance.bingo-db-init`
    # !! Switch to 0 after db init https://stackoverflow.com/a/53196343
    count              = 0
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores         = 2
      memory        = 1 # Gb
      // Гарантированная доля CPU: доля может временно повышаться, но не будет меньше
      core_fraction = 5 # %
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      subnet_id = "${yandex_vpc_subnet.foo.id}"
      nat = true
    }
    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = templatefile("${path.module}/docker-compose-db-init.yaml", {
        registry_id = var.registry_id # yandex_container_registry.registry1.id,
        # folder_id = var.folder_id
      })
      // Для доступа к ВМ через SSH сгенерируйте пару SSH-ключей и передайте
      // публичную часть ключа на ВМ в параметре ssh-keys блока metadata.
      // https://cloud.yandex.ru/docs/compute/operations/vm-connect/ssh#creating-ssh-keys
      // Пользователь ВМ Container Optimized Image - ubuntu. Можно указать любого другого?
      ssh-keys  = "ubuntu:${file("./ssh_key.pub")}"
    }
}

// https://cloud.yandex.com/en/docs/cos/tutorials/coi-with-terraform#creating-group
resource "yandex_compute_instance_group" "bingo" {
  depends_on = [ yandex_resourcemanager_folder_iam_member.catgpt-ig-roles ]
  folder_id = var.folder_id
  // ID of the service account authorized for this instance = catgpt-sa
  service_account_id = yandex_iam_service_account.service-accounts["catgpt-ig-sa"].id
  scale_policy {
    fixed_scale {
      size = 2 // The number of instances in the instance group
    }
  }
  deploy_policy {
    // max num. of inst. that can be taken offline at the same time during the update
    max_unavailable = 1
    # max_creating = 2
    // --//-- that can be temporarily allocated above the group size during the update
    max_expansion = 1
    # max_deleting = 2
  }
  allocation_policy {
    zones = ["ru-central1-a"]
  }
  load_balancer {
    # target_group_name        = "target-group" // The name of the target group
    # target_group_description = "load balancer target group" // A description
  }
  // https://terraform-provider.yandexcloud.net/Resources/compute_instance
  instance_template {
    // Requires 'compute.editor' role https://cloud.yandex.ru/docs/compute/security
    // Requires 'iam.serviceAccounts.admin' role
    // https://cloud.yandex.com/en/docs/compute/concepts/vm-platforms
    platform_id        = "standard-v2"  // Intel Cascade Lake
    // ID of the service account authorized for this instance = catgpt-sa
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores         = 2
      memory        = 1 # Gb
      // Гарантированная доля CPU: доля может временно повышаться, но не будет меньше
      core_fraction = 5 # %
    }
    scheduling_policy {
      // Прерываемая ВМ работает не более 24 часов и может быть автоматически
      // остановлена. Все данные сохраняются, возможен перезапуск вручную.
      preemptible = true
    }
    network_interface {
      // 'subnet_id' in a single yandex_compute_instance
      subnet_ids = ["${yandex_vpc_subnet.foo.id}"]
      nat = true
    }
    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    // https://cloud.yandex.ru/docs/compute/concepts/vm-metadata
    metadata = {
      # user-data = "${file("cloud-config.yaml")}"
      docker-compose = templatefile("${path.module}/docker-compose.yaml", {
        registry_id = var.registry_id # yandex_container_registry.registry1.id,
        folder_id = var.folder_id
      })
      // Для доступа к ВМ через SSH сгенерируйте пару SSH-ключей и передайте
      // публичную часть ключа на ВМ в параметре ssh-keys блока metadata.
      // https://cloud.yandex.ru/docs/compute/operations/vm-connect/ssh#creating-ssh-keys
      // Пользователь ВМ Container Optimized Image - ubuntu. Можно указать любого другого?
      ssh-keys  = "ubuntu:${file("./ssh_key.pub")}"
    }
  }
}

// https://cloud.yandex.com/en/docs/compute/operations/instance-groups/create-with-balancer
// https://cloud.yandex.ru/docs/network-load-balancer/operations/load-balancer-create
resource "yandex_lb_network_load_balancer" "lb-1" {
  // Requires 'load-balancer.admin' role https://cloud.yandex.ru/docs/network-load-balancer/security
  name = "network-load-balancer-1"

  listener {
    name = "network-load-balancer-1-listener"
    port = 80
    target_port = var.container_port // Port of a target. The default is the same as listener's port.
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.bingo.load_balancer.0.target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = var.container_port
        path = "/ping"
      }
    }
  }
}
