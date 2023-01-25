
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
      version="1.2.0"
    }
    sonarqube = {
      source = "jdamata/sonarqube"
      version="0.15.5"
    }
  }
}

provider "azapi" {
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "sonargroup" { 
  name     = "sonar-rg" 
  location = "${var.location}" 
} 

resource "azurerm_virtual_network" "network" {
  name                = "sq-network"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.sonargroup.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "sq-subnet"
  resource_group_name = azurerm_resource_group.sonargroup.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.0.0/23"]
}


resource "azurerm_log_analytics_workspace" "env" {
  name                = "loganalytics"
  location            = azurerm_resource_group.sonargroup.location
  resource_group_name = azurerm_resource_group.sonargroup.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azapi_resource" "sonar-env" {
  name      = "sonar-env"
  type      = "Microsoft.App/managedEnvironments@2022-03-01"
  location  = var.location
  parent_id = azurerm_resource_group.sonargroup.id
  body = jsonencode({
    properties = {
      vnetConfiguration = {
        internal               = false
        infrastructureSubnetId = azurerm_subnet.subnet.id
      }
      appLogsConfiguration = {
        destination = "log-analytics"
        logAnalyticsConfiguration = {
          customerId = azurerm_log_analytics_workspace.env.workspace_id
          sharedKey  = azurerm_log_analytics_workspace.env.primary_shared_key
        }
      }
    }
  })
}

resource "azapi_resource" "sonarqube" {
  name      = "sonarqube-container-app"
  location  = var.location
  parent_id = azurerm_resource_group.sonargroup.id
  type      = "Microsoft.App/containerApps@2022-06-01-preview"
  body = jsonencode({
    properties = {
      managedEnvironmentId = azapi_resource.sonar-env.id
      configuration = {
        ingress = {
          targetPort  = 9000
          exposedPort = 9000
          transport   = "tcp"
          external    = true
        }
      },
      template = {
        containers = [
          {
            "image" : "docker.io/sonarqube",
            "name" : "sonarqube",
            resources: {
              "cpu": 2,
              "memory": "4.0Gi"
            }


            # "env" : [
            #   {
            #     "name" : "POSTGRES_PASSWORD",
            #     "value" : "mysecretpassword"
            #   }
            # ]
          }
        ]
      }
      
    }
  })

  ignore_missing_property = true
  response_export_values  = ["properties.configuration.ingress"]

  provisioner "local-exec" {
    command = "sudo sysctl -w vm.max_map_count=262144"
  }
}

output "sq_endpoint" {
  value=azapi_resource.sonarqube.output
}

provider "sonarqube" {
    user   = var.sq_admin_login
    pass   = var.sq_admin_login_password
    host   = "http://sonarqube-container-app.mangoground-cc1ae440.westeurope.azurecontainerapps.io:9000"
}

resource "sonarqube_user_token" "token" {
  login_name = "admin"
  name       = "sq-token"
}

output "user_token" {
  value = sonarqube_user_token.token.token
  sensitive = true
}