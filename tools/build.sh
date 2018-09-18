#!/bin/bash

#
## Create the files for uploading to the Marketplace
## (c) peters@suse.com
#
#set -x 

GITHOME=/data/GITHUB/

BUILDHOME=$GITHOME/azure-resource-manager-sap-solution-templates
MP_HOME=$BUILDHOME/for_marketplace/

GIT_TEMPLATE=azuredeploy.json
MP_TEMPLATE=mainTemplate.json

TEMPLATE_LIST='2Tier 3Tier 3TierHA'


for DIR in $TEMPLATE_LIST
do
   echo "Creating Marketplace file for $DIR"

   cd $BUILDHOME/$DIR

   VERSION=`cat version.txt`||exit 1

   #create filename
   MP_ZIP_FILE=$DIR"_mp_template_"$VERSION".zip"

   #check if we need to do something
   if [ ! -f "$MP_HOME/$MP_ZIP_FILE" ]
   then
      echo -e "\tBuilding ..."

      #copy for MP names
      cp $GIT_TEMPLATE $MP_TEMPLATE

      # replace GUID because we want to identifiy from which place it
      # got deployed
      GUID=`cat mp_guid.txt`
      sed -i "s/\"name\": \"pid-.*\",/\"name\": \"pid-$GUID\",/" $MP_TEMPLATE
      
      #check changes - only the GUID should be different
      diff -b $GIT_TEMPLATE $MP_TEMPLATE

      #create marketplace zip file in a seperate folder
      zip $MP_HOME'/'$MP_ZIP_FILE createUiDefinition.json mainTemplate.json

      # remove Marketplace file name
      rm $MP_TEMPLATE
  else
     echo -e "\tnothing to do ... the version exist"
  fi

done






