####################################################################################################################
# Environment:
# CentOS Linux release 7.5.1804 (Core) minimal installation
# 1 Kubernetes master node (4vCpu, 4Gb RAM, 20GB Disk, Nat or Wan or Bridge Network) 
# 1 Kubernetes Worker Node or More (2vCpu, 2Gb RAM, 20GB Disk, Nat or Wan or Bridge Network)
# <master-ip> = 172.16.0.22 (for my demo)
# 
# /etc/hosts file
# 172.16.0.20	worker1.variasimx.com (Kubernetes Node1)
# 172.16.0.21	worker2.variasimx.com (Kubernetes Node1)
# 172.16.0.22	master.variasimx.com (Kubernetes Master, please take not this IP)
#
# To lazy to prepare your environment, you can use: https://www.katacoda.com/courses/istio/deploy-istio-on-kubernetes
####################################################################################################################
# Master and Node
# Prepare Operating System, disabling Selinux and Firewalld 
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
systemctl disable firewalld

# Master and Node
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

# Master and Node
# Update Centos and Reboot to apply latest kernel, ater reboot install kubernetes and enable docker & kubelet into startup
yum repolist; yum -y update; reboot
yum install kubeadm kubelet kubectl docker -y
systemctl enable docker
systemctl enable kubelet

# Master and Node
# Enable BR filter
modprobe br_netfilter
bash -c 'cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF'
sysctl -p
echo 1 >  /proc/sys/net/bridge/bridge-nf-call-iptables
echo 1 >  /proc/sys/net/bridge/bridge-nf-call-ip6tables

# Master and Node
# Disable swap, no need swap on kubernetes
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configuration of the Kubernetes Master 
# <master-ip> my master IP, 192.168.0.0/16 is default istio Network, please use default istio network
# More info related to install istio please go to:
# https://istio.io/docs/setup/kubernetes/quick-start/
# https://istio.io/docs/setup/kubernetes/sidecar-injection

# Initializes a Kubernetes master node
kubeadm init --apiserver-advertise-address=<master-ip>  --pod-network-cidr=192.168.0.0/16
# Take note on --discovery-token-ca-cert-hash
# example:
# kubeadm join 172.16.0.22:6443 --token k4l46z.o07cabxrgjk10pp3 --discovery-token-ca-cert-hash sha256:c4b8100526838ec6da0e12e4dd7336124a852ca719f532e7fb3bdff9c77dfff4

# COpy credential to home dir and set permission in master
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

kubectl cluster-info
  
# join Worker node to master
kubeadm join <master-ip>:6443 --token ly4swk.uyxl37ovhi0m7ktt --discovery-token-ca-cert-hash <token-hash>
kubectl get nodes

# Check core-dns is up and running in master
watch -n 2 kubectl get pods --all-namespaces -o wide
# core-dns pod should be in status: ContainerCreating, from the node /var/log/messages we will found:
# cni.go:188] Unable to update cni config: No networks found in /etc/cni/net.d
  
# Deploy CNI using weave in master
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
  
# make sure core-dns is up and running
watch -n 2 kubectl get pods --all-namespaces -o wide
kubectl get nodes
# Now core-dns was running and Node in Status: Ready

# Start your lab
git clone https://github.com/isnuryusuf/kubernetes-istio-cicd
  
####################################################################################################################
# Get Started with Istio and Kubernetes
# In this scenario, you will learn how to deploy Istio Service Mesh to Kubernetes. 
# Istio is an open platform that provides a uniform way to connect, manage, and secure microservices. 
# Istio supports managing traffic flows between microservices, enforcing access policies, and aggregating telemetry-
# data, all without requiring changes to the microservice code

# The scenario uses the sample BookInfo application. The application has no dependencies on Istio and demonstrates-
# how any application could build upon Istio without modifications.
####################################################################################################################

#--|  Install Istio
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

#-| Check Status, All the services are deployed as Pods and Running without Error.
kubectl get pods -n istio-system
kubectl get svc -n istio-system
# If your network doesnt support LoadBalancer mode, the istio-ingressgateway EXTERNAL-IP will show <pending> state

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
# make sure all POD on namespace default was running: 
# (details-v1, productpage-v1, ratings-v1, reviews-v1, reviews-v2, reviews-v3)

#-| Apply default destination rules
# Before you can use Istio to control the Bookinfo version routing, 
# you need to define the available versions, called subsets, in destination rules.
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml

#-| Expose bookinfo sample app component
# To make the sample BookInfo application and dashboards available to the outside world, 
wget https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/expose.yaml -O /root/kubernetes-istio-cicd/expose.yaml
# change <master-ip> to your master node IP address 
kubectl apply -f /root/kubernetes-istio-cicd/expose.yaml

####################################################################################################################

#-| Control Routing
# One of the main features of Istio is its traffic management. As a Microservice architectures scale, -
# there is a requirement for more advanced service-to-service communication control.

#-| User Based Testing / Request Routing (login as user jason
# One aspect of traffic management is controlling traffic routing based on the HTTP request, such as user agent strings, -
# IP address or cookies.
# The example below will send all traffic for the user "jason" to the reviews:v2, meaning they'll only see the black stars.
# Form Data: "username=jason&passwd=jason"
cat samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml
# Visit the product page http://<master-ip>/productpage and signin as a user jason (password jason)

####################################################################################################################

#-| Traffic Shaping for Canary Releases
# The ability to split traffic for testing and rolling out changes is important. 
# This allows for A/B variation testing or deploying canary releases.
# The rule below ensures that 50% of the traffic goes to reviews:v1 (no stars), or reviews:v3 (red stars).
cat samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml
# Logout of user Jason otherwise the above configuration will take priority
# Note: The weighting is not round robin, multiple requests may go to the same service.
# Open http://<master-ip>/productpage and refresh periodicly (press f5 to refresh on browser)

####################################################################################################################

#-| New Releases
# Given the above approach, if the canary release were successful then we'd want to move 100% of the traffic to reviews:v3.
cat samples/bookinfo/networking/virtual-service-reviews-v3.yaml
#This can be done by updating the route with new weighting and rules.
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v3.yaml
# Open http://<master-ip>/productpage and refresh periodicly (press f5 to refresh on browser)

#--| List All Routes
# It's possible to get a list of all the rules applied using 
istioctl get virtualservices 
#and 
istioctl get virtualservices -o yaml

####################################################################################################################

#--| Access Metrics
# With Istio's insight into how applications communicate, 
# it can generate profound insights into how applications are working and performance metrics.

#-| Generate Load
# To view the graphs, there first needs to be some traffic. Execute the command below to send requests to the application.
# <master-ip> is your Kubernetes Master node
while true; do
  curl -s http://<master-ip>/productpage/productpage > /dev/null
  echo -n .;
  sleep 0.2
done
# Check metric on browser 
# http://<master-ip>:3000/d/1/istio-mesh-dashboard

#--| Access Dashboards
# With the application responding to traffic the graphs will start highlighting what's happening under the covers.

#-| Grafana
# The first is the Istio Grafana Dashboard. The dashboard returns the total number of requests currently being processed, 
# along with the number of errors and the response time of each call.

# Grafana Dashboard
# http://<master-ip>:3000/d/1/istio-mesh-dashboard
# As Istio is managing the entire service-to-service communicate, the dashboard will highlight the aggregated totals 
# and the breakdown on an individual service level.

####################################################################################################################

#-| Jaeger
# Jaeger provides tracing information for each HTTP request. 
# It shows which calls are made and where the time was spent within each request.

# Jeager UI
# http://<master-ip>:16686/
# Click on a span to view the details on an individual request and the HTTP calls made. 
# This is an excellent way to identify issues and potential performance bottlenecks.

#-| Service Graph
# As a system grows, it can be hard to visualise the dependencies between services. 
# The Service Graph will draw a dependency tree of how the system connects.
# ServiceGraph
# http://<master-ip>:8088/dotviz

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
echo $pod
kubectl expose pod $pod -n weave --external-ip="<master-ip>" --port=4040 --target-port=4040
# Important: Scope is a powerful tool and should only be exposed to trusted individuals and not the outside public. 
# Ensure correct firewalls and VPNs are configured.
# View Scope on port 4040 at http://<master-ip>:4040

#-| Generate Load
# Scope works by mapping active system calls to different parts of the application and the underlying infrastructure. 
# Create load to see how various parts of the system now communicate.
while true; do
  curl -s http://<master-ip>/productpage > /dev/null
  echo -n .;
  sleep 0.2
done

####################################################################################################################

# Grafana Dashboard URL
# http://<master-ip>:3000/d/1/istio-mesh-dashboard

# Productpage App URL
# http://<master-ip>/productpage

# ServiceGraph URL
# http://<master-ip>:8088/dotviz

# Jeager UI URL
# http://<master-ip>:16686/

# Weave Scope URL
# http://<master-ip>:4040


####################################################################################################################
# Traffic Shaping Microservices Connections
# In this scenario you will learn how to use Istio to control and manage traffic within your infrastructure.
# You will learn how to use the following Istio objects:
# * Ingress and Gateway
# * Virtual Service
# * Destination Rule
# * Egress and Service Entry

####################################################################################################################

#--| Traffic Shaping Microservices Connections
# remove bookinfo from previous installation
kubectl delete -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl get pods

cd /root/istio-1.0.0
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v1.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-v1.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v2.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-v2.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-chrome-v2.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-chrome-v2.yaml

cat <<EOF > /root/istio-1.0.0/serviceEntry.yaml
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

#-| Deploy Bookinfo
# Istio is already running on the Kubernetes cluster. Deploy the sample Bookinfo application before continuing.
kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl get pods

#--| Step 3 - Ingress
# To make the application available to the outside world a Gateway needs to be deployed. 
# Within Kubernetes this is managed with Ingress that specifies services that should be exposed outside the cluster.
# Within Istio, the Istio Ingress Gateway defines this via configuration.
# A Gateway allows Istio features such as monitoring and route rules to be applied to traffic entering the cluster.
kubectl get svc --all-namespaces | grep istio-ingressgateway

# An example of extending the gateway is this:
: <<'END_COMMENT'
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
END_COMMENT

# Because we are using a wildcard (*) character for the host and only one route rule, all traffic from this gateway 
# to the frontend service (as defined in the VirtualService)

cat samples/bookinfo/networking/bookinfo-gateway.yaml
# This file contains two objects. The first object is a Gateway, which will allow us to bind to the "istio-ingressgateway" 
# that exists in the cluster. The second object, a VirtualService, will be discussed in the next step.
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
# To view all gateways on the system, run 
kubectl get gateway

#-| Step 4 - Virtual Services
# A VirtualService defines a set of traffic routing rules to apply when a host is addressed. 
# for detail https://istio.io/docs/reference/config/istio.networking.v1alpha3/#VirtualService
: <<'END_COMMENT'
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
END_COMMENT

# In the above example, we are sending all traffic for the Rating service to v1.
# The VirtualService traffic will be then be processed by the DestinationRule which will load balance based on LEAST_CONN.
# For our BookInfo application, because we are using a wildcard (*) character for the host and only one route rule, 
# all traffic from this gateway to the frontend service. This is defined by the combination of our Gateway and Virtual Services.
cat samples/bookinfo/networking/bookinfo-gateway.yaml
# When you visit the application, the traffic will be initially processed by our Gateway, 
# with rules defined by the Virtual Services to explain which Kubernetes Pod should process the request.
# The application can be accessed at http://<IP-Kubenetes-Master>/productpage

#-| Step 5 - Destination Rules
# While a VirtualService configures traffic flows, a DestinationRule defines policies that apply to traffic intended 
# for a service after routing has occurred.
# The following rule defines that the load balancer should be using LEAST_CONN, 
# meaing route the pod with the least active connnections.

: <<'END_COMMENT'
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: bookinfo-ratings
spec:
  host: ratings.prod.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      simple: LEAST_CONN
END_COMMENT
# The following rule indicates traffic should be load balanced across-
# three different versions based on the Pod labels, v1, v2 and v3.

: <<'END_COMMENT'
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
END_COMMENT
      
# Within this rule, it also defines that the connections should be over TLS.
: <<'END_COMMENT'
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
END_COMMENT
      
# Without the DestinationRule, Istio cannot route the internal traffic.

#-| Apply default destination rules
# Before you can use Istio to control the Bookinfo version routing, you need to-
# define the available versions, called subsets, in destination rules.
cat samples/bookinfo/networking/destination-rule-all-mtls.yaml
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
kubectl get destinationrules

# Now when you visit the Product Page the reviews will appear. As three versions have been defined within our Destination Rule
# By default, it will load balance across all available review services.

#--| Step 6 - Deploying Virtual Services / Deploy V1
# For the Bookinfo application, we have three different versions of a Reviews service available.-
# The reviews service provides a short review, together with a star rating in the newer versions.
# By default, Istio and Kubernetes will load balance the requests across all the available services.-
# We can use a Virtual Service to control our traffic and force it to only be processed by V1.
cat samples/bookinfo/networking/virtual-service-all-v1.yaml
# The file defines the Virtual Services for all the application. For every application,-
# a host is defined (such as productpage), which is a DNS entry of how other applications will communicate with the service. 
# Based on requests to this host, the route defines the destination and which Pods should handle the request.
# This is deployed via 
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
# When you visit the Product Page you will only see the reviews coming from our V1 service.

# List All Routes
# It's possible to get a list of all the rules applied using 
kubectl get virtualservices
# and 
kubectl get virtualservices reviews -o yaml

#--| Step 7 - Updating Virtual Services
# As with all Kubernetes objects, Virtual Services can be updated which will change how our traffic is processed within the system.
# This Virtual Service sends all traffic to the V2 rating service, meaning our application would return the star rating
cat samples/bookinfo/networking/virtual-service-reviews-v2.yaml
# This is deployed via 
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v2.yaml
# When you visit the Product Page (http://<master-ip>/productpage) you will now see the results from V2.
# These Virtual Services become the heart of controlling and shaping the traffic within our system.

#-| Step 8 - Egress
# While the Bookinfo application doesn't need to call external applications, certain applications do.
# Istio is security focused, meaning applications cannot access external services by default. Instead,-
# the egress (outbound) traffic needs to be configured.
# Deploy a simple Sleep pod which will attempt to access an external service.
kubectl apply -f <(istioctl kube-inject -f samples/sleep/sleep.yaml)

# Once started, attach to the container:
export SOURCE_POD=$(kubectl get pod -l app=sleep -o jsonpath={.items..metadata.name})
echo $SOURCE_POD
kubectl exec -it $SOURCE_POD -c sleep bash
# When you attempt to access an external service, it will return a 404.
curl http://httpbin.org/headers -i

: <<'END_COMMENT'
HTTP/1.1 404 Not Found
date: Wed, 10 Oct 2018 08:04:27 GMT
server: envoy
content-length: 0
END_COMMENT
# Exit from docker shell

# We need to configure our Egress. Exit the container as we need to deploy additional components.
# Egress is configured via a ServiceEntry. The ServiceEntry defines how the external can be reached.
cat /root/istio-1.0.0/serviceEntry.yaml
kubectl apply -f /root/istio-1.0.0/serviceEntry.yaml
# Repeat the process of attaching to the container:
kubectl exec -it $SOURCE_POD -c sleep bash
# When you attempt to access an external service, it will now return the expected response.
curl http://httpbin.org/headers -i
# Within the response, you can also identify all the additional metadata Istio includes to help build metrics,-
# traceability and insights into the inner-workings of the network. 
# These will be explored within the Observing Microservices with Istio course.
# More information at https://istio.io/docs/tasks/traffic-management/egress/#configuring-the-external-services


####################################################################################################################
# Deploying Canary Releases
# In this scenario, you will learn how to take apply Traffic Shaping techniques discussed in the previous scenario. 
# By apply Traffic Management, you will be able to control who can access versions of your application making it-
# possible to perform canary releases with Istio and Kubernetes.

# "Canary release is a technique to reduce the risk of introducing a new software version in production by slowly-
# rolling out the change to a small subset of users before rolling it out to the entire infrastructure and making-
# it available to everybody." Martin Flower
####################################################################################################################

#--| Step 1 - Remove bookinfo from previous installation
# kubectl delete -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
# kubectl get pods

#--| Step 2 - Deploy V1
# The default deployment will load balance requests for the reviews across the different versions meaning on each request you may get a different result.
# As described in our traffic shaping scenario, Virtual Services are used to control the traffic flow within the system. 
# Deploy the Virtual Services to force all traffic to V1 of our system.
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
# When you visit the Product Page you will only see the reviews coming from our V1 service.
# The next steps will rollout V2 of our rating service as a canary release.

#--| Step 3 - Access V2 Internally
# The key to successful canary releases is being able to deploy components of the system into production,-
# test everything is successful for a small sample before rolling out to a larger user base. If everything is happy,-
# it can be deployed to 100% of the user-base.

# Virtual Services provide Layer 7 load balancing and traffic routing. Layer 7 means it's possible to route traffic based-
# on aspects of HTTP request, such as host headers, user agents or cookies.

# By having Layer 7 routing, we can provide a specific section of our users with a different response to the request of our user base.
# For example, if a user as a particular cookie, they could be sent to the V2 version. Using this routing is ideal for 
# allowing internal employees access before it goes live.
# The following Virtual Service implements this pattern. If the user is logged in as jason then they will be direct to V2. 
# As this VirtualService comes all the flow for the reviews host, at the end we indicate that everyone else who didn't match will go to the V1.
cat samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-test-v2.yaml

# When listing services you should only see the current version available.
kubectl get virtualservice
kubectl describe virtualservice reviews
# Access to http://<master-ip>/productpage/productpage
# When you visit the Product Page you will only see the reviews coming from our V1 service. 
# If you log in at jason you will start to see the V2 service.


#--| Step 4 - 10% Public Traffic to V2
# Hopefully V2 is working successfully for Jason meaning it can be rolled out to production.
# Instead of sending 100% of traffic to V2, we want to slowly roll out the service. 
# To start with, only 10% of traffic should go to V2.
# With Virtual Services, this can be done by defining two route destinations. 
# Each of these destinations can have the desired weight.
cat samples/bookinfo/networking/virtual-service-reviews-90-10.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-90-10.yaml
# When you visit the Product Page you will see mainly V1 responses, but every 1/10 should be V2. 
# The order isn't 100% even, but given a large enough distribution of traffic, the ratios will even out.

#--| Step 5 - 20%
# As confidence grows in v2, changing the Virtual Service weights will start sending more traffic to the latest version.
cat samples/bookinfo/networking/virtual-service-reviews-80-20.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-80-20.yaml
# Within the Katacoda Observing Microservices with Istio course, we explain how to use the Istio Dashboards, 
# Metrics and Tracing to identify when systems are working and the traffic distribution. 
# These would be critical in understanding how our systems are operating and if the next version is working as expected.

# If you are interested in seeing the data you can view the Grafana dashboards here.
# http://<master-ip>:3000/d/LJ_uJAvmk/istio-service-dashboard?refresh=10s&orgId=1&var-service=reviews.default.svc.cluster.local&var-srcns=All&var-srcwl=All&var-dstns=All&var-dstwl=All

# Each service has it's own version available, allowing you to inspect Reviews Service v1 or Reviews Service v2
# http://<master-ip>:3000/d/UbsSZTDik/istio-workload-dashboard?refresh=10s&orgId=1&var-namespace=default&var-workload=reviews-v1&var-srcns=All&var-srcwl=All&var-dstsvc=All
# http://<master-ip>:3000/d/UbsSZTDik/istio-workload-dashboard?refresh=10s&orgId=1&var-namespace=default&var-workload=reviews-v2&var-srcns=All&var-srcwl=All&var-dstsvc=All
# http://<master-ip>:3000/d/1/istio-workload-dashboard

#--| Step 6 - Auto Scale
# During this canary deployment, our system is shifting load from our previous version to the desired version.-
# As a result, the older version is receiving less traffic while our new version is increasing.
# Running both v1 and v2 at full capacity might not be possible given system resources available. Ideally,-
# we'd like Kubernetes to scale up/down our Pods as the traffic changes.

#This is possible with Kubernetes by using the Horizontal Pod Autoscaler.-
# Based on CPU usage of the pods we can change the number of Pods running automatically.
# The auto scale is defined based on the deployments running. This can be found with 
# The auto scale is defined based on the deployments running. This can be found with kubectl get deployment
# The deployments show that both v1 and v2 are running. We can tell Kubernetes to autoscale these components with the following commands:
kubectl autoscale deployment reviews-v1 --cpu-percent=50 --min=1 --max=10
kubectl autoscale deployment reviews-v2 --cpu-percent=50 --min=1 --max=10
# If the Pod CPU exceeds 50% then an additional Pod will be started, up to a maximum of 10.
# View all auto-scaling definitions with 
kubectl get hpa
# Hit http://<master-ip>/productpage with your favorite Stress test tools

#--| Step 7 - Configure All Traffic to V2
# Once happy the Virtual Service can be updated to direct all the traffic to the v2 version.
cat samples/bookinfo/networking/virtual-service-reviews-v2.yaml
# This is deployed with the command:
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v2.yaml
# When you visit the Product Page you will see mainly V1 responses, but every 1/10 should be V2. The order isn't 100% even,-
# but given a large enough distribution of traffic, the ratios will even out.

# The Grafana dashboards should also indicate that all traffic is going to Reviews Service v2.
# http://<master-ip>:3000/d/LJ_uJAvmk/istio-service-dashboard?refresh=10s&orgId=1&var-service=reviews.default.svc.cluster.local&var-srcns=All&var-srcwl=All&var-dstns=All&var-dstwl=All
# http://<master-ip>:3000/d/UbsSZTDik/istio-workload-dashboard?refresh=10s&orgId=1&var-namespace=default&var-workload=reviews-v2&var-srcns=All&var-srcwl=All&var-dstsvc=All


####################################################################################################################
# Simulating Failures Between Microservices  
# Distributed systems are difficult to test. It can be time-consuming to reproduce the errors and situations when 
# it's deep within the system. Based on the traffic management capabilities, it's possible for Istio to inject faults -
# and simulate application errors or timeouts.
# In this scenario, you will learn how to cause delays or failures for certain sections of the traffic to allow you to -
# test how the rest of the system handles problems.
# Based on https://istio.io/docs/tasks/traffic-management/fault-injection/
####################################################################################################################

#--| Step 1 - Remove bookinfo from previous installation
# kubectl delete -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
# kubectl get pods

#-| Deploy Bookinfo
# Istio is already running on the Kubernetes cluster. Deploy the sample Bookinfo application before continuing.
# kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
# kubectl get pods

#--| Step 2 - Injecting an HTTP delay fault
# Istio can simulate failures and injects faults into the traffic routing of the system. 
# This allows developers and operations to simulate or reproduce failures within the system.
# As Istio has Layer 7 traffic shaping capabilities, as discussed thin the Connecting and Controlling Microservices 
# with Istio course, it allows HTTP requests to be filtered based on users or team members without affecting other users.
# In this case, a 7s delay is forced the user jason. Deploy the service with 
cat samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml

# You can verify what the current virtual services deployed are with 
kubectl get virtualservice ratings -o yaml
# As a normal user, when you visit the Product Page of the Bookinfo application, everything should load as expected. However, 
# if you sign in as jason then you will experience the delay.
# This allows you to safely test how systems behaviour within a safe boundary.

#--| Step 3 - Injecting an HTTP abort fault
# As with timeouts, HTTP errors can also be injected with different HTTP response codes. 
# This is a great way to verify that applications will handle various errors that might happen in production.
cat samples/bookinfo/networking/virtual-service-ratings-test-abort.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-ratings-test-abort.yaml
# As a normal user, when you visit the Product Page of the Bookinfo application, everything should load as expected. 
# However, if you sign in as jason then you will experience errors from the rating service.


####################################################################################################################
# Handling Timeouts Between Microservices
# In this scenario, you will learn how Istio can help you gracefully handle timeouts. 
# Systems can cause timeouts for a number of reasons, sometimes this can cause 30-60 second delays in responses. 
# As a result, the workload is queued and has knock-on effects for the rest of the application.
# By implementing a timeout, services will always return within a known time, either as a success or an error.
# Based on https://istio.io/docs/tasks/traffic-management/request-timeouts/
####################################################################################################################
#--| Step 1 - Remove bookinfo from previous installation
# kubectl delete -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
# kubectl get pods

#-| Deploy Bookinfo
# Istio is already running on the Kubernetes cluster. Deploy the sample Bookinfo application before continuing.
# kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
# kubectl get pods

#--| Step 2 - Bookinfo Reviews v2
# At the moment, requests are going to different versions of the Reviews version. 
# Deploy a Virtual Service to force requests to only v2 meaning it will call our Rating service.

bash -c 'cat <<EOF > /root/istio-1.0.0/reviewsV2.yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: reviews
spec:
  hosts:
    - reviews
  http:
  - route:
    - destination:
        host: reviews
        subset: v2
EOF'

kubectl apply -f /root/istio-1.0.0/reviewsV2.yaml
# In the next step, we'll introduce a delay without the Rating service and see how the system responds.

#--| Step 3 - Add Rating Delay
# With Reviews calling the Rating service, we can now introduce a delay. 
# This will showcase the rating service potentially being under large load, or an internal component having problems.
# With the delay in place, it's possible to understand how the Reviews service and the platform handles these errors.
# The Virtual Service below introduces a 5-second delay for all users.

bash -c 'cat <<EOF > /root/istio-1.0.0/ratingDelay.yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: ratings
spec:
  hosts:
  - ratings
  http:
  - fault:
      delay:
        percent: 100
        fixedDelay: 5s
    route:
    - destination:
        host: ratings
        subset: v1
EOF'

kubectl apply -f /root/istio-1.0.0/ratingDelay.yaml
# When you visit the product page (http://<master-ip>/productpage), you should notice that the page loads significantly slower.-
# This is because the service is blocking the entire page being loaded.

#--| Step 4 - Configure Timeout
# Instead of the page blocking, the application should fail gracefully and display a message to the user.
# We can update the Virtual Service for the Reviews service that automatically timeouts after 0.5s.

bash -c 'cat <<EOF > /root/istio-1.0.0/virtualServiceReviews.yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: ratings
spec:
  hosts:
  - ratings
  http:
  - fault:
      delay:
        percent: 100
        fixedDelay: 5s
    route:
    - destination:
        host: ratings
        subset: v1
EOF'

kubectl apply -f /root/istio-1.0.0/virtualServiceReviews.yaml
# As long as the upstream application can handle timeouts/failures, this improves the developer experience. 
# Requests to the different components can timeout, unblocking the overall request and delivering a response to the user.
# when visiting the product page, it should return after 0.5s with a friendly error message about the ratings.

#--| Step 5 - Visit Jaeger Dashboard
# As discussed in the Observing Microservices with Istio course, Istio has traceability built-in. 
# The traceability can help identify the requests to the system, the dependent services and the system calls made.
# With the timeout in place, it's possible to identify the system calls producing an error.
# Visit the Jaeger dashboard at http://<master-ip>:16686/


####################################################################################################################
# Handling Failures With Circuit Breakers
# In this scenario, you will learn how to use Circuit Breakers within Envoy Proxy to cause applications- 
# to fail quick based on certain metrics within the system, such as active HTTP connections.

# Circuit breaking is a critical component of distributed systems. 
# It’s nearly always better to fail quickly and apply back pressure downstream as soon as possible." Envoy Proxy

# Based on https://istio.io/docs/tasks/traffic-management/circuit-breaking/
####################################################################################################################

export PATH="$PATH:/root/istio-1.0.0/bin";
cd /root/istio-1.0.0
kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml -n istio-system
kubectl apply -f install/kubernetes/istio-demo-auth.yaml
kubectl apply -f /root/kubernetes-istio-cicd/expose.yaml
kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
kubectl delete -f samples/bookinfo/networking/virtual-service-all-v1.yaml

curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v1.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-v1.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v2.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-v2.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-chrome-v2.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-chrome-v2.yaml

bash -c 'cat <<EOF > /root/istio-1.0.0/httpbinRule.yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: httpbin
spec:
  host: httpbin
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1
      http:
        http1MaxPendingRequests: 1
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutiveErrors: 1
      interval: 1s
      baseEjectionTime: 3m
      maxEjectionPercent: 100
    tls:
      mode: ISTIO_MUTUAL
EOF'

#--| Step 1 - Deploy HTTPBin Client
# A Circuit Breaker is a design pattern that allows systems to define limits and restrictions that protect them from -
# being overloaded. If errors start to happen or too much load for the system to handle is created, the Circuit Breaker -
# is tripped and requests fail in a known, consistent approach. This allows the calling application to handle the errors gracefully.
# Without a Circuit Breaker in place, unknown system errors or inconsistencies may appear causing additional problems and unexpected results.

# Within the Istio architecture, Envoy Proxy is used to manage traffic between services. As a result,- 
# all the functionality available within Envoy is exposed via Istio, such as Envoy's Circuit Breaker. The types include:
# * Cluster maximum connections: The maximum number of connections that Envoy will establish to all hosts in an upstream cluster.
# * Cluster maximum pending requests: The maximum number of requests that will be queued while waiting for a ready connection pool connection.
# * Cluster maximum requests: The maximum number of requests that can be outstanding to all hosts in a cluster at any given time.
# * Cluster maximum active retries: The maximum number of retries that can be outstanding to all hosts in a cluster at any given time.

# In this example, we'll deploy an HTTPBin service. The service echoes the HTTP request as a response,-
# allowing us to identify responses and errors easily.
# Deploy the application with 
kubectl apply -f <(istioctl kube-inject -f samples/httpbin/httpbin.yaml)

#--| Step 2 - Configure Circuit Breaker
# To access the HTTPBin service, a client is required. The sleep sample application doesn't execute any workload, instead,- 
# it allows users to attach and execute bash commands interactively. The container will allow us to test and debug our system.

# Deploy a sleep container with 
kubectl apply -f <(istioctl kube-inject -f samples/sleep/sleep.yaml)
# This gives us access to the Istio deployed applications and internal control plane.

# Attach a Bash prompt to the container with 
kubectl exec -it $(kubectl get pod -l app=sleep -o jsonpath={.items..metadata.name}) bash
# It's now possible to send cURL commands to other components running within our system.
curl http://httpbin:8000/get;
# The response should be a 200 OK message indicating everything is working as expected. Exit the container to continue.

#--| Step 3 - View Request
# Within Istio, the traffic and networking approaches can be updated and modified based on requirements.
# As discussed in the Connecting and Controlling Istio scenarios, Virtual Services direct the traffic flow 
# to which version of the component(s) should handle the request. Destination Rules configure the network and load balancing 
# of the traffic. With a Destination Rule it's possible to implement a Circuit Breaker to-
# restrict the number of concurrent requests to a service.

# The Destination Rule below has two Circuit Breakers that can trigger. 
# The first is a Connection Pool that limits the maximum TCP connections to 1, and a maximum of 1 HTTP request per connection.

# The second is an Outlier Detection that automatically removes failing nodes if-
# they have consecutively returned 500 error messages for more than a period of time.
cat /root/istio-1.0.0/httpbinRule.yaml
kubectl apply -f /root/istio-1.0.0/httpbinRule.yaml

# After this has been deployed, you should find the application still functions as before.
kubectl exec -it $(kubectl get pod -l app=sleep -o jsonpath={.items..metadata.name}) bash
curl http://httpbin:8000/get;
# Exit the container to continue. In the next step, we'll increase the load and watch-
# how Istio and Envoy Proxy trips the circuit breaker

#--| Step 4 - Tripping Circuit Breaker
# With the circuit breaker in place, we should be able to trigger errors via a load test.
# Fortio Φορτίο is a load testing tool created for Istio. Fortio runs at a specified query per second (qps) 
# and records an histogram of execution time and calculates percentiles (e.g. p99 ie the response time such as 99% 
# of the requests take less than that number (in seconds, SI unit)). It can run for a set duration, for a fixed number of calls, 
# or until interrupted (at a constant target QPS, or max speed/load per connection/thread).

# Start Fortio with 
kubectl apply -f <(istioctl kube-inject -f samples/httpbin/sample-client/fortio-deploy.yaml); FORTIO_POD=$(kubectl get pod | grep fortio | awk '{ print $1 }');
# The first command generates two concurrent connections (-c 2) and sends 20 requests (-n 20). 

# You should start to see some requests being returned as 503, meaning the Circuit Breaker has tripped.
kubectl exec -it $FORTIO_POD  -c fortio /usr/local/bin/fortio -- load -c 2 -qps 0 -n 20 -loglevel Warning http://httpbin:8000/get

# If you increase the concurrent connections, the number of errors will also increase.
kubectl exec -it $FORTIO_POD  -c fortio /usr/local/bin/fortio -- load -c 3 -qps 0 -n 20 -loglevel Warning http://httpbin:8000/get

# Remember, the circuit breaker is defined to protect the underlying system and fail gracefully.
# As Envoy implements the Circuit Breaker, the Envoy Proxy is collecting its statistics. 
# These can be queried via Prometheus/Grafana Dashboards, or via CURL requests.

# For example, the following will highlight the stats for the HTTPBin service.
kubectl exec -it $FORTIO_POD  -c istio-proxy  -- sh -c 'curl localhost:15000/stats' | grep httpbin | grep pending

# You can see a upstream_rq_pending_overflow value indicating the number of calls so far that have been flagged for circuit breaking.
# The metric upstream_rq_pending_overflow is from Envoy, more details can be found in at documentation at 
# https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/circuit_breaking
# More insight into the Circuit Breaker pattern is discussed at 
# http://blog.christianposta.com/microservices/01-microservices-patterns-with-envoy-proxy-part-i-circuit-breaking/


####################################################################################################################
# Identifying Slow Services with Distributed Tracing       
# In this scenario you will learn how to use OpenTracing, Jaeger and Istio to identify slow Microservices.
####################################################################################################################

#--| Preparation
#--| Step 1 - Remove bookinfo from previous installation
kubectl delete -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl get pods

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
kubectl apply -f /root/kubernetes-istio-cicd/expose.yaml
kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml

curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v1.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-v1.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v2.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-v2.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-chrome-v2.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-chrome-v2.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-ratings-test-fail.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-ratings-test-fail.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-ratings-test-fail-50.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-ratings-test-fail-50.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-ratings-test-delay-everyone.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-ratings-test-delay-everyone.yaml

kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v2.yaml

#--| Step 2 - View Tracing
# When you visit the Product Page you will only see the reviews coming from our the different deployed services.
# http://<master-ip>:16686/
# Select Service productpage. This selects all the traces that have interacted with the service.
# Click Find Traces at the bottom.
# You will now see traces for each request that has been made to the service.
# Each trace will allow you to identify potentially slow requests or errors that have occurred within the system.
# If you click on one of the traces, you will be shown the spans for the request.
# A span is a request to a service, allowing you to see the requests made and how long the process took. 
# Within each span, you can identify aspects of the request, such as User-Agent string, the IP which processed the request etc. 
# This can help to identify potentially problematic servers or pods.
# The list of traces can be filtered based on the duration or specific tags. By using tags, services which are called can -
# add additional metadata making it easy to identify specific users, functionality, or errors that have occurred.

#--| Step 3 - Simulate Slowdown
# As discussed in the Increasing Reliability with Istio course, 
# Istio can be used to simulate errors and problems within the system to verify how it behaves.
# Use this fault injection functionality inject a delay for all users of the site, 60% of the time.
# As you'd expect, this is not recommended to run in production, instead always limit it to a particular user.

# Apply the configuration with 
kubectl apply -f samples/bookinfo/networking/virtual-service-ratings-test-delay-everyone.yaml
# Now when you visit the product page, you should have a delay before the page is returned.

#--| Step 4 - Identify Slowdown
# Using Jaeger, identify the slow calls using the traces. As only 60% of the traffic is affected, 
# you should see two distinct patterns.

# What happens after 7s?
# o The rating returns a response
# o The user is annoyed at the slow response time
# o A poor user experience is created

#--| Step 5 - Simulate Failure
# As with adding delays, application failures can be introduced by deploying the following Virtual Service.
kubectl apply -f samples/bookinfo/networking/virtual-service-ratings-test-fail-50.yaml

# The service will return a 500 HTTP error for 50% of the requests. 
kubectl get virtualservice ratings -o yaml

# Going to the product page should return instantly, but sometimes have the error "Rating service is currently unavailable"
# Now, Jaeger will show the requests which have failed, the other and the calls attached. This can aid your debugging process.



####################################################################################################################
# Graphing System Metrics with Prometheus and Grafana
# In this scenario, you will learn how to use Istio to create graphs showing live real-time system metrics and connections.
# Istio has many built-in dashboards that show how the system is performing. The scenario will discuss what's -
# available and what to look for within each scenario.
####################################################################################################################

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
kubectl apply -f /root/kubernetes-istio-cicd/expose.yaml
kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-all-v1.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v2.yaml

curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v1.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-v1.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-v2.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-v2.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-reviews-chrome-v2.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-reviews-chrome-v2.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-ratings-test-fail.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-ratings-test-fail.yaml
curl -s -L -o samples/bookinfo/networking/virtual-service-ratings-test-fail-50.yaml https://raw.githubusercontent.com/isnuryusuf/kubernetes-istio-cicd/master/virtual-service-ratings-test-fail-50.yaml

#-| Step 2 - Generate Load
#With Istio's insight into how applications communicate, it can generate profound insights into how 
# applications are working and performance metrics.
# Istio automatically collects metrics about the data connections, latency and error count that helps identify how the
# system is performing and increases in error rates.
# Generate Load
# To view the graphs, there first needs to be some traffic. Execute the command below to send requests to the application.
while true; do
  curl -s http://<master-ip>/productpage > /dev/null
  echo -n .;
  sleep 0.2
done
# The various Istio dashboards will highlight key information about the system to help gain insights 
# into the inter-working of the applications.

#-| Step 3 - Mesh Dashboard
# The Istio Mesh Dashboard provides a top-level overview of the workloads running and how they are performing.
# The dashboard highlights:
#* Service / Workload
#* Requests
#* P50 Latency / P90 Latency / P99 Latency
#* Success Rate

# View the dashboard at http://<master-ip>:3000/dashboard/db/istio-mesh-dashboard
# The different dashboards can be selected via the dropdown in the top left corner.

#-| Step 4 - Service Dashboard
# The Istio Service Dashboard showcases the upstream (client) and services metrics.
# http://<master-ip>:3000/dashboard/db/istio-service-dashboard
# Changing dropdowns to view details of each component within the system. At the top, 
# different options are available to drill into different services and deployments.

#-| Step 5 - Workload Dashboard
# The Istio Workload Dashboard will show individual deployments running within Istio.
# http://<master-ip>:3000/dashboard/db/istio-workload-dashboard

#-| Step 6 - Generate Failure
# Using the Fault Injection functionality within Istio, it's possible to cause failures. 
# This should be visible from the dashboards.
# The following Virtual Service will cause the rating service to fail 50% of the time.
kubectl apply -f samples/bookinfo/networking/virtual-service-ratings-test-fail-50.yaml
# Check it's deployed with the command 
kubectl get virtualservice ratings -o yaml

# When visiting the Product Page you should see the Rating service will now be failing 50% of the time.
# With the Istio Service Dashboard you can identify this failure and when it's occurring.
# If you delete the deployment entirely
# kubectl delete deployment ratings-v1
# the errors will change to 503. Again, the dashboards should showcase this.


####################################################################################################################
# Istio - Visualising Microservices Dependencies with Scope
# In this scenario, you will learn how you can use Weave Scope to identify the- 
# dependencies and application connections within your deployment.
####################################################################################################################

#--| Preparation
#--| Step 1 - Remove bookinfo from previous installation
kubectl delete -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl get pods

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
kubectl apply -f /root/kubernetes-istio-cicd/expose.yaml
kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml

#-| Step 2 - Deploy Scope
# Scope is deployed onto a Kubernetes cluster with the command 
kubectl create -f 'https://cloud.weave.works/launch/k8s/weavescope.yaml'
# Wait for it to be deployed by checking the status of the pods using 
kubectl get pods -n weave

# Make Scope Accessible
# Once deployed, expose the service to the public.
pod=$(kubectl get pod -n weave --selector=name=weave-scope-app -o jsonpath={.items..metadata.name})
kubectl expose pod $pod -n weave --external-ip="<master-ip>" --port=4040 --target-port=4040
# Important: Scope is a powerful tool and should only be exposed to trusted individuals and not the outside public. 
# Ensure correct firewalls and VPNs are configured.
# View Scope on port 4040 at http://<master-ip>:4040/

#-| Step 3 - View Dependencies with Scope
# Scope will display the deployments on Kubernetes, together with the connections and data flows between them.
# As the Scope data is based on live system traffic, as data flows change, the dependencies and connections will update to match. When the system scales or changes, Scope will redraw to update the changes.
# Scope has a number of interesting features:
# * You can hide system components, such as Istio, by changing the namespaces that are viewable.
# * By clicking each node, you can see what is running within the Pod, identifying memory or CPU consumption.
# * Scope also has the ability to view the live logs and attach to a running container directly within the application.

#-| Step 4 - Deploy V3
# As this is a live system, change the application to use V2/V3 of the Bookinfo deployment.
# This is done by deploying the Virtual Service with 
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-v2-v3.yaml
# When you visit the Product Page you will only see the reviews/ratings coming from V2 and V3. 
# Within Scope, you should see no requests being made to the v1 service.

#-| Step 5 - Service Graph
# Within Istio, the default deployment also includes the ability to draw a graph using Graphviz.
# This produces a static graph of the dependencies and the request count being made.
# http://<master-ip>/dotviz


: <<'END_COMMENT'
END_COMMENT

####################################################################################################################
# XXXXX          
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
