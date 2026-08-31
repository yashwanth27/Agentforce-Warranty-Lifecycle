# WarrantyDesk — Agentforce Warranty Lifecycle

**Warranty registration and claims on Salesforce Agentforce, delivered over
Apple Messages for Business.**

A customer buys a pump. The order is activated. They get an email with a QR
code. They point their iPhone camera at it, Messages opens a conversation
with the business, and the whole warranty lifecycle — registration, claims,
status, pickup scheduling, escalation to a human — happens in that one
thread. No app to install, no portal login, no forms.

This repository is the deployable source for that system, retrieved from the
org it runs in, plus three deep-dive documents on how every piece works and
why.

---

## Contents

| Path | What's in it |
|------|--------------|
| `force-app/main/default/` | All Salesforce metadata, SFDX source format |
| `manifest/package.xml` | Retrieve/deploy manifest |
| `manifest/RETRIEVE.md` | How to pull the system down from an org |
| `docs/` | Three standalone HTML documents — open in any browser |
| `scripts/seed-data.apex` | Test data for a fresh org |
| `scripts/post-deploy-checklist.md` | The manual steps the Metadata API can't do |
| `ROADMAP.md` | What's next, in priority order |

### The three documents

Self-contained HTML — no server, no build step, no internet needed.

- **`docs/WarrantyDesk-Technical-Reference.html`** — 17 sections. Every field,
  class, permission, queue and agent instruction, with the reasoning behind
  each. **Start here.**
- **`docs/WarrantyDesk-Execution-Trace.html`** — six end-to-end journeys traced
  call by call, from the customer's first message to the database write.
- **`docs/WarrantyDesk-Call-Graph-Explorer.html`** — interactive graph. Click a
  node to see what calls it and what it calls.

GitHub won't render HTML in file preview. Clone and open locally, or enable
Pages (Settings → Pages → `main` / `/docs`).

---

## How it works

```
Order activated
      │
      ▼
OrderWarrantyTrigger ──► OrderWarrantyService
                              ├─ creates one Asset per order line
                              │  (serial SN-{OrderNumber}-{n})
                              ├─ builds an Apple deep link
                              ├─ renders it as a QR code
                              └─ emails it to the buyer
                                        │
                                        ▼
                          Customer scans → Apple Messages
                                        │
                                        ▼
              MessagingChannel (AppleBusinessChat, Enhanced)
                    SessionHandlerId ──► Warranty Claims Agent
                                        │
                        ┌───────────────────────────────┐
                        │  warranty_router (start)      │
                        ├───────────────────────────────┤
                        │  registration     ──► CheckSerialRegistrationAction
                        │                   ──► RegisterWarrantyAction
                        │  claim_intake     ──► GetCustomerAssetsAction
                        │                   ──► CreateWarrantyClaimAction
                        │  claim_status     ──► GetClaimStatusAction
                        │  pickup_scheduling──► SchedulePickupAction
                        │  escalation       ──► Warranty Support queue
                        │  off_topic / ambiguous_question
                        └───────────────────────────────┘
                                        │
                                        ▼
                            Asset / Case records
```

Every agent action is a single `@InvocableMethod` class. The agent's reasoning
layer decides which to call; the Apex does the data work and returns a
structured result the agent reads back to the customer.

### The eight Apex classes

| Class | Role |
|-------|------|
| `WarrantyDesk` | Shared helpers — serial lookup, warranty date math, name matching |
| `OrderWarrantyService` | Order-activation side: assets, deep link, QR, email |
| `CheckSerialRegistrationAction` | Is this serial real, and already registered? |
| `RegisterWarrantyAction` | Writes warranty months and end date onto the Asset |
| `GetCustomerAssetsAction` | Everything this customer owns still in warranty |
| `CreateWarrantyClaimAction` | Files the Case |
| `GetClaimStatusAction` | Reads back claim stage |
| `SchedulePickupAction` | Writes the pickup slot onto the Case |

All `without sharing` — they run as the agent's user, and the permission set
is what actually constrains them.

---

## Deploy

```bash
sf org login web --alias warrantydesk
sf project deploy start -x manifest/package.xml --target-org warrantydesk
```

Then work through **[`scripts/post-deploy-checklist.md`](scripts/post-deploy-checklist.md)**.
Don't skip it — several steps, the agent's permission set assignment above
all, fail *silently* if missed: the conversation just stalls with no error.

Validate first if deploying somewhere that matters:

```bash
sf project deploy start -x manifest/package.xml --dry-run --target-org warrantydesk
```

### Two hand-authored additions

Everything else here was retrieved from the org. These two were added by hand,
because neither can be created through any REST or Tooling API — but both
deploy fine as source metadata:

1. **`objects/Case/businessProcesses/Warranty_Claim_Process`** and the
   `<businessProcess>` reference on the record type. The live org's record
   type has none; the Tooling API refuses to create one.
2. **`<servicePresenceStatusAccesses>`** in `WarrantyDesk_Support_Agent`,
   which removes a manual Setup click.

Both are unverified by an actual deploy — run the `--dry-run` above before
relying on them.

### What won't travel to another org

The Apple `MessagingChannel` is in the source, but its business ID is issued
by Apple and bound to this registration. A different org needs its own Apple
handshake before a channel can exist. Treat the retrieved file as a versioned
record of the routing config, not as portable setup.

---

## Three rules learned the hard way

All three came from live conversations failing in ways that weren't obvious.
The docs cover them at length.

> **1. An ordered procedure written as prose is a suggestion.**
> Instructions saying "confirm the serial, *then* register it" do not enforce
> ordering. Anything that must happen before an action fires belongs in that
> action's `available when` gate. Prose is advice to the planner; a gate is a
> wall.

> **2. An ungated variable dependency doesn't fail loudly — it fabricates a
> plausible negative.**
> A *gated* missing variable stops the planner, which then asks the customer
> for it. An *ungated* one produces an empty parameter, the Apex returns "no
> results", and the agent confidently tells the customer they own nothing.
> Wrong, specific, and completely believable. It took a transcript diff to
> catch.

> **3. The agent doesn't run as you.**
> Everything tested clean through the REST endpoint as System Administrator,
> then hung on the first real conversation — the agent's dedicated running
> user had zero `SetupEntityAccess` rows and couldn't execute a single Apex
> class. Worse, the Atlas planner validates *all* actions across *all*
> subagents at session start, so one missing grant disabled the entire agent.
> Always test in the live channel, as the agent user.

---

## Current state

**Proven live:** order activation → asset creation → QR email → Apple
Messages → warranty registration.

**Built, not yet proven on the current agent version:** claim intake, claim
status, pickup scheduling, escalation. The Apex is verified; the
conversational path hasn't had a clean live run since the v4 rewrite.

**Known gaps** — full list with priorities in `ROADMAP.md`:

- **No Apex test classes.** Zero coverage. Blocks any production deployment.
- **Photo capture declared but unwired** — no `ContentVersion` id reaches
  `CreateWarrantyClaimAction`.
- **No rep-side workflow** — no approval process, no notification on filing.
- **Pickup slots are fictional** — offered from agent instructions, with no
  availability system behind them.
- **`APPLE_BUSINESS_ID` hard-coded** in `OrderWarrantyService`. Should be
  Custom Metadata.

---

## Org noise

This was retrieved with wildcards, so some of what's here isn't WarrantyDesk:
`CreateLeadFromChatAction`, `Claude_Test_Agent`, `Copilot_for_Salesforce`,
`EmployeeCopilotPlanner`, and Case's stock sample fields
(`EngineeringReqNumber`, `PotentialLiability`, `SLAViolation`). All real org
state, none of it part of this system.

The Apple business ID `45b81efd-1d6e-405a-9547-7d8e8c34b8a8` appears in
`OrderWarrantyService.cls` and the docs. Deliberately not scrubbed — but if
you fork this, replace it, or your customers' QR codes open a conversation
with someone else's business.

---

## License

MIT — see `LICENSE`.
