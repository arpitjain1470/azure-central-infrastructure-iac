# Runbook — Azure IAC (Hub & Spoke) Deployment

**Purpose:** Quick operational guide for running the Azure DevOps pipeline that deploys Platform (Connectivity, Identity), Landing (spokes), and Peerings using Bicep at subscription scope.

> **Pipeline file:** `azure-iac/pipelines/deploy-prod.yml`  
> **Main template:** `azure-iac/main.bicep`  
> **Params root:** `azure-iac/env/prod/<Level>/<Subscription>/<region>.parameters.json`

***

## 1) Prerequisites

*   **Azure DevOps Service Connections**
    *   Each subscription mapped under `variables` in the YAML (e.g., `prodSc.CONNECTIVITY`) must exist.
    *   **RBAC:**
        *   **Contributor** on its own subscription (to deploy).
        *   **Reader** on **remote** subscriptions referenced via `remoteVnetId` (so peering “wait” checks can see remote VNets).

*   **Agents:** Use **Microsoft-hosted Ubuntu** (`ubuntu-latest`). `jq` and `az` are available.

*   **Parameter files:** Provide correct values for:
    *   `rgName`, `location`, `vnets[]`, `nsgs[]`, `udrs[]`, `peerings[]`, `additionalResourceGroups[]`.
    *   For peerings: `sourceVnetName`, **full** `remoteVnetId`.

***

## 2) Stages & Order (What Runs)

1.  **Platform** (Connectivity, Identity): WHAT‑IF → Phase 1 (RGs) → wait → Phase 2 (Core)
2.  **Landing** (spokes): WHAT‑IF → Phase 1 (RGs) → wait → Phase 2 (Core)
3.  **Platform Peerings (AFTER Landing)**: Identity ↔ Connectivity
4.  **Landing Peerings**: Spokes ↔ Hub

> The pipeline enforces **RG waits** after Phase 1 and **VNet waits** before peering to avoid race conditions.

***

## 3) Pipeline Parameters (Controls)

| Param           | Type    | Default | Effect                            |
| --------------- | ------- | ------- | --------------------------------- |
| `runPlatform`   | boolean | true    | Include Platform stages.          |
| `runLanding`    | boolean | true    | Include Landing stages.           |
| `runWhatIf`     | boolean | true    | Run WHAT‑IF before deploy.        |
| `deployRG`      | boolean | true    | Run Phase 1 (RGs only).           |
| `deployNSG`     | boolean | true    | Include NSGs in Phase 2.          |
| `deployUDR`     | boolean | true    | Include UDRs in Phase 2.          |
| `deployVNet`    | boolean | true    | Include VNets/Subnets in Phase 2. |
| `deploypeering` | boolean | true    | Run peering stages.               |

> **Phase 1** is explicitly **RG-only** in the pipeline (`deploylb=false` is forced).

***

## 4) Common Run Scenarios

### A) Full end-to-end (standard)

*   **Parameters:** Keep defaults (all `true`).
*   **Outcome:** Platform → Landing → Platform Peerings → Landing Peerings.

### B) Bootstrap RGs only

*   **Parameters:** `deployRG=true`, all others **false**; `runWhatIf` as you like.
*   **Outcome:** Creates all required RGs; stops.

### C) Core only (after RGs)

*   **Parameters:** `deployRG=false`, set any of `deployNSG|deployUDR|deployVNet=true`, `deploypeering=false`.
*   **Outcome:** Deploys NSGs/UDRs/VNets only.

### D) Peerings only (re-run)

*   **Parameters:** `deployRG=false`, `deployNSG=false`, `deployUDR=false`, `deployVNet=false`, `deploypeering=true`.
*   **Outcome:** Runs Platform Peerings then Landing Peerings with wait checks.

### E) Platform only (hub/identity)

*   **Parameters:** `runPlatform=true`, `runLanding=false`.
*   Add `deploypeering` as needed.

### F) Landing only (spokes)

*   **Parameters:** `runPlatform=false`, `runLanding=true`.
*   Peerings will still wait for remote VNets if IDs are provided and visible.

***

## 5) How to Run (Azure DevOps)

1.  Go to **Pipelines → Run pipeline**.
2.  Set parameters per scenario (above).
3.  Run.
    *   WHAT‑IF stages appear only if `runWhatIf=true`.
    *   Peerings stages appear only if `deploypeering=true`.

***

## 6) Operational Checks

### Check service connection mapping

In YAML `variables`, verify:

```yaml
"prodSc.CONNECTIVITY": <ADO Service Connection Name>
"prodSc.IDENTITY":     <ADO Service Connection Name>
# ... and so on
```

### Validate Bicep locally (optional)

```bash
az bicep upgrade --yes
bicep build azure-iac/main.bicep
```

### Validate WHAT‑IF locally (optional)

```bash
az deployment sub what-if \
  --location centralus \
  --template-file azure-iac/main.bicep \
  --parameters @"azure-iac/env/prod/Platform/Connectivity/centus.parameters.json" \
    deployRG=true deployNSG=false deployUDR=false deployVNet=false deploypeering=false
```

***

## 7) Troubleshooting

### A) `ResourceGroupNotFound`

*   **Cause:** Core/peering steps executed before RGs were addressable.
*   **Pipeline has:** Explicit **RG waits** (`az group wait --created`).
*   **Action:** Re-run Phase 2 (Core) or Peerings.

### B) `InvalidGlobalResourceReference` (peering failed)

*   **Cause:** `remoteVnetId` does not exist (wrong ID, wrong subscription, or not deployed yet).
*   **Action:**
    *   Confirm **full** resource ID (sub/RG/name correct).
    *   Ensure **Platform** and **Landing** stages completed successfully.
    *   Ensure service connection has **Reader** on remote subscription.

### C) YAML parsing errors

*   **Cause:** Accidental HTML escapes or conditional keys in lists.
*   **Action:** Ensure scripts use real `&&`, `&>`, `2>/dev/null`. Avoid `${{ if ... }}:` as a **list item** key.

### D) Bicep compile errors (`BCP018`, `BCP007`)

*   **Cause:** Optional chaining (`.?`) or HTML-encoded operators.
*   **Action:** Replace with `contains(obj,'prop') ? obj.prop : <fallback>` and real `&&`.

***

## 8) Rollback / Rerun Strategy

*   **Idempotent reruns:** Safe to re-run WHAT‑IF / Phase 2 / Peerings; Bicep and ARM are declarative.
*   **Targeted rollback:** Remove or adjust entries in parameter files, then re-run the relevant phase/stage.
*   **Peering rollback:** Remove peering entries from `peerings[]` in the parameter file and re-run peering stage.

***

## 9) Adding a New Spoke (Landing)

1.  Create param file:  
    `azure-iac/env/prod/Landing/<SubName>/centus.parameters.json`
2.  Add `<SubName>` to `landingSubscriptions` when running the pipeline.
3.  Ensure a service connection mapping exists in YAML `variables`.
4.  Run with desired flags.

***

## 10) Notes & Best Practices

*   Keep **Platform peerings after Landing** (as implemented) if your Identity ↔ Connectivity peerings reference Landing VNets.
*   Maintain **Reader** access across subscriptions used in `remoteVnetId` to allow “wait for remote VNet” checks.
*   Use the **Peerings only** scenario to heal peering after any out-of-band fixes.

***

**Questions or changes?**  
Create an issue or PR with your scenario and the parameter files you’re using (redact sensitive values).
