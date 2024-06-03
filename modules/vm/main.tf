provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "random_password" "vm_password" {
  length  = 16
  special = true
}

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "azurerm_virtual_network" "vnet" {
  count               = var.create_vnet ? 1 : 0
  name                = "${var.name_prefix}-vnet"
  address_space       = [var.vnet_address_space]
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  count                = var.create_vnet ? var.subnet_count : 0
  name                 = element(var.subnet_names, count.index)
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = [element(var.subnet_address_spaces, count.index)]
}

resource "azurerm_public_ip" "public_ip" {
  count               = var.create_public_ip ? var.zone_count : 0
  name                = "${var.name_prefix}-publicip-0${count.index + 1}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "nic" {
  count               = var.create_nic ? var.zone_count : 0
  name                = "${var.name_prefix}-nic-0${count.index + 1}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.${count.index + 4}"
    public_ip_address_id          = var.create_public_ip ? azurerm_public_ip.public_ip[count.index].id : null
  }
}

resource "azurerm_virtual_machine" "vm" {
  count                 = var.zone_count
  name                  = "${var.name_prefix}-vm-0${count.index + 1}"
  location              = data.azurerm_resource_group.rg.location
  resource_group_name   = data.azurerm_resource_group.rg.name
  network_interface_ids = var.create_nic ? [azurerm_network_interface.nic[count.index].id] : []

  vm_size = var.vm_size

  storage_os_disk {
    name              = "${var.name_prefix}-osdisk-0${count.index + 1}"
    caching           = var.os_disk_caching
    create_option     = "FromImage"
    managed_disk_type = var.os_disk_type
    disk_size_gb      = var.os_disk_size_gb
  }

  storage_image_reference {
    publisher = var.vm_image_publisher
    offer     = var.vm_image_offer
    sku       = var.vm_image_sku
    version   = var.vm_image_version
  }

  os_profile {
    computer_name  = "${var.name_prefix}-hostname-0${count.index + 1}"
    admin_username = var.admin_username
    admin_password = random_password.vm_password.result
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  boot_diagnostics {
    enabled     = var.enable_boot_diagnostics
    storage_uri = var.boot_diagnostics_storage_uri
  }

  dynamic "storage_data_disk" {
    for_each = range(var.data_disk_count)
    content {
      name              = "${var.name_prefix}-datadisk-0${count.index + 1}-${storage_data_disk.value}"
      lun               = storage_data_disk.value
      caching           = var.data_disk_caching
      create_option     = "Empty"
      disk_size_gb      = var.data_disk_size_gb
      managed_disk_type = var.data_disk_type
    }
  }

  zones = var.zone_redundant ? [count.index + 1] : null
}
