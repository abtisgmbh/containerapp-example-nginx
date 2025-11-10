#!bin/bash
# requires apt package xxhash

rgName=rg-abtis-test
location=westeurope
webappName=app-abtis-cco-test
appservicePlan=asp-abtis-cco-test
containerappEnv=cae-abtis-cco-test

rgId=$(az group create -n $rgName -l $location --query 'id' -o tsv)
suffix=$(echo $rgId | xxhsum -q | awk '{print $1}')
storageaccountName="sa${suffix}"

az appservice plan create -g $rgName -n $appservicePlan --is-linux
az webapp create -g $rgName -p $appservicePlan -n $webappName --runtime "TOMCAT:10.1-java17"
az webapp deploy --resource-group $rgName --name $webappName --src-path .build/sample.war --type war

az containerapp env create -n $containerappEnv -g $rgName --location $location

#Storage Mounts konfigurieren: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts?pivots=azure-cli&tabs=smb
az storage account create -n $storageaccountName -g $rgName -l $location --sku Standard_LRS
storageaccountKey=$(az storage account keys list -g $rgName -n $storageaccountName --query '[0].value' -o tsv)
az containerapp env storage set --name $containerappEnv --resource-group $rgName \
    --storage-name 'azurefile' \
    --storage-type AzureFile \
    --azure-file-account-name $storageaccountName \
    --azure-file-account-key $storageaccountKey \
    --azure-file-share-name nginx \
    --access-mode ReadOnly

az storage share create --account-name $storageaccountName --name nginx --account-key $storageaccountKey
az storage file upload --account-key $storageaccountKey \
    --account-name $storageaccountName \
    --path nginx.conf \
    --share-name nginx \
    --source ./containerapp/nginx/nginx.conf


az containerapp compose create -g $rgName --environment $containerappEnv --compose-file-path "./containerapp/docker-compose.yaml"
az containerapp show \
  --name nginx \
  --resource-group $rgName \
  --output yaml > nginx.yaml

#     volumeMounts:
#       - volumeName: nginxvol
#         mountPath: /etc/nginx/nginx.conf
#         subPath: nginx.conf
# volumes:
# - name: nginxvol
#   storageType: AzureFile
#   storageName: azurefile


az containerapp update --name nginx --resource-group $rgName --yaml containerapp/nginx.yaml

az containerapp show \
  --name web \
  --resource-group $rgName \
  --output yaml > web.yaml

#    ingress:
#       external: false
#       targetPort: 8000
#       allowInsecure: true

az containerapp update --name web --resource-group $rgName --yaml containerapp/web.yaml

