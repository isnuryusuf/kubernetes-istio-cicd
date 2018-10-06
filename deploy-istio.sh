#!/bin/bash
cd /root/
launch.sh>&2
if [[ ! -d "/root/istio-1.0.0" ]]; then
  echo "Downloading Istio... this may take a couple of moments">&2
  curl -s -L https://git.io/getLatestIstio | ISTIO_VERSION=1.0.0 sh -
  echo "Download completed. Configuring Kubernetes.">&2
else
  echo "Istio already exists">&2
fi
export PATH="$PATH:/root/istio-1.0.0/bin";
cd /root/istio-1.0.0
kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml -n istio-system
kubectl apply -f install/kubernetes/istio-demo-auth.yaml
kubectl apply -f /root/katacoda.yaml

# kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
# kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
# kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml

curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v1.yaml https://gist.githubusercontent.com/BenHall/e5fa7eed7e1b0bc21ac0abbd431efc37/raw/bed904fb75516e8e0dd87c86c5b274fb4c5e372c/virtual-service-reviews-v1.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v2.yaml https://gist.githubusercontent.com/BenHall/e5fa7eed7e1b0bc21ac0abbd431efc37/raw/cf8426de87eb29716f41070bb619c6f4fbd759af/virtual-service-reviews-v2.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-chrome-v2.yaml https://gist.githubusercontent.com/BenHall/e5fa7eed7e1b0bc21ac0abbd431efc37/raw/c3c3a25721af90e180c1b02c618d6c8b660402d7/virtual-service-reviews-chrome-v2.yaml

cat <<EOF >> /root/istio-1.0.0/serviceEntry.yaml
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: httpbin-ext
spec:
  hosts:
  - httpbin.org
  ports:
  - number: 80
    name: http
    protocol: HTTP
  resolution: DNS
  location: MESH_EXTERNAL
EOF

kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl get pods

# To make the application available to the outside world a Gateway needs to be deployed. 
# Within Kubernetes this is managed with Ingress that specifies services that should be exposed outside the cluster.
# Within Istio, the Istio Ingress Gateway defines this via configuration.
# A Gateway allows Istio features such as monitoring and route rules to be applied to traffic entering the cluster.
kubectl get svc --all-namespaces | grep istio-ingressgateway


# An example of extending the gateway is this:
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: bookinfo-gateway
spec:
  selector:
    istio: ingressgateway # use istio default controller
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
# Because we are using a wildcard (*) character for the host and only one route rule, all traffic from this gateway 
# to the frontend service (as defined in the VirtualService)

cat samples/bookinfo/networking/bookinfo-gateway.yaml
# This file contains two objects. The first object is a Gateway, which will allow us to bind to the "istio-ingressgateway" 
# that exists in the cluster. The second object, a VirtualService, will be discussed in the next step.
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
# To view all gateways on the system, run 
kubectl get gateway

# A VirtualService defines a set of traffic routing rules to apply when a host is addressed. https://istio.io/docs/reference/config/istio.networking.v1alpha3/#VirtualService
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: ratings
spec:
  hosts:
  - ratings
  http:
  - route:
    - destination:
        host: ratings
        subset: v1

# In the above example, we are sending all traffic for the Rating service to v1.
# The VirtualService traffic will be then be processed by the DestinationRule which will load balance based on LEAST_CONN.
# For our BookInfo application, because we are using a wildcard (*) character for the host and only one route rule, 
# all traffic from this gateway to the frontend service. This is defined by the combination of our Gateway and Virtual Services.\

# When you visit the application, the traffic will be initially processed by our Gateway, 
# with rules defined by the Virtual Services to explain which Kubernetes Pod should process the request.
# The application can be accessed at http://<IP-Kubenetes-Master>/productpage

# While a VirtualService configures traffic flows, a DestinationRule defines policies that apply to traffic intended 
# for a service after routing has occurred.
# The following rule defines that the load balancer should be using LEAST_CONN, 
# meaing route the pod with the least active connnections.

apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: bookinfo-ratings
spec:
  host: ratings.prod.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      simple: LEAST_CONN
      
# The following rule indicates traffic should be load balanced across three different versions based on the Pod labels, v1, v2 and v3.
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: reviews
spec:
  host: reviews
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
      
# Within this rule, it also defines that the connections should be over TLS.
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
      
# Without the DestinationRule, Istio cannot route the internal traffic.


# Apply default destination rules
# Before you can use Istio to control the Bookinfo version routing, you need to define the available versions, called subsets, in destination rules.
cat samples/bookinfo/networking/destination-rule-all-mtls.yaml
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
kubectl get destinationrules

# Now when you visit the Product Page the reviews will appear. As three versions have been defined within our Destination Rule
# By default, it will load balance across all available review services.

# Step 6 - Deploying Virtual Services
# For the Bookinfo application, we have three different versions of a Reviews service available. The reviews service provides a short review, together with a star rating in the newer versions.
# By default, Istio and Kubernetes will load balance the requests across all the available services. We can use a Virtual Service to control our traffic and force it to only be processed by V1.
cat samples/bookinfo/networking/virtual-service-all-v1.yaml
# The file defines the Virtual Services for all the application. For every application, a host is defined (such as productpage), which is a DNS entry of how other applications will communicate with the service. Based on requests to this host, the route defines the destination and which Pods should handle the request.
# This is deployed via 
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
# When you visit the Product Page you will only see the reviews coming from our V1 service.

# List All Routes
# It's possible to get a list of all the rules applied using 
kubectl get virtualservices 
# and 
kubectl get virtualservices reviews -o yaml


# Step 7 - Updating Virtual Services
# As with all Kubernetes objects, Virtual Services can be updated which will change how our traffic is processed within the system.
# This Virtual Service sends all traffic to the V2 rating service, meaning our application would return the star rating
cat samples/bookinfo/networking/virtual-service-reviews-v2.yaml
# This is deployed via 
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v2.yaml
# When you visit the Product Page you will now see the results from V2.
# These Virtual Services become the heart of controlling and shaping the traffic within our system.


# Step 8 - Egress
# While the Bookinfo application doesn't need to call external applications, certain applications do.
# Istio is security focused, meaning applications cannot access external services by default. Instead, the egress (outbound) traffic needs to be configured.
# Deploy a simple Sleep pod which will attempt to access an external service.
kubectl apply -f <(istioctl kube-inject -f samples/sleep/sleep.yaml)

# Once started, attach to the container:
export SOURCE_POD=$(kubectl get pod -l app=sleep -o jsonpath={.items..metadata.name})
kubectl exec -it $SOURCE_POD -c sleep bash
# When you attempt to access an external service, it will return a 404.
curl http://httpbin.org/headers -i

# We need to configure our Egress. Exit the container as we need to deploy additional components.
# Egress is configured via a ServiceEntry. The ServiceEntry defines how the external can be reached.
kubectl apply -f /root/istio-1.0.0/serviceEntry.yaml
cat /root/istio-1.0.0/serviceEntry.yaml
# Repeat the process of attaching to the container:
kubectl exec -it $SOURCE_POD -c sleep bash
# When you attempt to access an external service, it will now return the expected response.
curl http://httpbin.org/headers -i
# Within the response, you can also identify all the additional metadata Istio includes to help build metrics, traceability and insights into the inner-workings of the network. These will be explored within the Observing Microservices with Istio course.
# More information at https://istio.io/docs/tasks/traffic-management/egress/#configuring-the-external-services


