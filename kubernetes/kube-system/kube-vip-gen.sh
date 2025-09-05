sudo mkdir -p /etc/kubernetes/manifests
export VIP=10.0.10.200
export INTERFACE=eth0
export KVVERSION=v1.0.0

kube-vip() {
    sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
    sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip "$@"
}

kube-vip manifest pod \
    --interface "$INTERFACE" \
    --address "$VIP" \
    --controlplane \
    --arp \
    --leaderElection | sudo tee /etc/kubernetes/manifests/kube-vip.yaml
