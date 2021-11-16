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

@description('Admin user ssh key data')
param keyData string = loadTextContent('key-data')

@description('Size of the VM')
param vmSize string = 'Standard_A1_v2'

@description('Location to deploy all the resources')
param location string = 'southeastasia'

var providerVmName = 'ProviderVm'
var providerNicName = 'ProviderNic'
var providerPipNicName = 'ProviderPipNic'
var providerPipName = 'ProviderPip'
var providerVnetName = 'ProviderVnet'
var providerSubnetName = 'ProviderSubnet'
var providerLbName = 'ProviderLb'
var nsgName = 'DefaultNsg'
var consumerVmName = 'ConsumerVm'
var consumerNicName = 'ConsumerNic'
var consumerPipName = 'ConsumerPip'
var consumerVnetName = 'ConsumerVnet'
var consumerSubnetName = 'ConsumerSubnet'

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Tcp-Inbound-Allow-All'
        properties: {
          description: 'Tcp-Inbound-Allow-All'
          protocol: 'Tcp'
          sourcePortRange: '0-65535'
          destinationPortRange: '0-65535'
          sourceAddressPrefix: '0.0.0.0/0'
          destinationAddressPrefix: '0.0.0.0/0'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
      {
        name: 'Tcp-Outbound-Allow-All'
        properties: {
          description: 'Tcp-Outbound-Allow-All'
          protocol: 'Tcp'
          sourcePortRange: '0-65535'
          destinationPortRange: '0-65535'
          sourceAddressPrefix: '0.0.0.0/0'
          destinationAddressPrefix: '0.0.0.0/0'
          access: 'Allow'
          priority: 200
          direction: 'Outbound'
        }
      }
      {
        name: 'Udp-Inbound-Allow-All'
        properties: {
          description: 'Udp-Inbound-Allow-All'
          protocol: 'Udp'
          sourcePortRange: '0-65535'
          destinationPortRange: '0-65535'
          sourceAddressPrefix: '0.0.0.0/0'
          destinationAddressPrefix: '0.0.0.0/0'
          access: 'Allow'
          priority: 300
          direction: 'Inbound'
        }
      }
      {
        name: 'Udp-Outbound-Allow-All'
        properties: {
          description: 'Udp-Outbound-Allow-All'
          protocol: 'Udp'
          sourcePortRange: '0-65535'
          destinationPortRange: '0-65535'
          sourceAddressPrefix: '0.0.0.0/0'
          destinationAddressPrefix: '0.0.0.0/0'
          access: 'Allow'
          priority: 300
          direction: 'Outbound'
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
        '10.55.0.0/16'
      ]
    }
    subnets: [
      {
        name: providerSubnetName
        properties: {
          addressPrefix: '10.55.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
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
          privateIPAddress: '10.55.0.128'
          subnet: {
            id: provider_vnet.properties.subnets[0].id
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
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.55.0.4'
          subnet: {
            id: provider_vnet.properties.subnets[0].id
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
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.55.0.5'
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
      id: nsg.id
    }
  }
}

resource provider_vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: providerVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
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
        name: 'ProviderOsDisk'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: 30
      }
    }
    osProfile: {
      computerName: providerVmName
      adminUsername: adminUsername
      customData: loadFileAsBase64('user-data.yml')
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
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
        }
      }
      allowExtensionOperations: true
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
        '10.2.0.0/16'
      ]
    }
    subnets: [
      {
        name: consumerSubnetName
        properties: {
          addressPrefix: '10.2.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
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
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.2.0.4'
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
      vmSize: vmSize
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
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
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

//output comsumerVMPublicIp string = consumer_pip.properties.ipAddress
//output providerVMPublicIp string = provider_pip.properties.ipAddress
