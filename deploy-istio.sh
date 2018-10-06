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
