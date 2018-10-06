##################################################################################
# Environment:
# CentOS Linux release 7.5.1804 (Core) minimal installation
# 1 master node (4vCpu, 4Gb RAM, 20GB Disk, Nat or Wan or Bridge Network) 
# 1 Worker Node or More (2vCpu, 2Gb RAM, 20GB Disk, Nat or Wan or Bridge Network)
# 
# /etc/hosts file
# 172.16.0.20	worker1.variasimx.com (Kubernetes Node1)
# 172.16.0.21	worker2.variasimx.com (Kubernetes Node1)
# 172.16.0.22	master.variasimx.com (Kubernetes Master, please take not this IP)
##################################################################################

# Prepare Operating System
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
systemctl disable firewalld

bash -c 'cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF'

yum repolist; yum -y update; reboot
yum install kubeadm kubelet kubectl docker -y

systemctl enable docker
systemctl enable kubelet

# Enable BR filter
modprobe br_netfilter
bash -c 'cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF'
sysctl -p
echo 1 >  /proc/sys/net/bridge/bridge-nf-call-iptables
echo 1 >  /proc/sys/net/bridge/bridge-nf-call-ip6tables

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configuration of the Kubernetes Master (172.16.0.22 my master IP, 192.168.0.0/16 is default istio Network)
kubeadm init --apiserver-advertise-address=172.16.0.22  --pod-network-cidr=192.168.0.0/16
# Take note on --discovery-token-ca-cert-hash
kubectl cluster-info

# COpy credential to home dir and set permission
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
  
# join node to master
kubeadm join 172.16.0.22:6443 --token ly4swk.uyxl37ovhi0m7ktt --discovery-token-ca-cert-hash <token-hash>
kubectl get nodes
  
# Deploy CNI using weave
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
  
# make sure core-dns is up and running
watch -n 2 kubectl get pods --all-namespaces -o wide
kubectl get nodes
  
# Install ISTIO
cd /root/
curl -L https://git.io/getLatestIstio | ISTIO_VERSION=1.0.0 sh -
export PATH="$PATH:/root/istio-1.0.0/bin"
cd /root/istio-1.0.0

# Configure Istio CRD
# Istio has extended Kubernetes via Custom Resource Definitions (CRD). Deploy the extensions by applying crds.yaml
kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml -n istio-system

# Install Istio with default mutual TLS authentication
# To Install Istio and enforce mutual TLS authentication by default, use the yaml istio-demo-auth.yaml:
kubectl apply -f install/kubernetes/istio-demo-auth.yaml
# This will deploy Pilot, Mixer, Ingress-Controller, and Egress-Controller, and the Istio CA (Certificate Authority). 
# These are explained in the next step.

# Check Status, All the services are deployed as Pods.
kubectl get pods -n istio-system
kubectl get svc -n istio-system

# The previous step deployed the Istio Pilot, Mixer, Ingress-Controller, and Egress-Controller, and the Istio CA 
# (Certificate Authority).
# * Pilot - Responsible for configuring the Envoy and Mixer at runtime.
# * Proxy / Envoy - Sidecar proxies per microservice to handle ingress/egress traffic between services in the cluster and from a service to external services. The proxies form a secure microservice mesh providing a rich set of functions like discovery, rich layer-7 routing, circuit breakers, policy enforcement and telemetry recording/reporting functions.
# * Mixer - Create a portability layer on top of infrastructure backends. Enforce policies such as ACLs, rate limits, quotas, authentication, request tracing and telemetry collection at an infrastructure level.
# * Citadel / Istio CA - Secures service to service communication over TLS. Providing a key management system to automate key and certificate generation, distribution, rotation, and revocation.
# * Ingress/Egress - Configure path based routing for inbound and outbound external traffic.
# * Control Plane API - Underlying Orchestrator such as Kubernetes or Hashicorp Nomad.
# Topologi: https://katacoda.com/courses/istio/deploy-istio-on-kubernetes/assets/istio-arch1.png

# Deploy Sample Application
# - To showcase Istio, a BookInfo web application has been created. This sample deploys a simple application composed 
# - of four separate microservices which will be used to demonstrate various features of the Istio service mesh.
# - When deploying an application that will be extended via Istio, the Kubernetes YAML definitions are extended via kube-inject. 
# - This will configure the services proxy sidecar (Envoy), Mixers, Certificates and Init Containers.
kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl get pods
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml

  
kubectl create deployment nginx --image=nginx
kubectl create service nodeport nginx --tcp=80:80
kubectl get svc
watch -n 2 kubectl get pods --all-namespaces -o wide
curl worker1.variasimx.com:31750
kubectl delete service nginx
curl worker1.variasimx.com:31750
kubectl get svc
kubectl create service clusterip  nginx --tcp=80:80
kubectl get svc
curl 10.106.161.83


# Expose bookinfo sample app component
# To make the sample BookInfo application and dashboards available to the outside world, 
# in particular, on Katacoda, deploy the following Yaml
#------- cut here ------
bash -c 'cat <<EOF > /root/expose.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: servicegraph
    chart: servicegraph-0.1.0
    heritage: Tiller
    release: RELEASE-NAME
  name: katacoda-servicegraph
  namespace: istio-system
spec:
  ports:
  - name: http
    port: 8088
    protocol: TCP
    targetPort: 8088
  selector:
    app: servicegraph
  type: ClusterIP
  externalIPs:
    - 172.16.0.22
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: grafana
    chart: grafana-0.1.0
    heritage: Tiller
    release: RELEASE-NAME
  name: katacoda-grafana
  namespace: istio-system
spec:
  ports:
  - name: http
    port: 3000
    protocol: TCP
    targetPort: 3000
  selector:
    app: grafana
  sessionAffinity: None
  type: ClusterIP
  externalIPs:
    - 172.16.0.22
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: jaeger
    chart: tracing-0.1.0
    heritage: Tiller
    jaeger-infra: jaeger-service
    release: RELEASE-NAME
  name: katacoda-jaeger-query
  namespace: istio-system
spec:
  ports:
  - name: query-http
    port: 16686
    protocol: TCP
    targetPort: 16686
  selector:
    app: jaeger
  type: ClusterIP
  externalIPs:
    - 172.16.0.22
---
apiVersion: v1
kind: Service
metadata:
  labels:
    name: prometheus
  name: katacoda-prometheus
  namespace: istio-system
spec:
  ports:
  - name: http-prometheus
    port: 9090
    protocol: TCP
    targetPort: 9090
  selector:
    app: prometheus
  type: ClusterIP
  externalIPs:
    - 172.16.0.22
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: istio-ingressgateway
    chart: gateways-1.0.0
    heritage: Tiller
    istio: ingressgateway
    release: RELEASE-NAME
  name: istio-ingressgateway
  namespace: istio-system
spec:
  externalTrafficPolicy: Cluster
  ports:
  - name: http2
    nodePort: 31380
    port: 80
    protocol: TCP
    targetPort: 80
  - name: https
    nodePort: 31390
    port: 443
    protocol: TCP
    targetPort: 443
  - name: tcp
    nodePort: 31400
    port: 31400
    protocol: TCP
    targetPort: 31400
  - name: tcp-pilot-grpc-tls
    nodePort: 32565
    port: 15011
    protocol: TCP
    targetPort: 15011
  - name: tcp-citadel-grpc-tls
    nodePort: 32352
    port: 8060
    protocol: TCP
    targetPort: 8060
  - name: http2-prometheus
    nodePort: 31930
    port: 15030
    protocol: TCP
    targetPort: 15030
  - name: http2-grafana
    nodePort: 31748
    port: 15031
    protocol: TCP
    targetPort: 15031
  selector:
    app: istio-ingressgateway
    istio: ingressgateway
  type: LoadBalancer
  externalIPs:
  - 172.16.0.22
EOF'
#------- cut here ------

# Grafana Dashboard
# http://172.16.0.22:3000/d/1/istio-mesh-dashboard

# Booksample App URL
# http://172.16.0.22/productpage

# 
# http://172.16.0.22:8088/dotviz

# Jeager UI
# http://172.16.0.22:16686/

# Weave Scope
# http://172.16.0.22:4040

