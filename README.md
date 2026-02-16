# Azure IAC — Hub & Spoke Network Deployment (Bicep + Azure DevOps)

This repository contains **Bicep templates** and an **Azure DevOps pipeline** to deploy a **CAF-style** hub & spoke network architecture across subscriptions:

*   **Platform**: Connectivity (Hub), Identity (Platform)
*   **Landing**: Spokes (Citrix, DMZ, DR-IT, EMP-QA, EMP-Prod, etc.)
*   **Peerings**: Platform peerings (Identity ↔ Connectivity) **after Landing**, and Landing peerings (Spokes ↔ Hub)

The pipeline supports **phased deployments** (RGs → Core → Peerings), **WHAT-IF**, and **boolean toggles** to run only selected parts safely and repeatably.

***

## 🔎 Quick Links

*   **Pipeline YAML**: `/azure-iac/pipelines/deploy-prod.yml`
*   **Main Bicep**: `/azure-iac/main.bicep`
*   **Modules**:
    *   `/azure-iac/modules/resourcegroup/rg.bicep`
    *   `/azure-iac/modules/network/nsg.bicep`
    *   `/azure-iac/modules/network/udr.bicep`
    *   `/azure-iac/modules/network/vnet.bicep`
    *   `/azure-iac/modules/network/lb.bicep`
    *   `/azure-iac/modules/network/peering.bicep`
*   **Parameters** (per environment, level, subscription):  
    `/azure-iac/env/prod/<Level>/<Subscription>/<region>.parameters.json`  
    e.g. `/azure-iac/env/prod/Platform/Connectivity/centus.parameters.json`

***

## 📁 Repository Structure

    azure-iac/
    ├─ main.bicep
    ├─ pipelines/
    │  └─ deploy-prod.yml
    ├─ modules/
    │  ├─ resourcegroup/
    │  │  └─ rg.bicep
    │  └─ network/
    │     ├─ nsg.bicep
    │     ├─ udr.bicep
    │     ├─ vnet.bicep
    │     ├─ lb.bicep
    │     └─ peering.bicep
    └─ env/
       └─ prod/
          ├─ Platform/
          │  ├─ Connectivity/
          │  │  └─ centus.parameters.json
          │  └─ Identity/
          │     └─ centus.parameters.json
          └─ Landing/
             ├─ Citrix/
             │  └─ centus.parameters.json
             ├─ DMZ/
             │  └─ centus.parameters.json
             ├─ DR-IT/
             │  └─ centus.parameters.json
             ├─ EMP-QA/
             │  └─ centus.parameters.json
             └─ EMP-Prod/
                └─ centus.parameters.json

***

## 🧭 Deployment Flow (Stages)

The pipeline runs **in this order** to guarantee dependencies:

1.  **Platform** (WHAT‑IF optional → Phase 1 RGs → wait → Phase 2 Core)
2.  **Landing** (WHAT‑IF optional → Phase 1 RGs → wait → Phase 2 Core)
3.  **Platform Peerings** *(after Landing completes)* — e.g., **Identity ↔ Connectivity**
4.  **Landing Peerings** *(after Platform Peerings)* — Spokes ↔ Hub

> We moved **Platform peerings after Landing** because your Identity ↔ Connectivity peering references VNets that may be provisioned in Landing. This sequencing removes race conditions and invalid‑reference errors.

***

## ⚙️ Pipeline Parameters (boolean toggles)

These booleans let you **skip or run** specific scopes and phases:

| Parameter               | Type    | Default | Purpose                                                                   |
| ----------------------- | ------- | ------- | ------------------------------------------------------------------------- |
| `runPlatform`           | boolean | true    | Include Platform stages (Connectivity, Identity)                          |
| `runLanding`            | boolean | true    | Include Landing (spokes) stages                                           |
| `runWhatIf`             | boolean | true    | Run WHAT‑IF before deploy                                                 |
| `deployRG`              | boolean | true    | Phase 1: create RGs (RG‑only run)                                         |
| `deployNSG`             | boolean | true    | Phase 2: deploy NSGs                                                      |
| `deployUDR`             | boolean | true    | Phase 2: deploy UDRs                                                      |
| `deployVNet`            | boolean | true    | Phase 2: deploy VNets/Subnets                                             |
| `deploypeering`         | boolean | true    | Final stages: create peerings                                             |
| *(implicit)* `deploylb` | —       | —       | In Phase 1 the pipeline **forces** `deploylb=false` so Phase 1 is RG‑only |

***

## 🧪 WHAT‑IF and Phases

Each level (Platform/Landing) follows **phases**:

*   **WHAT‑IF**: subscription‑scope what-if for the param file
*   **Phase 1 (RG‑only)**: `deployRG=true` and everything else false (and `deploylb=false`)
*   **Wait for RGs**: `az group wait --created` for main and additional RGs
*   **Phase 2 (Core)**: `deployNSG|deployUDR|deployVNet` toggled from pipeline parameters
*   **Peerings** (final stages): `deploypeering=true` with waits for both **local** and **remote** VNets

***

## 📄 Parameter File Schema (example)

**Platform — Identity** (`/azure-iac/env/prod/Platform/Identity/centus.parameters.json`):

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "rgName": { "value": "rg-identity-vnets-centus-001" },
    "location": { "value": "centralus" },
    "tags": { "value": { "env": "prod", "owner": "netops" } },
    "additionalResourceGroups": { "value": [] },

    "vnets": {
      "value": [
        {
          "vnetName": "vn-identity-prod-centus-001",
          "addressSpace": [ "10.20.0.0/16" ],
          "subnets": [
            { "name": "sn-ad", "prefix": "10.20.1.0/24", "nsgName": "nsg-id-ad", "udrName": "rt-id-ad" }
          ],
          "dnsServers": [ "10.10.0.4", "10.10.0.5" ]
        }
      ]
    },

    "nsgs": { "value": [ { "name": "nsg-id-ad", "rules": [] } ] },
    "udrs": { "value": [ { "name": "rt-id-ad", "routes": [] } ] },

    "peerings": {
      "value": [
        {
          "peeringName": "identity-to-connectivity-centus",
          "sourceVnetName": "vn-identity-prod-centus-001",
          "remoteVnetId": "/subscriptions/<HUB_SUB_ID>/resourceGroups/rg-connectivity-centus-001/providers/Microsoft.Network/virtualNetworks/vn-it-conn-prod-centus-001",
          "allowForwardedTraffic": true,
          "allowGatewayTransit": false,
          "useRemoteGateways": false
        }
      ]
    },

    "lbs": { "value": [] }
  }
}
```

**Landing — Citrix** is similar, but `remoteVnetId` usually points to **Connectivity hub** VNet.

> Ensure **remoteVnetId** is the **full resource ID** of the target VNet (correct subscription, RG, name).

***

## 🧱 Bicep Expectations (high‑level)

`main.bicep` (subscription scope) expects the parameters above and supports flags:

*   `deployRG`, `deployNSG`, `deployUDR`, `deployVNet`, `deploypeering`, `deploylb`
*   **Do not** use optional chaining like `s.?nsgName` (Bicep doesn’t support it). Use `contains(s,'nsgName') ? s.nsgName : null` patterns.
*   Ensure no HTML-encoded operators (`&amp;&amp;`). Use real `&&`.

***

## ▶️ How to Run the Pipeline (Manual)

1.  In Azure DevOps → Pipelines → **Run pipeline**
2.  Choose parameters:
    *   **Scope**: `runPlatform`, `runLanding`
    *   **Phases**: `deployRG`, `deployNSG`, `deployUDR`, `deployVNet`, `deploypeering`
    *   **WHAT‑IF**: `runWhatIf`
3.  Click **Run**.

> The pipeline maps service connections via variables like `"prodSc.CONNECTIVITY": WC-SP-Central-WC1-DR-Connectivity`. Make sure these exist in Azure DevOps and have proper **RBAC**.

***

## 🔐 Service Connections & RBAC

For **waits** and **peerings** across subscriptions to work:

*   Each service connection used for a subscription should have:
    *   **Contributor** on its own subscription (for deploying resources)
    *   **Reader** on any **remote** subscription where `remoteVnetId` points (so `az resource show --ids <remoteVnetId>` can see it before peering)
*   If peerings are cross‑tenant, configure **appropriate SPN/permissions**.

***

## ✅ Common Use Cases

### 1) **RGs only (bootstrap)**

*   `deployRG=true`, everything else **false**, `deploypeering=false`
*   WHY: Create all RGs without deploying resources.

### 2) **Core only (no peerings)**

*   `deployRG=false`, set any of `deployNSG|deployUDR|deployVNet=true`, `deploypeering=false`
*   WHY: Build networks after RGs exist.

### 3) **Peerings only**

*   `deployRG=false`, `deployNSG=false`, `deployUDR=false`, `deployVNet=false`, `deploypeering=true`
*   WHY: Re-run peering after both sides are built.

### 4) **Full Hub → Spokes → Peerings (standard)**

*   All flags **true** (default)
*   WHY: End‑to‑end deploy.

### 5) **Platform only (Connectivity/Identity)**

*   `runLanding=false`

### 6) **Landing only (Spokes)**

*   `runPlatform=false`

***

## 🧰 Troubleshooting

### A) `ResourceGroupNotFound`

**Cause**: Phase 2/3 targeting RGs before they’re addressable.  
**Fixes**:

*   Phase 1 is **RGs only** (`deploylb=false` forced)
*   Pipeline **waits** with `az group wait --created` before Phase 2
*   Re-run Phase 2 after Phase 1 success

### B) `InvalidGlobalResourceReference` (peering)

**Cause**: `remoteVnetId` VNet not found (wrong ID, not yet deployed, wrong sub).  
**Fixes**:

*   Ensure **Platform** (Connectivity) runs **before** Landing
*   We **wait** for both **local** and **remote** VNets before peering
*   Verify the **full resource ID** and **RBAC** (Reader on remote sub)

### C) YAML parser errors like `Mapping values are not allowed...`

**Cause**: Conditional used as **key** inside a list or HTML‑encoded chars (`&gt;`, `&amp;`).  
**Fixes**:

*   Don’t use `${{ if ... }}:` inside arrays (`dependsOn`, `jobs`)
*   Replace `&gt;` → `>` and `&amp;` → `&` in scripts
*   Keep indentation consistent (spaces, no tabs)

### D) Bicep compile errors (`BCP018`, `BCP007`)

**Cause**: Optional chaining (`.?`) or HTML-encoded ops.  
**Fixes**:

*   Use `contains(obj,'prop') ? obj.prop : <fallback>`
*   Replace `&amp;&amp;` with `&&`
*   Optionally run: `az bicep upgrade --yes`

***

## 🧪 Local Validation

```bash
# Optional: keep bicep updated
az bicep upgrade --yes
az bicep version

# Build main template
bicep build azure-iac/main.bicep

# Dry-run What-If for a subscription
az deployment sub what-if \
  --location centralus \
  --template-file azure-iac/main.bicep \
  --parameters @"azure-iac/env/prod/Platform/Connectivity/centus.parameters.json" \
    deployRG=true deployNSG=false deployUDR=false deployVNet=false deploypeering=false
```

***

## 🧩 Adding a New Landing Subscription

1.  Create parameter file:  
    `/azure-iac/env/prod/Landing/<NewSub>/<region>.parameters.json`
2.  Add to `landingSubscriptions` list (pipeline parameter default or at run time)
3.  Ensure service connection mapping exists under `variables`:
        "prodSc.<NEWSUB>": <ADO Service Connection Name>
4.  Run pipeline with desired flags.

***

## 🔁 Re-running Peerings Only

If hub/spoke VNets exist but peering failed earlier:

*   Set `deploypeering=true`
*   Set all other flags **false**
*   Run pipeline — only the **final peering stages** execute

***

## 📝 Operational Tips

*   Prefer **explicit stage order** over complex `dependsOn` with conditionals — cleaner YAML and fewer parser issues.
*   Keep Bicep code **free of optional chaining** and **HTML-encoded** tokens.
*   If remote VNets are **cross‑subscription/tenant**, make sure your SPN has **visibility** to run `az resource show --ids`.

***

## ❓ FAQ

**Q: Why is “Platform Peerings” after Landing?**  
A: In this environment, Identity ↔ Connectivity peerings may reference VNets created in Landing. Running Platform peerings after Landing avoids invalid references during creation.

**Q: Can I run Connectivity only?**  
A: Yes — set `runLanding=false`. You can then run Platform peerings later (or skip by `deploypeering=false`).

**Q: How do I control which core parts deploy?**  
A: Use `deployNSG`, `deployUDR`, `deployVNet` booleans. If all three are false, Phase 2 is skipped.

***

## 🧾 Changelog Template

Use the following format in PR descriptions:

    ### What changed
    - Add new Landing subscription: <name>
    - Update Identity peering remoteVnetId
    - Fix Bicep optional property access

    ### Why
    - Support new app environment

    ### Validation
    - bicep build OK
    - WHAT-IF OK
    - Peering: waited local/remote VNets, success

    ### Rollback
    - Revert PR #<id>

***

## 🧠 KT Summary

*   **Design**: CAF-aligned hub & spoke across Platform and Landing layers
*   **Pipeline**: Safe sequencing (Platform → Landing → Platform Peerings → Landing Peerings), with **waits** and **retries avoided**
*   **Controls**: Boolean toggles for phases and layers
*   **Resilience**: RG waits, VNet waits, peering isolated in final stages
*   **Extensible**: Add subscriptions by adding param files + variable mapping

***
