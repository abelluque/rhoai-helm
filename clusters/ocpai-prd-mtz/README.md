# ocpai-prd-mtz — overlay MaaS / RHOAI

Cluster de **11 nodos**: 3 masters VM (no schedulable), 3 infra VM, 3 workers VM, 2 SuperMicro SYS-521GE-TNRT (12× H200, solo inferencia).

- OpenShift AI, GitOps, Pipelines, Authorino y Connectivity Link en VMs (`workload.rhoai.io/platform=true`)
- Gateway API vía Ingress Operator de OpenShift 4.22. **No** se instala Service Mesh 3: el chart `charts/service-mesh-operators` queda como referencia legada ([por qué](INSTALL.md#4-wave-3--gateway-api-ingress-operator-openshift-422)).
- Model Registry (MySQL + MinIO + `ModelRegistry` CR) en VMs, storage Nutanix Files
- Tres LLMs en GPU: Granite 3.0 8B, Qwen2.5-Coder 32B FP8, DeepSeek-Coder 33B

## Documentación

1. [DAY0.md](DAY0.md) — login, labels/taints, secretos, Nutanix
2. [INSTALL.md](INSTALL.md) — comandos Helm exactos y diagramas
3. `./scripts/render.sh` — template local sin cluster

```bash
./scripts/day0.sh
./scripts/install-waves.sh
./scripts/install-models.sh
./scripts/validate.sh
```
