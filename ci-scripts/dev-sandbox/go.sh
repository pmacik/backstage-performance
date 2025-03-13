#!/bin/bash

backstage_metric_json='{"groupVersionKind":{"group":"rhdh.redhat.com","kind":"Backstage","version":"v1alpha3","labelsFromPath":{"name":["metadata","name"],"namespace":["metadata","namespace"]},"metrics":[{"name":"backstage_status","help":"Backstage Status Conditions","each":{"type":"Gauge","gauge":{"path":["status","conditions"],"labelsFromPath":{"type":["type"]},"valueFrom":["status"]}}}]}}'

cli="oc"

configmap=kube-state-metrics-custom-resource-state-configmap
key=custom-resource-state-configmap.yaml
config="$key"

$cli -n openshift-monitoring extract configmap/"$configmap" --to=- --keys="$key" >"$config"

yq -ie '.spec.resources += '"$backstage_metric_json" "$config"

$cli -n openshift-monitoring set data configmap/"$configmap" --from-file="$key"="$config"
