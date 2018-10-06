# Environment:
# CentOS Linux release 7.5.1804 (Core) minimal installation
# 1 master node (4vCpu, 4Gb RAM, 20GB Disk, Nat or Wan or Bridge Network) 
# 1 Worker Node or More (2vCpu, 2Gb RAM, 20GB Disk, Nat or Wan or Bridge Network)
# 

# Prepae Operating System
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
bash -c 'cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF'
sysctl -p

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configuration of the Kubernetes Master (172.16.0.22 my master IP, 192.168.0.0/16 is default istio Network)
kubeadm init --apiserver-advertise-address=172.16.0.22  --pod-network-cidr=192.168.0.0/16

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
kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml -n istio-system
kubectl apply -f install/kubernetes/istio-demo-auth.yaml
kubectl get pods -n istio-system
kubectl get svc -n istio-system




kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl get pods
kubectl apply -f samples/bookinfo/networking/destination-rule-all-mtls.yaml



# Expose bookinfo sample app
vim /root/expose.yaml

  
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

