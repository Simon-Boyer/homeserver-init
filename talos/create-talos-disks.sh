#!/bin/bash

# Example: ./create-disks.sh --out _out --talos_version "v1.3.7" --disk /dev/xvdc --endpoint kube-test.local.codegameeat.com --cluster_name test

while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
   fi
  shift
done

mkdir -p $out

# Main Talos Image
docker run --rm -i "ghcr.io/siderolabs/imager:$talos_version" iso --arch amd64 --tar-to-stdout --extra-kernel-arg console=tty0 --extra-kernel-arg console=ttyS1 --extra-kernel-arg talos.config=metal-iso | tar xz -C $out

if [[ -z "$existing_talos_path" ]]; then
        cd $out
        wget "https://github.com/siderolabs/talos/releases/download/$talos_version/talosctl-linux-amd64" -O talosctl
        chmod +x talosctl
        ./talosctl gen secrets -o secrets.yaml
        ./talosctl gen config --with-secrets secrets.yaml "$cluster_name" https://"$endpoint":6443 --additional-sans "$endpoint" --install-disk "$disk"
        ./talosctl --talosconfig talosconfig config endpoint $endpoint
        cd -
fi

mkdir -p $out/iso-control-plane
mkdir -p $out/iso-worker

cp ${existing_talos_path:-"$out"}/controlplane.yaml $out/iso-control-plane/config.yaml
cp ${existing_talos_path:-"$out"}/worker.yaml $out/iso-worker/config.yaml

cd _out

sudo mkisofs -joliet -rock -volid 'metal-iso' -output worker.iso iso-worker/
sudo mkisofs -joliet -rock -volid 'metal-iso' -output control-plane.iso iso-control-plane/

qemu-img convert -O vmdk worker.iso worker.vmdk
qemu-img convert -O vmdk control-plane.iso control-plane.vmdk

cd -
