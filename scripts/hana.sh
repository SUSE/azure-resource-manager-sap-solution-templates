#!/bin/bash
#
## create all hana partitions depending on input parameter from ARM template
#

function log()
{
  message=$@
  echo "$message"
  #echo "$(date -Iseconds): $message" >> /var/log/sapconfigcreate
  echo "$(date -Iseconds): $message" >> /tmp/sapconfigcreate
}

function addtofstab()
{
  log "addtofstab"
  partPath=$1
  mount=$2
  
  local blkid=$(/sbin/blkid $partPath)
  
  if [[ $blkid =~  UUID=\"(.{36})\" ]]
  then
  
    log " Adding fstab entry"
    local uuid=${BASH_REMATCH[1]};
    local mountCmd=""
    log " adding fstab entry"
    mountCmd="/dev/disk/by-uuid/$uuid $mount xfs  defaults,nofail  0  2"
    echo "$mountCmd" >> /etc/fstab
    $(mount $partPath $mount)
  
  else
    log "ERR: no UUID found"
    exit -1;
  fi
  
  log "addtofstab done"
}

function getdevicepath()
{
  # Azure does create an additional entry below /dev/disk/
  # which links to the 
  # /dev/disk/azure 
  #   /dev/disk/azure/root
  #   /dev/disk/azure/resource
  #   /dev/disk/azure/scsi1  
  #     /dev/disk/azure/scsi1/lun0
  # /dev/disk/by-id  
  # /dev/disk/by-label
  # /dev/disk/by-path
  # /dev/disk/by-uuid

  log "getdevicepath"

  getdevicepathresult=""
  local lun=$1
  local readlinkOutput=$(readlink /dev/disk/azure/scsi1/lun$lun)
  local scsiOutput=$(lsscsi)
  if [[ $readlinkOutput =~ (sd[a-zA-Z]{1,2}) ]];
  then
    log " found device path using readlink"
    getdevicepathresult="/dev/${BASH_REMATCH[1]}";
  elif [[ $scsiOutput =~ \[5:0:0:$lun\][^\[]*(/dev/sd[a-zA-Z]{1,2}) ]];
  then
    log " found device path using lsscsi"
    getdevicepathresult=${BASH_REMATCH[1]};
  else
    log " ERR: :lsscsi output not as expected for $lun"
    exit -1;
  fi
  log "getdevicepath done"
}

function createlvm()
{
  log "createlvm"

  local lunsA=(${1//,/ })
  local vgName=$2
  local lvName=$3

  local lunsCount=${#lunsA[@]}

  local mountPathA=(${4//,/ })
  local sizeA=(${5//,/ })

  local mountPathCount=${#mountPathA[@]}
  local sizeCount=${#sizeA[@]}

  log " count $lunsCount $mountPathCount $sizeCount"

  if [[ $lunsCount -gt 1 ]]
  then
    log " creating lvm devices"

    local numRaidDevices=0
    local raidDevices=""
    log " num luns $lunsCount"
    
    for ((i=0; i<lunsCount; i++))
    do
      log " trying to find device path"
      local lun=${lunsA[$i]}
      getdevicepath $lun
      local devicePath=$getdevicepathresult;
      
      if [ -n "$devicePath" ];
      then
        log " Device Path is $devicePath"
        numRaidDevices=$((numRaidDevices + 1))
        raidDevices="$raidDevices $devicePath "
      else
        log " no device path for LUN $lun"
        exit -1;
      fi
    done

    log " num: $numRaidDevices paths: '$raidDevices'"
    $(pvcreate $raidDevices)
    $(vgcreate $vgName $raidDevices)

    for ((j=0; j<mountPathCount; j++))
    do
      local mountPathLoc=${mountPathA[$j]}
      local sizeLoc=${sizeA[$j]}
      local lvNameLoc="$lvName-$j"
      $(lvcreate --extents $sizeLoc%FREE --stripes $numRaidDevices --name $lvNameLoc $vgName)
      $(mkfs -t xfs /dev/$vgName/$lvNameLoc)
      $(mkdir -p $mountPathLoc)
    
      addtofstab /dev/$vgName/$lvNameLoc $mountPathLoc
    done

  else
    log " creating single disk"

    local lun=${lunsA[0]}
    local mountPathLoc=${mountPathA[0]}
    getdevicepath $lun;
    local devicePath=$getdevicepathresult;
    if [ -n "$devicePath" ];
    then
      log " Device Path is $devicePath"
      # http://superuser.com/questions/332252/creating-and-formating-a-partition-using-a-bash-script
      $(echo -e "n\np\n1\n\n\nw" | fdisk $devicePath) > /dev/null
      local partPath="$devicePath""1"
      $(mkfs -t xfs $partPath) > /dev/null
      $(mkdir -p $mountPathLoc)

      addtofstab $partPath $mountPathLoc
    else
      log " ERR: no device path for LUN $lun"
      exit -1;
    fi
  fi

  log "createlvm done"
}

function installPackages()
{
   log "installPackages start"

   # update everything
   zypper update -y
   # install pattern
   zypper install pattern -y sap-hana
   #install packages
   zypper install -y saptune
   
   log "installPackages done"
}

function enableSwap()
{
  log "enableSwap start"
  
  sed -i.bak "s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/" /etc/waagent.conf 
  sed -i.bak "s/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=2048/" /etc/waagent.conf
  
  #service waagent restart

  log "enableSwap done"
  
}

################
# ### MAIN ### #
################
log $@

# example input 
#
#  -luns "0,1#2,3#4#5#6#7"
#  -names "data#log#shared#usrsap#backup#sapmnt"
#  -paths "/hana/data#/hana/log#/hana/shared#/usr/sap#/hana/backup#/sapmnt/ABC"
#  -sizes "100#100#100#100#100#100"
#
luns=""
names=""
paths=""
sizes=""

numpara=0

if [ $# -eq 0 ]
then
  echo "No parameters provided";
  exit 2;
fi

while [ $# != 0 ];
do
  case "$1" in
    "-luns")  luns=$2;shift 2;log " found luns"
    ;;
    "-names")  names=$2;shift 2;log " found names"
    ;;
    "-paths")  paths=$2;shift 2;log " found paths"
    ;;
    "-sizes")  sizes=$2;shift 2;log " found sizes"
    ;;
    *) log "ERR:unknown parameter $1";shift 1; numpara=1
    ;;
  esac
done

if [ $numpara -ne 0 ]
then
  echo "Wrong parameters provided";
  exit 2;

fi

log " running with $luns $names $paths $sizes" 

lunsSplit=(${luns//#/ })
namesSplit=(${names//#/ })
pathsSplit=(${paths//#/ })
sizesSplit=(${sizes//#/ })

lunsCount=${#lunsSplit[@]}
namesCount=${#namesSplit[@]}
pathsCount=${#pathsSplit[@]}
sizesCount=${#sizesSplit[@]}

log " count $lunsCount $namesCount $pathsCount $sizesCount"

if [[ $lunsCount -eq $namesCount && $namesCount -eq $pathsCount && $pathsCount -eq $sizesCount ]]
then
  for ((ipart=0; ipart<lunsCount; ipart++))
  do
    lun=${lunsSplit[$ipart]}
    name=${namesSplit[$ipart]}
    path=${pathsSplit[$ipart]}
    size=${sizesSplit[$ipart]}

    log " creating disk with LUN: $lun VG: $name PATH: $path SIZE: $size"
    createlvm $lun "vg-$name" "lv-$name" "$path" "$size";
  done
else
  log "ERR: Input parameter count not equal"
  exit 1
fi

installPackages

saptune solution apply HANA
saptune daemon start

enableSwap

exit