#!/bin/bash

kubectl get clusterrolebindings | grep keda | awk '{print $1}' | xargs kubectl delete clusterrolebinding
kubectl get clusterroles | grep keda | awk '{print $1}' | xargs kubectl delete clusterrole
kubectl get rolebindings -n kube-system | grep keda | awk '{print $1}' | xargs kubectl delete rolebinding -n kube-system
kubectl get apiservices | grep keda | awk '{print $1}' | xargs kubectl delete apiservice
kubectl get validatingwebhookconfigurations | grep keda | awk '{print $1}' | xargs kubectl delete validatingwebhookconfiguration

kubectl get crd | grep keda | awk '{print $1}' | xargs kubectl delete crd