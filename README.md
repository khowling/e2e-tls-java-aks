
# End-2-End TLS with Azure Kubernetes Service and Application Gateway Ingress Controller

This repo demostrates deploying an example "Hello World" Java Spring Boot web app into a AKS clsuter, securly exposing it to the web using end-to-end TLS.  The following instructions will walk you though

1. Creating the AKS Cluster with ACR, AGIC, cert-manager & external-dns
2. Generating a Self-signed backend certificate & uploading into a Kubernetes secret
3. Compiling and running the App locally
4. Deploying the app to AKS

## Provisioning a cluster

Please use the [AKS helper](https://azure.github.io/Aks-Construction) to provision your cluster, keep the default options of
  * __I want a managed environment__
  * __Cluster with additional security controls__

Then, go into the __Addon Details__ tab, and select the following options, providing all the require information
  * __Create FQDN URLs for your applications using external-dns__
  * __Automatically Issue Certificates for HTTPS using cert-manager (with Lets Encrypt - requires email)__


__NOTE:__ If you want to store your certs in KeyVault (recommended), please also select the follwo option from the __Addon Details__ tab:
  * __Store Kubernetes Secrets in Azure Keyvault, using AKS Managed Identity__


This will create the full environment with everything configured inclduing AKS Cluster with ACR, AGIC, cert-manager & external-dns.

___NOTE___: Please relember to run the script on the __Post Configuration__ tag to complete the deployment.




## Generate self signed PKCS12 backend cert

__NOTE__: The CN you provide the certificate needs to match the Ingress annotation : "appgw.ingress.kubernetes.io/backend-hostname" currently ___"openjdk-demo-service"___


```
# Create a private key and public certificate 
openssl req -newkey rsa:2048 -x509 -keyout cakey.pem -out cacert.pem -days 3650 

# Create a JKS keystore
openssl pkcs12 -export -in cacert.pem -inkey cakey.pem -out identity.pfx 

# Record your key store passwd for the following commands:
export KEY_STORE_PASSWD=<your pfx keystore password>
```

__NOTE:__ If you are using the [CSI Secret Store Driver](https://docs.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) addon, you can ensure the secret is stored in an [Azure KeyVault](https://azure.microsoft.com/en-gb/services/key-vault/). Create Your Secret like this:

## Option (A) Using CSI Secret & KeyVault (recommended)

Add Secret and Certificate to the vault
```
export KVNAME=kv-azk8s56xy

## Create Key store password in KeyVault as secret
az keyvault secret set --name key-store-password --vault-name $KVNAME  --value=${KEY_STORE_PASSWD}

## Import Cert into keyvault
## Cannot mount as binary :( (objectEncoding only supported for objectType: secret)
## https://github.com/Azure/secrets-store-csi-driver-provider-azure/issues/138#issuecomment-874909741
az keyvault certificate import --vault-name $KVNAME --name openjdk-demo-service --password $KEY_STORE_PASSWD --file ./identity.pfx

## Alternative, store as secret!
az keyvault secret set --vault-name $KVNAME  --name openjdk-demo-secret -e base64  --file ./identity.pfx
```

Create a `SecretProvideClass` in AKS, to allow AKS to reference the values in the KeyVault


```
## Get the identity created from the KeyVaultSecert Addon
export AKSRG=xxx
export AKSNAME=xxx
export CSISECRET_CLIENTID=$(az aks show  --resource-group $AKSRG --name $AKSNAME --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)

## Assign KV access to CSI Secret addon
az keyvault  set-policy -n $KVNAME --secret-permissions  get list --certificate-permissions get list --spn $CSISECRET_CLIENTID


## Get your tenantId
export KVTENANT=$(az account show --query tenantId -o tsv)

echo "
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-${KVNAME}
spec:
  provider: azure
  secretObjects:
  - secretName: openjdk-demo-cert
    type: Opaque
    data: 
    - objectName: key-store-password
      key: key-store-password
  parameters:
    usePodIdentity: \"false\"         # [OPTIONAL] if not provided, will default to "false"
    useVMManagedIdentity: \"true\"
    userAssignedIdentityID: \"${CSISECRET_CLIENTID}\"
    keyvaultName: \"${KVNAME}\"          # the name of the KeyVault
    cloudName: \"\"                   # [OPTIONAL for Azure] if not provided, azure environment will default to AzurePublicCloud 
    objects:  |
      array:
        - |
          objectName: key-store-password
          objectType: secret 
        - |
          objectName: openjdk-demo-secret
          objectAlias: identity.p12
          objectType: secret
          objectFormat: PFX
          objectEncoding: base64
    tenantId: \"${KVTENANT}\"                 # the tenant ID of the KeyVault
" | kubectl apply -f -
```

### Upload backend cert to AppGw

This step is required if your backend cert is not a CA-signed cert, or a CA known to AppGw: https://azure.github.io/application-gateway-kubernetes-ingress/tutorials/tutorial.e2e-ssl/


```
## https://docs.microsoft.com/en-us/azure/application-gateway/key-vault-certs#how-integration-works

export AGNAME=xxx
export AGRG=xxx

## https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/key-vault-parameter?tabs=azure-cli
## Property to specify whether Azure Resource Manager is permitted to retrieve secrets from the key vault
az keyvault update  --name $KVNAME --enabled-for-template-deployment true

## Create AppGW Identity to access KeyVault & Assign perms
az identity create --name id-${AGNAME}  --resource-group $AGRG

## May need to wait a minute or so until the Ideneity is propergated
az keyvault  set-policy -n $KVNAME --secret-permissions set delete get list --spn $(az identity show  --resource-group $AGRG --name id-${AGNAME} --query clientId -o tsv)

## Assign Identity to AppGW
az network application-gateway identity assign -g $AGRG --gateway-name $AGNAME --identity $(az identity show  --resource-group $AGRG --name id-${AGNAME} --query id -o tsv)

## Create Root Cert reference in AppGW
az network application-gateway root-cert create \
     --gateway-name $AGNAME  \
     --resource-group $AGRG \
     --name openjdk-demo-service \
     --keyvault-secret $(az keyvault secret list-versions --vault-name $KVNAME -n openjdk-demo-service --query "[?attributes.enabled].id" -o tsv)
```


## Option (B) Using Kubernetes Secrets

Create Secret

```
kubectl create secret generic openjdk-demo-cert  --from-literal=key-store-password=${KEY_STORE_PASSWD} --from-file=identity.p12=./identity.p12
```


### Upload backend cert to AppGw

This step is required if your backend cert is not a CA-signed cert, or a CA known to AppGw: https://azure.github.io/application-gateway-kubernetes-ingress/tutorials/tutorial.e2e-ssl/


```
openssl x509 -outform der -in cacert.pem -out cacert.crt


applicationGatewayName=xxx
resourceGroup=xxx
az network application-gateway root-cert create \
    --gateway-name $applicationGatewayName  \
    --resource-group $resourceGroup \
    --name backend-tls \
    --cert-file cacert.crt
```



## Build / Run Java App


export ACRNAME=xxx


### Create Docker container

Set ```ACRNAME``` to the container registry that was created by the wizzard

```
### Create a deployable jar file
SSL_ENABLED="false" mvn package

### Build the image locally
docker build -t ${ACRNAME}.azurecr.io/openjdk-demo:0.0.1 .
```

## Run container locally

When you use a bind mount, a file or directory on the host machine is mounted into a container. The file or directory is referenced by its absolute path on the host machine.

```
docker run -d \
  -it \
  -p 8080:8080 \
  --env SSL_ENABLED="true" \
  --env SSL_STORE=/cert/identity.p12 \
  --env KEY_STORE_PASSWD=${KEY_STORE_PASSWD} \
  --name openjdk-demo \
  --mount type=bind,source="$(pwd)"/identity.p12,target=/cert/identity.p12,readonly  \
  ${ACRNAME}.azurecr.io/openjdk-demo:0.0.1
```

## Deploy to ACR & kubernetes

  Upload to ACR

```
az acr login -n  ${ACRNAME}
docker push ${ACRNAME}.azurecr.io/openjdk-demo:0.0.1
```

In the ```deployment.yml``` __or__ ```deployment-csi.yml``` (latter if using CSI Secrets) file replace the following values:

 * ```{{ACRNAME}}``` to your ACR name (ie ```myacr001```)
 * ```{{DNSZONE}}``` to ypur DNS zone (ie ```example.com```)


Deploy to AKS

```
 kubectl apply -f ./yourdeployment.yml
```  

Then, after 3-4 minutes (while the dns and certificates are generated), your new webapp should be accessable on ```https://openjdk-demo.{{DNSZONE}}```

