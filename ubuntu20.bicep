// az group create -l southeastasia -n GLB
// az deployment group create -g GLB --template-file gatewaylb.bicep

/* 
// Drop forwarded port 22 traffic
iptables -A FORWARD -p tcp --dport 22 -j DROP
iptables -A FORWARD -i br0 -p tcp -d {consumer vm public ip} --dport 22 -j DROP
*/

/* 
// Enable iptables forward logging
iptables -A FORWARD -j LOG --log-prefix "IPTables: " --log-level 4
*/

/* 
// Clear all iptables rules
iptables -F
*/

@description('Admin username of os profile')
param adminUsername string = 'azadmin'

@description('Admin password of os profile')
param adminPassword string = 'AzureP@ssw0rd'

@description('Admin user ssh key data')
param keyData string = loadTextContent('key-data')

@description('Size of the VM')
param vmSize string = 'Standard_A1_v2'

@description('Location to deploy all the resources in')
param location string = 'southeastasia'

@description('Outbound only mode?')
param outboundOnly bool = false

var providerVmName = 'ProviderVm'
var providerNsgName = 'ProviderNsg'
var providerNsgSourceAddressPrefix = '167.220.0.0/16'
var providerVmNicName = 'ProviderNic'
var providerVmPrivateIPAddress = '10.110.1.4'
var providerVmPipNicName = 'ProviderPipNic'
var providerVmPipName = 'ProviderPip'
var providerVnetName = 'ProviderVnet'
var providerVnetAddressPrefix = '10.110.0.0/16'
var providerUntrustedSubnetName = 'ProviderUntrustedSubnet'
var providerUntrustedSubnetAddressPrefix = '10.110.0.0/24'
var providerTrustedSubnetName = 'ProviderTrustedSubnet'
var providerTrustedSubnetAddressPrefix = '10.110.1.0/24'
var providerLbName = 'ProviderLb'
var providerLbPrivateIPAddress = '10.110.1.128'

var consumerVmName = 'ConsumerVm'
var consumerNsgName = 'ConsumerNsg'
var consumerNsgSourceAddressPrefix = '167.220.0.0/16'
var consumerVmNicName = 'ConsumerNic'
var consumerVmPipName = 'ConsumerPip'
var consumerVnetName = 'ConsumerVnet'
var consumerVnetAddressPrefix = '10.120.0.0/16'
var consumerSubnetName = 'ConsumerSubnet'
var consumerSubnetAddressPrefix = '10.120.0.0/24'

resource provider_nsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: providerNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-Https'
        properties: {
          description: 'Allow-Https'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: providerNsgSourceAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SSH'
        properties: {
          description: 'Allow-SSH'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: providerNsgSourceAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 210
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource provider_vnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: providerVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        providerVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: providerUntrustedSubnetName
        properties: {
          addressPrefix: providerUntrustedSubnetAddressPrefix
          networkSecurityGroup: {
            id: provider_nsg.id
          }
        }
      }
      {
        name: providerTrustedSubnetName
        properties: {
          addressPrefix: providerTrustedSubnetAddressPrefix
        }
      }      
    ]
  }
}

resource provider_lb 'Microsoft.Network/loadBalancers@2021-03-01' = {
  name: providerLbName
  location: location
  sku: {
    name: 'Gateway'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'FeIpCfg'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: providerLbPrivateIPAddress
          subnet: {
            id: provider_vnet.properties.subnets[1].id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'BEPool'
        properties: {
          tunnelInterfaces: [
            {
              port: 10800
              identifier: 800
              protocol: 'VXLAN'
              type: 'Internal'
            }
            {
              port: 10801
              identifier: 801
              protocol: 'VXLAN'
              type: 'External'
            }
          ]
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'LbRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', providerLbName, 'FeIpCfg')
          }
          backendPort: 0
          frontendPort: 0
          protocol: 'All'
          backendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', providerLbName, 'BePool')
            }
          ]
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', providerLbName, 'LbProbe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'LbProbe'
        properties: {
          protocol: 'Tcp'
          port: 22
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
  }
}

resource provider_nic 'Microsoft.Network/networkInterfaces@2021-03-01' = {
  name: providerVmNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: providerVmPrivateIPAddress
          subnet: {
            id: provider_vnet.properties.subnets[1].id
          }
          loadBalancerBackendAddressPools: [
            {
              id: '${provider_lb.id}/backendAddressPools/BePool'
            }
          ]
        }
      }
    ]
  }
}

resource provider_pip 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: providerVmPipName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource provider_pip_nic 'Microsoft.Network/networkInterfaces@2021-03-01' = {
  name: providerVmPipNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfigPip'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: provider_pip.id
          }
          subnet: {
            id: provider_vnet.properties.subnets[0].id
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    enableAcceleratedNetworking: false
    enableIPForwarding: false
    networkSecurityGroup: {
      id: provider_nsg.id
    }
  }
}

resource provider_diag_sa 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: uniqueString(providerVmName, deployment().name)
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {}
}

resource provider_vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {  
  name: providerVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: provider_diag_sa.properties.primaryEndpoints.blob
      }
    }    
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: 'ProviderOsDisk'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        diskSizeGB: 64
      }
    }
    osProfile: {
      computerName: providerVmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: outboundOnly? base64(format(loadTextContent('ubuntu-outbound.yml'), consumer_pip.properties.ipAddress)) : base64(format(loadTextContent('ubuntu-tunnel.yml'), consumer_pip.properties.ipAddress))
      linuxConfiguration: {
        disablePasswordAuthentication: false
        /*
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: keyData
            }
          ]
        }
        */
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
        }
      }
      allowExtensionOperations: true
    }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: any(-1)
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: provider_pip_nic.id
          properties: {
            primary: true
          }
        }
        {
          id: provider_nic.id
          properties: {
            primary: false
          }
        }
      ]
    }
  }
}

resource consumer_nsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: consumerNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          description: 'Allow-SSH'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: consumerNsgSourceAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 210
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource consumer_pip 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: consumerVmPipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource consumer_vnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: consumerVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        consumerVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: consumerSubnetName
        properties: {
          addressPrefix: consumerSubnetAddressPrefix
          networkSecurityGroup: {
            id: consumer_nsg.id
          }
        }
      }
    ]
  }
}

resource consumer_nic 'Microsoft.Network/networkInterfaces@2021-03-01' = {
  name: consumerVmNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfigPip'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: consumer_vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: consumer_pip.id
          }
          gatewayLoadBalancer: {
            id: provider_lb.properties.frontendIPConfigurations[0].id
          }
        }
      }
    ]
  }
}

resource consumer_diag_sa 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: uniqueString(consumerVmName, deployment().name)
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {}
}

resource consumer_vm 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: consumerVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: consumerVmName
      adminUsername: adminUsername
      adminPassword: adminPassword      
      linuxConfiguration: {
        disablePasswordAuthentication: false
        /*
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: keyData
            }
          ]
        }
        */
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
        }
      }      
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: consumer_diag_sa.properties.primaryEndpoints.blob
      }
    }      
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: 'ConsumerOsDisk'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        diskSizeGB: 32
      }
    }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: any(-1)
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: consumer_nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

//output comsumerVMPublicIp string = consumer_pip.properties.ipAddress
//output providerVMPublicIp string = provider_pip.properties.ipAddress
