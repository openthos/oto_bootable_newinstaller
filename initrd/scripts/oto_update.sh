#!/bin/sh

UPDATE_NONEED=0
UPDATE_SHOULD=1
UPDATA_MISS=2

UPDATE_SRC=/mnt/data/media/0/System_Os
UPDATE_INFO=$UPDATE_SRC/update
UPDATE_PACK=$UPDATE_SRC
UPDATE_DESC=update.list

TMP_DIR=/tmp/oto_update

#----------------------------------
# by: David Chan (chanuei@sina.com)
# date: 2016-09-14
#
# Func: load_update_desc
load_update_desc()
{
  pushd $TMP_DIR
  local varPackFormat="$(echo $UPDATE_PACK | rev | cut -d. -f1 | rev)"
  if [ "$varPackFormat" = "zip" ]; then
    unzip -o $UPDATE_PACK $UPDATE_DESC
  elif [ "$varPackFormat" = "iso" ]; then
    :
  else
    dbg_printf "load_update_desc: Unsupported update package format with $varPackFormat"
    popd
    return 1
  fi
  popd
  return 0
}

#----------------------------------
# by: David Chan (chanuei@sina.com)
# date: 2016-09-13
#
# Func: update_detect
# Ret Value:
#   UPDATE_NONEED, The os should not be updated
#   UPDATE_SHOULD, The os should be updated
update_detect()
{
  if [ -e $UPDATE_INFO ]; then
    local updateVar=`tail -n 1 $UPDATE_INFO`
    case $updateVar in
    1)
      if [ -e $UPDATE_PACK ]; then
        return $UPDATE_SHOULD
      fi
      ;;
    *)
      return $UPDATA_MISS
      ;;
    esac
  fi
  return $UPDATE_NONEED
}

#----------------------------------
# by: David Chan (chanuei@sina.com)
# date: 2016-09-14
#
# Func: replace_img_file
# Param:
#   $1, imgFile
#   $2, imgPath
replace_img_file()
{
  local retVar;
  pushd $2
  local varPackFormat="$(echo $UPDATE_PACK | rev | cut -d. -f1 | rev)"
  if [ "$varPackFormat" = "zip" ]; then
    unzip -o $UPDATE_PACK $1
    retVar=0
  elif [ "$varPackFormat" = "iso" ]; then
    :
    retVar=0
  else
    dbg_printf "load_update_desc: Unsupported update package format with $varPackFormat"
    retVar=1
  fi
  popd
  return $retVar
}

#----------------------------------
# by: David Chan (chanuei@sina.com)
# date: 2016-09-13
#
# Func: do_update
# Param:
#   $1, imgFile
#   $2, imgPath
do_update()
{  
  local retVar=0
  
  pushd /mnt
  
  dbg_printf "do_update with $1 ..."

  case $1 in
  boto.zip)
    :
    ;;
    
  system.sfs)
    get_param_from_bootargs SYSTEM_HD_UUID

    if [ -n "$SYSTEM_HD_UUID" ]; then
      case $BOOT_MODE in
      hdimgboot)
        prepare_mountpoint system
        mount_part_via_uuid $SYSTEM_HD_UUID system
        local systemImagePath
        get_param_from_bootargs SYSTEM_IMG
        systemImagePath="$(echo $SYSTEM_IMG | rev | cut -d/ -f2- | rev)"
        replace_img_file $1 system/$systemImagePath
        sleep 1s
        umount system
        ;;
      hdboot)
        local varFsType
        get_hd_fstype $SYSTEM_HD_UUID varFsType
        local hdPart
        hdPart="$(for c in `blkid | grep -m 1 -i $SYSTEM_HD_UUID`; do echo $c | grep -i "/dev" | cut -d":" -f1; done)"
        mkfs -F -t $varFsType -U $SYSTEM_HD_UUID $hdPart
        prepare_mountpoint system
        mount_part_via_uuid $SYSTEM_HD_UUID system
        pushd system
        
        unzip -o $UPDATE_PACK $1
        prepare_mountpoint /mnt/system.sfs
        mount -o loop system.sfs /mnt/system.sfs
        prepare_mountpoint /mnt/system.img
        mount -t ext4 -o loop /mnt/system.sfs/system.img /mnt/system.img 
        local varFsType
        cp -af /mnt/system.img/* ./
        sync;sync;sync
        
        umount /mnt/system.img
        umount /mnt/system.sfs
        rm -f $1
        popd
        umount system
        ;;

      *)
        retVar=1
        ;;
      esac
    else
      echo "hdimg_replace_file: Fata error, no RAMDISK_HD_UUID found from bootagrs."
      retVar=1
    fi      
    ;;
    
  ramdisk.img | initrd.img | kernel)
    get_param_from_bootargs RAMDISK_HD_UUID
    prepare_mountpoint ramdisk
    if [ -n "$RAMDISK_HD_UUID" ]; then
      mount_part_via_uuid $RAMDISK_HD_UUID ramdisk "async"
      local ramdiskImagePath
      get_param_from_bootargs RAMDISK_IMG
      ramdiskImagePath="$(echo $RAMDISK_IMG | rev | cut -d/ -f2- | rev)"
      dbg_printf "ramdiskImagePath=$ramdiskImagePath while RAMDISK_IMG=$RAMDISK_IMG"
      replace_img_file $1 ramdisk/$ramdiskImagePath
      sync;sync;sync
      
#      if [ "$1" = "ramdisk.img" ]; then
#      :
#        sleep 2s
#      fi
      
#      sleep 1s
      
      dbg_printf "will umount ramdisk, now at $PWD"
      umount ramdisk
    else
      echo "hdimg_replace_file: Fata error, no RAMDISK_HD_UUID found from bootagrs."
      retVar=1
    fi
    ;;
    
  *)
    dbg_printf "hd_update_filesystem: $UPDATE_DESC in the $UPDATE_PACK show me a file $1, but I don\'t know what to do with it."
    retVar=1
    ;;
  esac
  
  popd
  
  return $retVar
}

#----------------------------------
# by: David Chan (chanuei@sina.com)
# date: 2016-09-20
#
# Func: openthos_update_stage2
openthos_update_stage2()
{
  dbg_echo "Update file found, your os will be updated."
  mkdir -p $TMP_DIR
  load_update_desc
  if [ $? -ne 0 ]; then
    echo hdimg_update: Failed to update OpenThos
    return 1
  fi
  
  local line
  cat $TMP_DIR/$UPDATE_DESC | while read line; do
    do_update $line
    if [ $? -ne 0 ]; then
      updateRet=-2
    fi
  done
  
    
  sed -i '$d' $UPDATE_INFO
  echo $updateRet >> $UPDATE_INFO
  
  if [ $updateRet -eq 0 ]; then
    dbg_echo "openthos_update: Updating process succeeded."
  else
    echo openthos_update: Updating process failed.
  fi
}

#----------------------------------
# by: David Chan (chanuei@sina.com)
# date: 2016-09-13
#
# Func: update_detect
openthos_update()
{
  dbg_echo "oto_update: Checking ..."
  
  if [ ! "$BOOT_MODE" = "hdboot" ] && [ ! "$BOOT_MODE" = "hdimgboot" ]; then
  
    echo $BOOT_MODE
    return
  fi
  
  updateRet=0
  get_param_from_bootargs DATA_HD_UUID

  if [ -n "$DATA_HD_UUID" ]; then
    pushd /mnt
    
    prepare_mountpoint data
    if [ "$BOOT_MODE" = "hdimgboot" ]; then
      prepare_mountpoint data.hd
      
      mount_part_via_uuid $DATA_HD_UUID data.hd
      if [ $DEBUG -gt 0 ]; then
        ls data.hd
      fi
      get_param_from_bootargs DATA_IMG
      mount -o loop data.hd/$DATA_IMG data
      
    else
      
      mount_part_via_uuid $DATA_HD_UUID data
    fi
    
    if [ -f $UPDATE_INFO ];
    then
        UPDATE_PACK="$UPDATE_PACK/$(tac $UPDATE_INFO | sed -n 2p)"
        dbg_printf "$UPDATE_PACK"
    fi

    update_detect
    
    case $? in
    $UPDATE_MISS)
      echo "openthos_update: It seems that the system should be updated, but no update package found."
      ;;
    $UPDATE_SHOULD)

      get_param_from_bootargs RAMDISK_HD_UUID
      prepare_mountpoint ramdisk

      mount_part_via_uuid $RAMDISK_HD_UUID ramdisk

      dbg_echo "now is at `pwd`"
      pushd /
      zcat /mnt/ramdisk/OpenThos/install.img | cpio -id
      popd
      which dialog
      if [ $? -eq 0 ]; then
        dialog --backtitle "OpenThos" --title "OTA Update hooker" --infobox "Will upgrade your system now!" 32 80
        sleep 2s
        openthos_update_stage2
#        openthos_update_stage2 | dialog --nook --backtitle "OpenThos" --title "Now Upgrading ..." --programbox 32 80
        dialog --backtitle "OpenThos" --title "OTA Update hooker" --infobox "\n\n  Upgrade process finished! \n  Now, just enjoy your new OpenThos system!" 32 80
        sleep 2s
      else
        openthos_update_stage2
      fi
      if [ -d /mnt/data/dalvik-cache ]; then
        rm -rf /mnt/data/dalvik-cache/*
      fi
	rm -rf /mnt/data/media/0/System_Os/*
      ;;
    *)
      dbg_echo "openthos_update: No update to be done."
      ;;
    esac
 

    rm -rf $TMP_DIR
    umount data
    
    mountpoint data.hd >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      umount data.hd
    fi
    popd
  fi
}
