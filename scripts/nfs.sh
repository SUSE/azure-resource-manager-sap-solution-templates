#!/bin/bash

function log()
{
  message=$@
  echo "$message"
  echo "$message" >> /var/log/sapconfigcreate
}

function getdevicepath()
{

  log "getdevicepath"
  getdevicepathresult=""
  local lun=$1
  local readlinkOutput=$(readlink /dev/disk/azure/scsi1/lun$lun)
  local scsiOutput=$(lsscsi)
  if [[ $readlinkOutput =~ (sd[a-zA-Z]{1,2}) ]];
  then
    log "found device path using readlink"
    getdevicepathresult="/dev/${BASH_REMATCH[1]}";
  elif [[ $scsiOutput =~ \[5:0:0:$lun\][^\[]*(/dev/sd[a-zA-Z]{1,2}) ]];
  then
    log "found device path using lsscsi"
    getdevicepathresult=${BASH_REMATCH[1]};
  else
    log "lsscsi output not as expected for $lun"
    exit -1;
  fi
  log "getdevicepath done"

}

function createlvm()
{
  
  log "createlvm"

  lunsA=(${1//,/ })
  vgName=$2
  lvName=$3

  arraynum=${#lunsA[@]}
  log "count $arraynum"
  
  log "createlvm - creating lvm"

  numRaidDevices=0
  raidDevices=""
  num=${#lunsA[@]}
  log "num luns $num"
  
  for ((i=0; i<num; i++))
  do
    log "trying to find device path"
    lun=${lunsA[$i]}
    getdevicepath $lun
    devicePath=$getdevicepathresult;
    
    if [ -n "$devicePath" ];
    then
      log " Device Path is $devicePath"
      numRaidDevices=$((numRaidDevices + 1))
      raidDevices="$raidDevices $devicePath "
    else
      log "no device path for LUN $lun"
      exit -1;
    fi
  done

  log "num: $numRaidDevices paths: '$raidDevices'"
  $(pvcreate $raidDevices)
  $(vgcreate $vgName $raidDevices)
  $(lvcreate --extents 100%FREE --stripes $numRaidDevices --name $lvName $vgName)

  log "createlvm done"
}

log $@

luns=""
node=0
lbip=""
lbname=""
lbprobe=""
ipnode0=""
ipnode1=""
hostnode0=""
hostnode1=""
xlun=""
subnet=""

while true; 
do
  case "$1" in
    "-luns")  luns=$2;shift 2;log "found luns"
    ;;
    "-node")  node=$2;shift 2;log "found node"
    ;;
    "-lbip")  lbip=$2;shift 2;log "found lbip"
    ;;
    "-lbname")  lbname=$2;shift 2;log "found lbname"
    ;;
    "-lbprobe")  lbprobe=$2;shift 2;log "found lbprobe"
    ;;
    "-ipnode0")  ipnode0=$2;shift 2;log "found ipnode0"
    ;;
    "-ipnode1")  ipnode1=$2;shift 2;log "found ipnode1"
    ;;
    "-hostnode0")  hostnode0=$2;shift 2;log "found hostnode0"
    ;;
    "-hostnode1")  hostnode1=$2;shift 2;log "found hostnode1"
    ;;
    "-xlun")  xlun=$2;shift 2;log "found xlun"
    ;;
    "-subnet")  subnet=$2;shift 2;log "found subnet"
    ;;
    *) log "unknown parameter $1";shift 1;
    ;;
  esac

  if [[ -z "$1" ]];
  then 
    break; 
  fi
done

log "running with $luns $node $lbip $lbname $ipnode0 $ipnode1 $hostnode0 $hostnode1"

if [[ $node -eq 0 ]]
then
  log "running on node 0"
  myip=$ipnode0
  otherip=$ipnode1
  myhost=$hostnode0
  otherhost=$hostnode1
else
  log "running on node 1"
  myip=$ipnode1
  otherip=$ipnode0
  myhost=$hostnode1
  otherhost=$hostnode0
fi

log "installing packages"
zypper update -y
zypper install -y -l sle-ha-release fence-agents drbd drbd-kmp-default drbd-utils

createlvm $luns "vg_NFS" "lv_NFS"

log "fixing hosts"
hosts=$(cat /etc/hosts)
if [[ $hosts =~  $lbip ]]
then
  log "host already in /etc/hosts"
else  
  log "host not in /etc/hosts"
  echo "$lbip $lbname" >> /etc/hosts
fi
if [[ $hosts =~  $myip ]]
then
  log "my host already in /etc/hosts"
else  
  log "my host not in /etc/hosts"
  echo "$myip $myhost" >> /etc/hosts
fi
if [[ $hosts =~  $otherip ]]
then
  log "my host already in /etc/hosts"
else  
  log "my host not in /etc/hosts"
  echo "$otherip $otherhost " >> /etc/hosts
fi

if [[ $node -eq 0 ]]
then    
  getdevicepath $xlun;
  devicePath=$getdevicepathresult;
  if [ -n "$devicePath" ];
  then
    log " Device Path is $devicePath"
    # http://superuser.com/questions/332252/creating-and-formating-a-partition-using-a-bash-script
    $(echo -e "n\np\n1\n\n\nw" | fdisk $devicePath) > /dev/null
    partPath="$devicePath""1"
    $(mkfs -t xfs $partPath) > /dev/null
    $(mkdir -p /mnt/x)
    $(mount -t xfs $partPath /mnt/x)
  else
    log "no device path for LUN $lun"
    exit -1;
  fi
  
  log "creating cluster"
  corosync-keygen
  #ha-cluster-init -y csync2
  ha-cluster-init -y -u corosync 
  ha-cluster-init -y cluster
  cp /etc/corosync/authkey /mnt/x
  # Fist move to new file otherwise file would be empty
  # https://unix.stackexchange.com/questions/48725/redirecting-tr-stdout-to-a-file
  cat /etc/corosync/corosync.conf | tr '\n' '\r' | perl -pe "s|nodelist.*?}.*?}|nodelist {\n\tnode {\n\t\tring0_addr: $myhost\n\t\tnodeid: 1\n\t}\n\tnode {\n\t\tring0_addr: $otherhost\n\t\tnodeid: 2\n\t}\n}\n|"  | tr '\r' '\n' > /etc/corosync/corosync.conf.new
  mv /etc/corosync/corosync.conf.new /etc/corosync/corosync.conf
  systemctl restart corosync
  cp /etc/corosync/corosync.conf /mnt/x
  #cp /etc/csync2/key_hagroup /mnt/x
  #sed -i -e "s/host $myhost/host $myhost $otherhost/g" /etc/csync2/csync2.cfg
  #cp /etc/csync2/csync2.cfg /mnt/x
  umount /mnt/x/
  passwd -d hacluster
else
  getdevicepath $xlun;
  devicePath=$getdevicepathresult;
  if [ -n "$devicePath" ];
  then
    partPath="$devicePath""1"
    $(mkdir -p /mnt/x)
    $(mount -t xfs $partPath /mnt/x)
  else
    log "no device path for LUN $lun"
    exit -1;
  fi
  log "joining cluster"
  cp /mnt/x/authkey /etc/corosync/
  cp /mnt/x/corosync.conf /etc/corosync/
  #cp /mnt/x/key_hagroup /etc/csync2/
  #cp /mnt/x/csync2.cfg /etc/csync2/
  systemctl restart corosync
  ha-cluster-join -y -c $otherhost cluster
  #csync2 -xv
  #corosync-cfgtool -R
  passwd -d hacluster   
fi
cat >/etc/drbd.d/NWS_nfs.res <<EOL
resource NWS_nfs {
   protocol     C;
   disk {
      on-io-error       pass_on;
   }
   on $hostnode0 {
      address   $ipnode0:7790;
      device    /dev/drbd0;
      disk      /dev/vg_NFS/lv_NFS;
      meta-disk internal;
   }
   on $hostnode1 {
      address   $ipnode1:7790;
      device    /dev/drbd0;
      disk      /dev/vg_NFS/lv_NFS;
      meta-disk internal;
   }
}
EOL

log "Create NFS server and root share"
echo "/srv/nfs/ *(rw,no_root_squash,fsid=0)">/etc/exports
systemctl enable nfsserver
service nfsserver restart
mkdir /srv/nfs/

drbdadm create-md NWS_nfs
drbdadm up NWS_nfs
drbdadm status
if [[ $node -eq 1 ]]
then
  log "waiting for connection"
  drbdsetup wait-connect-resource NWS_nfs
  drbdadm status

  drbdadm new-current-uuid --clear-bitmap NWS_nfs
  drbdadm status

  drbdadm primary --force NWS_nfs
  drbdadm status

  log "waiting for drbd sync"
  drbdsetup wait-sync-resource NWS_nfs
  mkfs.xfs /dev/drbd0
  log "waiting for drbd sync"
  drbdsetup wait-sync-resource NWS_nfs

  mask=$(echo $subnet | cut -d'/' -f 2)
  
  log "Creating NFS directories"
  mkdir /srv/nfs/NWS
  chattr +i /srv/nfs/NWS
  mount /dev/drbd0 /srv/nfs/NWS
  mkdir /srv/nfs/NWS/sidsys
  mkdir /srv/nfs/NWS/sapmntsid
  mkdir /srv/nfs/NWS/trans
  mkdir /srv/nfs/NWS/ASCS
  mkdir /srv/nfs/NWS/ASCSERS
  mkdir /srv/nfs/NWS/SCS
  mkdir /srv/nfs/NWS/SCSERS
  umount /srv/nfs/NWS

  log "waiting for drbd sync"
  drbdsetup wait-sync-resource NWS_nfs

  log "Creating NFS resources"

  crm configure property maintenance-mode=true
  crm configure property stonith-timeout=600
  
  crm node standby $hostnode0
  crm node standby $hostnode1

  crm configure rsc_defaults resource-stickiness="1"

  crm configure primitive drbd_NWS_nfs ocf:linbit:drbd params drbd_resource="NWS_nfs" op monitor interval="15" role="Master" op monitor interval="30"
  crm configure ms ms-drbd_NWS_nfs drbd_NWS_nfs meta master-max="1" master-node-max="1" clone-max="2" clone-node-max="1" notify="true" interleave="true"
  crm configure primitive fs_NWS_sapmnt ocf:heartbeat:Filesystem params device=/dev/drbd0 directory=/srv/nfs/NWS fstype=xfs options="sync,dirsync" op monitor interval="10s"

  crm configure primitive exportfs_NWS ocf:heartbeat:exportfs params directory="/srv/nfs/NWS" options="rw,no_root_squash" clientspec="*" fsid=1 wait_for_leasetime_on_stop=true op monitor interval="30s"
  crm configure primitive exportfs_NWS_sidsys ocf:heartbeat:exportfs params directory="/srv/nfs/NWS/sidsys" options="rw,no_root_squash" clientspec="*" fsid=2 wait_for_leasetime_on_stop=true op monitor interval="30s"
  crm configure primitive exportfs_NWS_sapmntsid ocf:heartbeat:exportfs params directory="/srv/nfs/NWS/sapmntsid" options="rw,no_root_squash" clientspec="*" fsid=3 wait_for_leasetime_on_stop=true op monitor interval="30s"
  crm configure primitive exportfs_NWS_trans ocf:heartbeat:exportfs params directory="/srv/nfs/NWS/trans" options="rw,no_root_squash" clientspec="*" fsid=4 wait_for_leasetime_on_stop=true op monitor interval="30s"
  crm configure primitive exportfs_NWS_ASCS ocf:heartbeat:exportfs params directory="/srv/nfs/NWS/ASCS" options="rw,no_root_squash" clientspec="*" fsid=5 wait_for_leasetime_on_stop=true op monitor interval="30s"
  crm configure primitive exportfs_NWS_ASCSERS ocf:heartbeat:exportfs params directory="/srv/nfs/NWS/ASCSERS" options="rw,no_root_squash" clientspec="*" fsid=6 wait_for_leasetime_on_stop=true op monitor interval="30s"
  crm configure primitive exportfs_NWS_SCS ocf:heartbeat:exportfs params directory="/srv/nfs/NWS/SCS" options="rw,no_root_squash" clientspec="*" fsid=7 wait_for_leasetime_on_stop=true op monitor interval="30s"
  crm configure primitive exportfs_NWS_SCSERS ocf:heartbeat:exportfs params directory="/srv/nfs/NWS/SCSERS" options="rw,no_root_squash" clientspec="*" fsid=8 wait_for_leasetime_on_stop=true op monitor interval="30s"
  
  crm configure primitive vip_NWS_nfs IPaddr2 params ip=$lbip cidr_netmask=$mask op monitor interval=10 timeout=20
  crm configure primitive nc_NWS_nfs anything params binfile="/usr/bin/nc" cmdline_options="-l -k $lbprobe" op monitor timeout=20s interval=10 depth=0

  crm configure group g-NWS_nfs fs_NWS_sapmnt exportfs_NWS exportfs_NWS_sidsys exportfs_NWS_sapmntsid exportfs_NWS_trans exportfs_NWS_ASCS exportfs_NWS_ASCSERS exportfs_NWS_SCS exportfs_NWS_SCSERS nc_NWS_nfs vip_NWS_nfs
  crm configure order o-NWS_drbd_before_nfs inf: ms-drbd_NWS_nfs:promote g-NWS_nfs:start
  crm configure colocation col-NWS_nfs_on_drbd inf: g-NWS_nfs ms-drbd_NWS_nfs:Master

  crm node online $hostnode1
  crm node online $hostnode0
  crm configure property maintenance-mode=false
fi