# Azure Infrastructure as Code - Frontend/Backend Application Setup

This infrastructure as code (IaC) deployment creates a complete environment for a frontend/backend application with OpenAI and Cosmos DB integration.

## Resources Deployed

- Frontend App Service (Node.js 20 LTS)
- Backend App Service (.NET 8)
- Azure OpenAI Service
  - GPT-4o deployment
  - Text embeddings deployment
- Azure Cosmos DB (Serverless)
  - ChatHistory container
  - Users container
- Managed Identities for both services
- RBAC role assignments

## Prerequisites

1. Azure CLI
2. Azure Developer CLI (azd)
3. Bicep CLI
4. Azure Subscription with permissions to create resources
5. Access to Azure OpenAI service

## Deployment Steps

1. Clone the repository:
```bash
git clone <repository-url>
cd <repository-name>
```

2. Initialize the Azure Developer CLI environment:
```bash
azd init
```

3. Deploy the infrastructure:
```bash
azd up
```

If your deployment is successful you see results that look like this...

![successful-az-up](././Images/successful-azd-up.jpg)

You will be prompted for:
- Environment name
- Azure location (e.g., 'eastus')

## Architecture Details

### Frontend App Service
- Node.js 20 LTS runtime
- User-assigned managed identity
- Communicates with backend through CORS-enabled endpoints

### Backend App Service
- .NET 8 runtime
- User-assigned managed identity
- Direct access to Cosmos DB and OpenAI
- CORS configured for frontend communication

### Security
- Key-based authentication disabled for Cosmos DB
- All service communication uses managed identities
- Frontend can only access backend API
- Backend has restricted access to Cosmos DB and OpenAI

## Configuration

The deployment uses standard naming conventions with the following format:
- Resource Group: {environmentName}
- Frontend App: web-fe-{resourceToken}
- Backend App: web-be-{resourceToken}
- Cosmos DB: cosmos-{resourceToken}
- OpenAI: openai-{resourceToken}

## Important Notes

1. OpenAI service deployment uses specific model versions:
   - GPT-4o : Version 2024-08-06
   - Text Embeddings: Version 2

2. Cosmos DB is configured in serverless mode for cost optimization

3. App Services use Linux-based hosting

## Validation

To validate the Bicep templates before deployment:
```bash
az deployment sub validate --location eastus --template-file main.bicep
```

## Folder Structure

Below is an example of the file struture that you need to use.  

```
project_root/
├── Infra/
│   ├── app/
│   │   ├── ai.bicep
│   │   ├── database.bicep
│   │   ├── identity.bicep
│   │   ├── security.bicep
│   │   └── web.bicep
│   ├── core/
│   │   ├── database/
│   │   │    ├── cosmos-db/
│   │   │    │   ├── nosql/
│   │   │    │   │   ├── role/
│   │   │    │   │   │   ├── assignment.bicep
│   │   │    │   │   │   └── definition.bicep
│   │   │    │   │   ├── account.bicep
│   │   │    │   │   ├── container.bicep
│   │   │    │   │   └── database.bicep
│   │   │    │   └── account.bicep
│   │   ├── host/
│   │   │    ├── app-service/
│   │   │    │   ├── config.bicep
│   │   │    │   ├── plan.bicep
│   │   │    │   └── site.bicep
│   │   ├── security/
│   │   │    ├── identity/
│   │   │    │   └── user-assigned.bicep
│   │   │    ├── role/
│   │   │    │   ├── assignment.bicep
│   │   │    │   └── definition.bicep
│   ├── abbreviations.json
│   ├── main.bicep
│   ├── main.parameters.json
│   └── main.test.bicep
├── azure.yaml
└── file_map.txt
```
## How to use this Infrastructure as Code with your repository

For example purposes, let's use [Semantic Kernel 101](https://github.com/Rickcau/Semantic-Kernel-101) repository as an example.

1. First copy the **azure.yaml** to the root of the repo.
2. Now, create an Infra folder in the root of the repo.
3. Copy all the folders and files from this into the newly created Infra folder.
4. Double check and make sure your **folder structure** matches the above structure.
5. Run the validation against the main.bicep to make sure you get no errors.
```
az deployment sub validate --location eastus --template-file main.bicep
```
6. Now, run 
```
azd init
```
7. Now, run 
```
azd init
```
8. Now, navigate to the Azure Portal and the resource group and verify everything was properly provisioned.
