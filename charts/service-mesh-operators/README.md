# service-mesh-operators — referencia legada

**No instalar este chart en `ocpai-prd-mtz` (OpenShift 4.22).** El overlay no lo referencia, `install-waves.sh` no lo ejecuta y no hay `platform/values/service-mesh-operators/`.

Se conserva en el repositorio solo como **referencia legada**: así se puede ver cómo se suscribía Service Mesh 3 (`servicemeshoperator3.v3.3.3`) en clusters anteriores a 4.19 / laboratorios OpenTLC que no tenían Gateway API gestionado por el Ingress Operator.

## Por qué no se instala en OpenShift 4.22

1. **CRDs de Gateway API vienen con OpenShift.** Desde 4.19 el Ingress Operator publica y mantiene las CRDs `gateway.networking.k8s.io`. En 4.22 ese ciclo de vida lo sigue el Ingress Operator, no un operador OLM aparte.

2. **El control plane Istio lo crea el Ingress Operator.** Al aplicar un `GatewayClass` con `controllerName: openshift.io/gateway-controller/v1` (chart `gateway-api`, clase `openshift-default`), el Ingress Operator instala un control plane Istio ligero (basado en Red Hat OpenShift Service Mesh) en el namespace `openshift-ingress`. No hace falta un `Istio` CR ni la CSV `servicemeshoperator3`.

3. **Dos gestores del mismo plano chocan.** Instalar este chart suscribe `servicemeshoperator3` vía OLM. Ese operador también instala CRDs Istio y puede reclamar Gateways. La condición `CRDsReady` del `GatewayClass` indica que las CRDs Istio las gestiona **o** el Ingress Operator **o** OLM. Tener ambos a la vez puede dejar el `GatewayClass` sin aceptar, duplicar control planes o romper Connectivity Link / MaaS.

4. **MaaS y RHCL ya apuntan al controlador de OpenShift.** RHCL parchea `ISTIO_GATEWAY_CONTROLLER_NAMES` con `openshift.io/gateway-controller/v1`. El `Gateway` `maas-default-gateway` usa `gatewayClassName: openshift-default`. OpenShift AI deja `serviceMesh.managementState: Removed` en el DSCInitialization para no instalar Service Mesh 2.

## Qué usar en su lugar

Wave 3 del overlay: solo `charts/gateway-api`. Después comprobar:

```bash
oc get gatewayclass openshift-default
# Accepted, ControllerInstalled, CRDsReady = True
```

Documentación: [README.md](../../README.md#gateway-api-on-openshift-422-no-service-mesh-3-operator) y [INSTALL.md](../../clusters/ocpai-prd-mtz/INSTALL.md).
