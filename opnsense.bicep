@description('Admin username of os profile')
param adminUsername string = 'azadmin'

@description('Admin user ssh key data')
param keyData string = loadTextContent('key-data')

@description('Size of provider VM')
param providerVmSize string = 'Standard_A2_v2'

@description('Size of consumer VM')
param consumerVmSize string = 'Standard_A1_v2'


@description('Location to deploy all the resources in.ex. eastus2euap')
param location string = 'southeastasia'

var providerVmName = 'ProviderVm'
var providerNsgName = 'ProviderNsg'
var providerNicName = 'ProviderNic'
var providerPipNicName = 'ProviderPipNic'
var providerPipName = 'ProviderPip'
var providerVnetName = 'ProviderVnet'
var providerVnetAddressPrefix = '10.110.0.0/16'
var providerUntrustedSubnetName = 'ProviderUntrustedSubnet'
var providerUntrustedSubnetAddressPrefix = '10.110.0.0/24'
var providerTrustedSubnetName = 'ProviderTrustedSubnet'
var providerTrustedSubnetAddressPrefix = '10.110.1.0/24'
var providerTrustedSubnetGateway = '10.110.1.1'
var providerLbName = 'ProviderLb'


var consumerVmName = 'ConsumerVm'
var consumerNsgName = 'ConsumerNsg'
var consumerNicName = 'ConsumerNic'
var consumerPipName = 'ConsumerPip'
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
          sourceAddressPrefix: '*'
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
          sourceAddressPrefix: '*'
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
          privateIPAllocationMethod: 'Dynamic'
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
  name: providerNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
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
  name: providerPipName
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
  name: providerPipNicName
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

resource provider_vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: providerVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: providerVmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftOSTC'
        offer: 'FreeBSD'
        sku: '12.0'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: 'ProviderOsDisk'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: providerVmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: keyData
            }
          ]
        }
      }
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

resource vmext 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  name: '${provider_vm.name}/CustomScript'
  location: resourceGroup().location
  properties: {
    publisher: 'Microsoft.OSTCExtensions'
    type: 'CustomScriptForLinux'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: false
    settings:{
      fileUris: [
        'https://raw.githubusercontent.com/huangyingting/glb-demo/master/opnsense/install.sh'
      ]
      commandToExecute: 'sh install.sh ${providerTrustedSubnetGateway}'
    }
  }
}

resource consumer_nsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: consumerNsgName
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
          sourceAddressPrefix: '*'
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
          sourceAddressPrefix: '*'
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
  name: consumerPipName
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
  name: consumerNicName
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

resource consumer_vm 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: consumerVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: consumerVmSize
    }
    osProfile: {
      computerName: consumerVmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: keyData
            }
          ]
        }
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
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: 30
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
