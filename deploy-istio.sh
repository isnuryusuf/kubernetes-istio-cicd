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
# all traffic from this gateway to the frontend service. This is defined by the combination of our Gateway and Virtual Services.
