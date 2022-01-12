# Moved

This project has moved to https://github.com/Azure-Samples/java-aks-keyvault-tls

Please go to the new repo to get the latest version!

## End-2-End TLS with Azure Kubernetes Service and Application Gateway Ingress Controller & CSI Sercret

This repo demostrates deploying an example "Hello World" Java Spring Boot web app into a AKS clsuter, securly exposing it to the web using end-to-end TLS.

This example uses the Azure Kubernetes managed WAF ingress __Applicaiton Gateway__, and the [CSI Secret Store Driver](https://docs.microsoft.com/azure/aks/csi-secrets-store-driver) addon, to store the certificates in [Azure KeyVault](https://azure.microsoft.com/services/key-vault/). 



## Provisioning a cluster

Use the [AKS helper](https://azure.github.io/Aks-Construction) to provision your cluster, and configure the helper as follows:

Keep the default options for:
  * __Operations Principles__: __"I want a managed environment"__
  * __Security Principles__: __"Cluster with additional security controls"__

Now, to configure the TLS Ingress, go into the __Addon Details__ tab

  In the section __Securely Expose your applications via Layer 7 HTTP(S) proxies__, select the following options, providing all the require information

  * __Create FQDN URLs for your applications using external-dns__
  * __Automatically Issue Certificates for HTTPS using cert-manager__


  __NOTE:__ In the section __CSI Secrets : Store Kubernetes Secrets in Azure Keyvault, using AKS Managed Identity__,  ensure the following option is selected: __Yes, provision a new Azure KeyVault & enable Secrets Store CSI Driver__.  Also, __Enable KeyVault Integration for TLS Certificates__ is selected, this will integrate Application Gateway access to KeyVault,  and 


Now, under the __Deploy__ tab, execute the commands to provision your complete environment. __NOTE__: Once complete, please relember to run the script on the __Post Configuration__ tab to complete the deployment.





## Run container locally (OPTIONAL)


### Generate self signed PKCS12 backend cert, for local testing only

```
# Create a private key and public certificate 
openssl req -newkey rsa:2048 -x509 -keyout cakey.pem -out cacert.pem -days 3650 

# Create a JKS keystore
openssl pkcs12 -export -in cacert.pem -inkey cakey.pem -out identity.pfx 

# Record your key store passwd for the following commands:
export KEY_STORE_PASSWD=<your pfx keystore password>
```

NOTE: When you use a bind mount, a file or directory on the host machine is mounted into a container. The file or directory is referenced by its absolute path on the host machine.


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