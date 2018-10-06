####################################################################################################################
# Environment:
# CentOS Linux release 7.5.1804 (Core) minimal installation
# 1 master node (4vCpu, 4Gb RAM, 20GB Disk, Nat or Wan or Bridge Network) 
# 1 Worker Node or More (2vCpu, 2Gb RAM, 20GB Disk, Nat or Wan or Bridge Network)
# 
# /etc/hosts file
# 172.16.0.20	worker1.variasimx.com (Kubernetes Node1)
# 172.16.0.21	worker2.variasimx.com (Kubernetes Node1)
# 172.16.0.22	master.variasimx.com (Kubernetes Master, please take not this IP)
#
# To lazy to prepare your environment, you can use: https://www.katacoda.com/courses/istio/deploy-istio-on-kubernetes
####################################################################################################################

# Prepare Operating System, disabling Selinux and Firewalld
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
systemctl disable firewalld

# Enable Kubernetes Repository
bash -c 'cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF'

# Update Centos and Reboot to apply latest kernel, ater reboot install kubernetes and enable docker & kubelet into startup
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

# Disable swap, no need swap on kubernetes
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configuration of the Kubernetes Master 
# 172.16.0.22 my master IP, 192.168.0.0/16 is default istio Network, please use default istio network
# More info related to install istio please go to:
# https://istio.io/docs/setup/kubernetes/quick-start/
# https://istio.io/docs/setup/kubernetes/sidecar-injection

# Initializes a Kubernetes master node
kubeadm init --apiserver-advertise-address=172.16.0.22  --pod-network-cidr=192.168.0.0/16
# Take note on --discovery-token-ca-cert-hash
kubectl cluster-info

# COpy credential to home dir and set permission
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
  
# join Worker node to master
kubeadm join 172.16.0.22:6443 --token ly4swk.uyxl37ovhi0m7ktt --discovery-token-ca-cert-hash <token-hash>
kubectl get nodes

# Check core-dns is up and running
watch -n 2 kubectl get pods --all-namespaces -o wide
  
# Deploy CNI using weave
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
  
# make sure core-dns is up and running
watch -n 2 kubectl get pods --all-namespaces -o wide
kubectl get nodes
  
####################################################################################################################
  
#--|  Install ISTIO
cd /root/
curl -L https://git.io/getLatestIstio | ISTIO_VERSION=1.0.0 sh -
export PATH="$PATH:/root/istio-1.0.0/bin"
cd /root/istio-1.0.0

#-| Configure Istio CRD
# Istio has extended Kubernetes via Custom Resource Definitions (CRD). Deploy the extensions by applying crds.yaml
kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml -n istio-system

#-| Install Istio with default mutual TLS authentication
# To Install Istio and enforce mutual TLS authentication by default, use the yaml istio-demo-auth.yaml:
kubectl apply -f install/kubernetes/istio-demo-auth.yaml
# This will deploy Pilot, Mixer, Ingress-Controller, and Egress-Controller, and the Istio CA (Certificate Authority). 
# These are explained in the next step.

#-| Check Status, All the services are deployed as Pods.
kubectl get pods -n istio-system
kubectl get svc -n istio-system

#-| The previous step deployed the Istio Pilot, Mixer, Ingress-Controller, and Egress-Controller, and the Istio CA 
# (Certificate Authority).
# * Pilot - Responsible for configuring the Envoy and Mixer at runtime.
# * Proxy / Envoy - Sidecar proxies per microservice to handle ingress/egress traffic between services in the cluster and from a service to external services. The proxies form a secure microservice mesh providing a rich set of functions like discovery, rich layer-7 routing, circuit breakers, policy enforcement and telemetry recording/reporting functions.
# * Mixer - Create a portability layer on top of infrastructure backends. Enforce policies such as ACLs, rate limits, quotas, authentication, request tracing and telemetry collection at an infrastructure level.
# * Citadel / Istio CA - Secures service to service communication over TLS. Providing a key management system to automate key and certificate generation, distribution, rotation, and revocation.
# * Ingress/Egress - Configure path based routing for inbound and outbound external traffic.
# * Control Plane API - Underlying Orchestrator such as Kubernetes or Hashicorp Nomad.
# Topologi: https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/istio-arch1.png

####################################################################################################################

#--| Bookinfo Architecture
# The BookInfo sample application deployed is composed of four microservices:
# * The productpage microservice is the homepage, populated using the details and reviews microservices.
# * The details microservice contains the book information.
# * The reviews microservice contains the book reviews. It uses the ratings microservice for the star rating.
# * The ratings microservice contains the book rating for a book review.

#-| The deployment included three versions of the reviews microservice to showcase different behaviour and routing:
# * Version v1 doesn’t call the ratings service.
# * Version v2 calls the ratings service and displays each rating as 1 to 5 black stars.
# * Version v3 calls the ratings service and displays each rating as 1 to 5 red stars.
# * The services communicate over HTTP using DNS for service discovery. An overview of the architecture is shown below.
# Topology: https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/BookInfo-all.png
# The source code for the application is available on Github: https://github.com/istio/istio/tree/release-0.1/samples/apps/bookinfo/src

#-| Deploy Sample Application
# To showcase Istio, a BookInfo web application has been created. This sample deploys a simple application composed 
# of four separate microservices which will be used to demonstrate various features of the Istio service mesh.
# When deploying an application that will be extended via Istio, the Kubernetes YAML definitions are extended via kube-inject. 
# This will configure the services proxy sidecar (Envoy), Mixers, Certificates and Init Containers.
kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
# Deploy Gateway
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl get pods

#-| Apply default destination rules
# Before you can use Istio to control the Bookinfo version routing, you need to define the available versions, called subsets, in destination rules.
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml

#-| Expose bookinfo sample app component
# To make the sample BookInfo application and dashboards available to the outside world, 
# change 172.16.0.22 to your master node IP address 
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
  name: expose-servicegraph
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
  name: expose-grafana
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
  name: expose-jaeger-query
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
  name: expose-prometheus
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

#-| Control Routing
# One of the main features of Istio is its traffic management. As a Microservice architectures scale, 
# there is a requirement for more advanced service-to-service communication control.

#-| User Based Testing / Request Routing
# One aspect of traffic management is controlling traffic routing based on the HTTP request, such as user agent strings, IP address or cookies.
# The example below will send all traffic for the user "jason" to the reviews:v2, meaning they'll only see the black stars.
cat samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml
# Visit the product page http://172.16.0.22/productpage and signin as a user jason (password jason)

#-| Traffic Shaping for Canary Releases
# The ability to split traffic for testing and rolling out changes is important. 
# This allows for A/B variation testing or deploying canary releases.
# The rule below ensures that 50% of the traffic goes to reviews:v1 (no stars), or reviews:v3 (red stars).
cat samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml
# Logout of user Jason otherwise the above configuration will take priority
# Note: The weighting is not round robin, multiple requests may go to the same service.

#-| New Releases
# Given the above approach, if the canary release were successful then we'd want to move 100% of the traffic to reviews:v3.
cat samples/bookinfo/networking/virtual-service-reviews-v3.yaml
#This can be done by updating the route with new weighting and rules.
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v3.yaml

#--| List All Routes
# It's possible to get a list of all the rules applied using 
istioctl get virtualservices 
#and 
istioctl get virtualservices -o yam

####################################################################################################################

#--| Access Metrics
# With Istio's insight into how applications communicate, 
# it can generate profound insights into how applications are working and performance metrics.

#-| Generate Load
# To view the graphs, there first needs to be some traffic. Execute the command below to send requests to the application.
# 172.16.0.22 is your Kubernetes Master node
while true; do
  curl -s http://172.16.0.22/productpage/productpage > /dev/null
  echo -n .;
  sleep 0.2
done
# Check metric on browser 
# http://172.16.0.22:3000/d/1/istio-mesh-dashboard

#--| Access Dashboards
# With the application responding to traffic the graphs will start highlighting what's happening under the covers.

#-| Grafana
# The first is the Istio Grafana Dashboard. The dashboard returns the total number of requests currently being processed, 
# along with the number of errors and the response time of each call.
# Grafana Dashboard
# http://172.16.0.22:3000/d/1/istio-mesh-dashboard
# As Istio is managing the entire service-to-service communicate, the dashboard will highlight the aggregated totals 
# and the breakdown on an individual service level.

#-| Jaeger
# Jaeger provides tracing information for each HTTP request. 
# It shows which calls are made and where the time was spent within each request.
# Jeager UI
# http://172.16.0.22:16686/
# Click on a span to view the details on an individual request and the HTTP calls made. 
# This is an excellent way to identify issues and potential performance bottlenecks.

#-| Service Graph
# As a system grows, it can be hard to visualise the dependencies between services. 
# The Service Graph will draw a dependency tree of how the system connects.
# ServiceGraph
# http://172.16.0.22:8088/dotviz

# Before continuing, stop the traffic (stop generate load) process with ctrl + c
  
####################################################################################################################
 
#--| Visualise Cluster using Weave Scope
# While Service Graph displays a high-level overview of how systems are connected, 
# a tool called Weave Scope provides a powerful visualisation and debugging tool for the entire cluster.
# Using Scope it's possible to see what processes are running within each pod and which pods are communicating with each other. 
# This allows users to understand how Istio and their application is behaving.

#-| Deploy Scope
# Scope is deployed onto a Kubernetes cluster with the command 
kubectl create -f 'https://cloud.weave.works/launch/k8s/weavescope.yaml'
# Wait for it to be deployed by checking the status of the pods using kubectl get pods -n weave
kubectl get pods -n weave

#-| Make Scope Accessible
# Once deployed, expose the service to the public.
pod=$(kubectl get pod -n weave --selector=name=weave-scope-app -o jsonpath={.items..metadata.name})
kubectl expose pod $pod -n weave --external-ip="172.17.0.35" --port=4040 --target-port=4040
# Important: Scope is a powerful tool and should only be exposed to trusted individuals and not the outside public. 
# Ensure correct firewalls and VPNs are configured.
# View Scope on port 4040 at http://172.16.0.22:4040

#-| Generate Load
# Scope works by mapping active system calls to different parts of the application and the underlying infrastructure. Create load to see how various parts of the system now communicate.
while true; do
  curl -s http://172.16.0.22/productpage > /dev/null
  echo -n .;
  sleep 0.2
done

####################################################################################################################

# Grafana Dashboard URL
# http://172.16.0.22:3000/d/1/istio-mesh-dashboard

# Productpage App URL
# http://172.16.0.22/productpage

# ServiceGraph URL
# http://172.16.0.22:8088/dotviz

# Jeager UI URL
# http://172.16.0.22:16686/

# Weave Scope URL
# http://172.16.0.22:4040

####################################################################################################################





# Troubleshooting Network, test ClusterIP instead of NodePort
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
