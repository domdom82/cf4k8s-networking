# CF for K8s networking

## Logical Network Traffic

![](doc/LogicalNetwork.png)

## Physical Network Traffic

![](doc/Network.png)

## Open Questions

* Which server entry is used. The one from `istio-system/ingressgateway` or the one on `cf-system/istio-ingressgateway` -> Only `cf-system/istio-ingressgateway` is used by virtual services.