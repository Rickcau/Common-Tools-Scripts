# Azure Secure Network Infrastructure Setup

This PowerShell script automates the deployment of a secure network infrastructure in Azure, consisting of a virtual network with segregated frontend and backend services, along with the necessary security configurations.

## Architecture Overview

The script sets up the following architecture:

```
Virtual Network (10.0.0.0/16)
├── Frontend Subnet (10.0.1.0/24)
│   └── Frontend Web App (with VNet Integration)
└── Backend Subnet (10.0.2.0/24)
    └── Backend Web App (with Private Endpoint)
```

## Features

- Virtual Network with isolated frontend and backend subnets
- Frontend Web App with:
  - VNet integration
  - Easy Auth (Azure AD authentication)
  - Linux-based B1 App Service Plan
  - Node.js 20 LTS runtime
- Backend Web App with:
  - Private Endpoint configuration
  - Disabled public access
  - Linux-based P1V2 App Service Plan
  - Node.js 20 LTS runtime
- Comprehensive error handling and cleanup
- Detailed logging

## Prerequisites

- Azure CLI installed and configured
- PowerShell 5.1 or higher
- Azure subscription with required permissions
- Existing resource group in the target region

## Usage

1. Configure the variables at the top of the script:
```powershell
$RESOURCE_GROUP = "rg-it-ops"          # Your existing resource group
$APP_LOCATION = "canadacentral"        # Desired location
$VNET_NAME = "it-ops-vnet"            # Name for the Virtual Network
$FRONTEND_APP_NAME = "it-ops-app"      # Frontend Web App name
$BACKEND_APP_NAME = "it-ops-backend"   # Backend Web App name
# ... additional variables
```

2. Run the script:
```powershell
.\Setup-Secure-VNet-App-Services.ps1
```

## Resource Naming Convention

- Virtual Network: `{prefix}-vnet`
- Subnets: 
  - `frontend-subnet`
  - `backend-subnet`
- App Service Plans:
  - Frontend: `frontend-plan`
  - Backend: `backend-plan`
- Web Apps:
  - Frontend: `{prefix}-app`
  - Backend: `{prefix}-backend`

## Network Configuration

- Virtual Network: 10.0.0.0/16
- Frontend Subnet: 10.0.1.0/24
- Backend Subnet: 10.0.2.0/24

## Security Features

1. Frontend Web App:
   - VNet integration for secure communication
   - Azure AD authentication enabled
   - Restricted network access through VNet

2. Backend Web App:
   - Private Endpoint for secure access
   - Public network access disabled
   - Isolated in backend subnet

## Error Handling

The script includes comprehensive error handling:
- Checks for existing resources before creation
- Automatic cleanup on failure
- Detailed error logging
- Exit codes for automation workflows

## Cleanup Process

The script includes a cleanup function that removes:
1. Frontend and Backend Web Apps
2. App Service Plans
3. Virtual Network (including subnets and private endpoints)

To manually trigger cleanup:
```powershell
Remove-Resources
```

## Logging

The script provides detailed logging with timestamps:
- Success messages in green
- Error messages in red
- Progress updates for each deployment step

## Common Issues and Troubleshooting

1. Resource Name Conflicts
   - Check if resources with the same names exist
   - Use unique prefixes for your deployment

2. Permission Issues
   - Ensure Azure CLI is authenticated
   - Verify you have required permissions in the resource group
   - Check subscription access

3. Network Configuration
   - Verify subnet address spaces don't overlap
   - Check for available address space in the VNet
   - Ensure private endpoint subnet has required configurations

## Best Practices

1. Resource Naming
   - Use consistent naming conventions
   - Include environment indicators
   - Follow organization naming standards

2. Network Security
   - Keep frontend and backend services separated
   - Use private endpoints where possible
   - Implement least-privilege access

3. Deployment
   - Test in non-production environment first
   - Review generated resources after deployment
   - Monitor deployment logs

## Contributing

When modifying this script:
1. Follow existing error handling patterns
2. Maintain the logging structure
3. Update documentation for new features
4. Test thoroughly before deployment

## Support

For issues or questions:
1. Check the detailed logs
2. Review Azure Portal for resource status
3. Verify Azure CLI version
4. Check network requirements