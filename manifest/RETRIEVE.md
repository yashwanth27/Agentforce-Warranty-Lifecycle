# Retrieving WarrantyDesk from the org

## 1. Authorise the org

```
sf org login web --alias warrantydesk
```

## 2. Main retrieve

```
sf project retrieve start -x manifest\package.xml --target-org warrantydesk
```

This pulls all code, the three objects WarrantyDesk touches, both permission
sets, and the whole Omni-Channel plus messaging chain — including the Apple
`MessagingChannel`, which is the one component that could never be created
or read through the REST/Tooling APIs the system was originally built with.

## 3. The agent — retrieve each type separately

**Do not add these to `package.xml`.** If any one type name is not valid at
API 67, the Metadata API rejects the *entire* manifest and you learn nothing
about the rest. Run them individually so each succeeds or fails alone:

```
sf project retrieve start --metadata AiAuthoringBundle   --target-org warrantydesk
sf project retrieve start --metadata Bot                 --target-org warrantydesk
sf project retrieve start --metadata GenAiPlannerBundle  --target-org warrantydesk
sf project retrieve start --metadata GenAiPlugin         --target-org warrantydesk
```

The org holds all of these for this agent:

| What exists | Name |
|-------------|------|
| `BotDefinition` | `Warranty_Claims_Agent` |
| `GenAiPlannerDefinition` x4 | `Warranty_Claims_Agent_v1` .. `_v4` (**v4 is active**) |
| Authoring bundle | `Warranty_Claims_Agent` |

`AiAuthoringBundle` is the Agent Script source — the 538-line
`definition.agent`. `Bot` and `GenAiPlannerBundle` are the compiled runtime
artifacts. Whichever of these retrieve cleanly, keep. Whichever error with an
unknown-type message simply are not source-trackable at this API version.

Add the successful ones to `package.xml` afterwards, e.g.

```xml
<types>
    <members>*</members>
    <name>AiAuthoringBundle</name>
</types>
```

## 4. Two things the retrieve will NOT give you

Both exist only in the repo, because neither could be created through the
APIs the system was built with — but both deploy fine as source metadata.

| Missing | Why | Consequence if left out |
|---------|-----|------------------------|
| `Case.Warranty_Claim_Process` (BusinessProcess) | Tooling API refuses to create one; the live org's record type has none | Record type deploys without a support process |
| `<servicePresenceStatusAccesses>` in `WarrantyDesk_Support_Agent` | No REST or Tooling endpoint can grant it | Presence-status access stays a manual Setup click |

Copy both from `warrantydesk-agentforce.zip` on the Desktop if you want them.

## 5. What is deliberately not retrieved

| Component | Why |
|-----------|-----|
| `Profile` | Org-specific and destructive to overwrite. Case record-type visibility stays a manual step |
| `Layout`, `EmailTemplate` | 28 stock sample templates and dozens of standard layouts — noise, nothing WarrantyDesk changed |
| Queue membership | Depends on who works at your company |

## 6. Expect some noise

`CustomObject:Case` returns every custom field on Case, including the stock
sample ones (`EngineeringReqNumber`, `PotentialLiability`, `Product`,
`SLAViolation`). `ApexClass` with a wildcard also returns
`CreateLeadFromChatAction`, which belongs to an earlier lead-creation agent,
and `Bot`/`GenAiPlannerBundle` will include `Claude_Test_Agent`.

None of that is WarrantyDesk. Delete what you don't want after the first
retrieve, or leave it — it is a true picture of the org either way.

## 7. Deploying elsewhere

Once `force-app/` is populated, this same manifest deploys:

```
sf project deploy start -x manifest\package.xml --target-org <other>
```

One caveat: the Apple `MessagingChannel` will not produce a working channel
in a different org. Its business ID is issued by Apple and bound to your
registration — a new org needs its own Apple handshake first. Retrieving it
gives you a versioned record of the routing config, not portability.
