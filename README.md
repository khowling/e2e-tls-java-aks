
# End-2-End TLS with Azure Kubernetes Service and Application Gateway Ingress Controller

This repo demostrates deploying an example "Hello World" Java Spring Boot web app into a AKS clsuter, securly exposing it to the web using end-to-end TLS.  The following instructions will walk you though

1. Creating the AKS Cluster with ACR, AGIC, cert-manager & external-dns
2. Generating a Self-signed backend certificate & uploading into a Kubernetes secret
3. Compiling and running the App locally
4. Deploying the app to AKS

## Provisioning a cluster

Please use the ```AKS helper``` to provision your cluster, keep the default options of
  * ___I want a managed environment___
  
      and
  * ___Cluster with additional security controls___

Then, go into the ___Addon Details___ tab, and select the following options, providing all the require information
  * ___Create FQDN URLs for your applications using external-dns___

     and
  * ___Automatically Issue Certificates for HTTPS using cert-manager (with Lets Encrypt - requires email)___


This will create the full environment with everything configured inclduing AKS Cluster with ACR, AGIC, cert-manager & external-dns.

___NOTE___: Please relember to run the script on the ___Post Configuration___ tag to complete the deployment.




## Generate self signed PKCS12 backend cert



___NOTE___: The CN you provide the certificate needs to match the Ingress annotation : "appgw.ingress.kubernetes.io/backend-hostname" currently ___"openjdk-demo-service"___


```
# Create a private key and public certificate 
openssl req -newkey rsa:2048 -x509 -keyout cakey.pem -out cacert.pem -days 3650 

#create a JKS keystore
openssl pkcs12 -export -in cacert.pem -inkey cakey.pem -out identity.p12 -name "mykey"  
```

## Create the secret in AKS to hold the backend certificate


Create Secret

```
kubectl create secret generic openjdk-demo-tls --from-file=identity.p12=./identity.p12
```


## Upload backend cert to AppGw

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
mvn package

### Build the image locally
docker build -t ${ACRNAME}.azurecr.io/openjdk-demo:0.0.1 .
```

## Run container locally

When you use a bind mount, a file or directory on the host machine is mounted into a container. The file or directory is referenced by its absolute path on the host machine.

```
docker run -d \
  -it \
  -p 8080:8080 \
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

In the ```deployment.yml``` file replace the following values:

 * ```{{ACRNAME}}``` to your ACR name (ie ```myacr001```)
 * ```{{DNSZONE}}``` to ypur DNS zone (ie ```example.com```)


Deploy to AKS

```
 kubectl apply -f ./deployment.yml
```  

Your new webapp should be accessable on ```https://openjdk-demo.{{DNSZONE}}```

