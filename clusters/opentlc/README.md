# opentlc — laboratorio de ensayo MaaS / RHOAI

Overlay para ensayar, corregir y validar la instalación completa **antes** de `ocpai-prd-mtz`. Cluster OpenTLC **sin GPU**.

Consola: https://console-openshift-console.apps.cluster-6f7dh.6f7dh.sandbox3519.opentlc.com/

- OpenShift AI, GitOps, Pipelines, Authorino, Connectivity Link y Model Registry en los 3 workers (`workload.rhoai.io/platform=true`)
- Gateway API vía Ingress Operator (sin operador Service Mesh 3; el chart queda como referencia legada)
- **No** se instala `nvidia-gpu-enablement`
- Un SLM en CPU para validar MaaS: Granite 3.1 2B Instruct (`rhaii/vllm-cpu-rhel9`)
- No se despliegan Granite 8B, Qwen 32B ni DeepSeek 33B

## Nodos (us-east-2)

| Rol | Qty | Instance type | CPU | RAM | Disco | Schedulable |
| --- | --- | --- | --- | --- | --- | --- |
| Control plane | 3 | m6a.2xlarge | 8 | 30.67 GiB | 99.78 GiB | No |
| Worker | 3 | m6a.4xlarge | 16 | 61.46 GiB | 99.78 GiB | Sí (plataforma + SLM) |

## Documentación

1. [DAY0.md](DAY0.md) — login, labels, Postgres in-cluster
2. [INSTALL.md](INSTALL.md) — comandos Helm y diagramas
3. `./scripts/render.sh` — template local sin cluster

```bash
./scripts/day0.sh
./scripts/install-waves.sh
./scripts/install-models.sh
./scripts/validate.sh
```
