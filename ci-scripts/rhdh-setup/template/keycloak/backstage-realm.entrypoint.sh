#!/bin/bash

if [ -z "${REALM_SIZE}" ]; then
  echo "REALM_SIZE environment variable is required"
  exit 1
fi

#cp -vf /realm-data/backstage-realm.${REALM_SIZE}.json /mnt/realm-data/backstage-realm.json
tar -xvf /realm-data/backstage-realm.${REALM_SIZE}.json.tar.gz -C /mnt/realm-data

ls -la /mnt/realm-data
