# Post-deploy checklist

Everything in `manifest/package.xml` deploys with the Metadata API. What
follows is the work that **cannot** be expressed as source-tracked metadata,
in the order it has to happen.

Times are rough; the whole list is about 25 minutes on a fresh org.

---

## 0. Prerequisites

- The target org has **Agentforce (Einstein) enabled** with at least one
  Agentforce Service Agent licence.
- **Messaging for In-App and Web / Enhanced Messaging** is enabled
  (Setup → Messaging Settings).
- **Omni-Channel** is enabled (Setup → Omni-Channel Settings →
  *Enable Omni-Channel*).
- **Einstein Generative AI** is turned on and the org has accepted the
  Einstein Trust Layer terms.

If any of these are off, the deploy still succeeds but the agent will not
run.

---

## 1. Deploy the metadata (2 min)

```bash
sf project deploy start -x manifest/package.xml --target-org <alias>
```

The `AiAuthoringBundle` deploys the agent **as a draft version**. It is not
active yet — step 4 handles that.

---

## 2. Assign the permission sets (1 min)

```bash
# Every human who works claims
sf org assign permset -n WarrantyDesk_Access        --target-org <alias>
sf org assign permset -n WarrantyDesk_Support_Agent --target-org <alias>

# The agent's own running user — THIS IS THE ONE THAT BREAKS SILENTLY
sf org assign permset -n WarrantyDesk_Access \
   -b <agent-running-user-username> --target-org <alias>
```

> **Read this twice.** The agent runs as its own dedicated user (an
> `@<orgid>.ext` address, findable at Setup → Users, filtered to the
> *Einstein Agent User* licence). If that user is not granted
> `WarrantyDesk_Access`, the Atlas planner finds it cannot execute any of
> the eight Apex actions and **disables the entire agent at session
> start** — no error to the customer, the conversation just stalls after
> the first reply. This cost us a full debugging round. See
> *Technical Reference → Testing lessons*.

`WarrantyDesk_Support_Agent` includes `<servicePresenceStatusAccesses>`,
so presence-status access is granted by the deploy and does **not** need a
manual Setup click.

---

## 3. Make the Case record type visible (2 min)

Record type *visibility* is a profile property, and profiles are
deliberately not in this package (they differ per org and overwriting them
is destructive).

Setup → Object Manager → **Case** → Record Types → make sure
**Warranty Claim** is assigned on every profile that will file claims,
including the **agent's running user's profile**.

Until this is done, `CreateWarrantyClaimAction` still files the case — but
with a null `RecordTypeId`, so it will not show the warranty page layout or
appear in record-type-filtered list views. Nothing errors.

---

## 4. Publish and activate the agent (3 min)

Setup → **Agentforce Agents** → *Warranty Claims Agent*.

1. Open the agent, click **Open in Builder**.
2. Confirm the eight Apex actions appear under each subagent and none show
   a red "action not found" state.
3. **Publish** the version. Publish is the real validator — it type-checks
   every action signature against the live Apex. If an output type
   mismatches (e.g. `Integer` where the planner expects a number), publish
   fails here rather than at runtime.
4. **Activate** the published version.

---

## 5. Wire the Apple Messages channel (10 min)

The `MessagingChannel` for Apple Messages for Business **cannot** be
deployed as metadata — it is created by the Apple registration handshake
and carries an Apple-issued business ID.

1. Register (or reuse) your Apple Messages for Business account at
   [register.apple.com/business-chat](https://register.apple.com/business-chat)
   and link it to this org.
2. Setup → **Messaging** → *New Channel* → **Apple Messages for Business**.
   Salesforce fills the developer name as
   `APPLEBUSINESSCHAT_US_<business-id-with-underscores>`.
3. Set:
   - **Routing Type** → *Agentforce* (this writes `SessionHandlerId`)
   - **Agent** → *Warranty Claims Agent*
   - **Fallback Queue** → *Warranty Support*  ← mandatory, the channel will
     not activate without it
   - **Consent** → *Implicit opt-in*
4. **Activate** the channel.

Note the API only accepts `SessionHandlerId` **or** a
`RoutingType`/`TargetQueueId` pair — never both. Setting the agent is what
you want; the fallback queue covers escalation.

Then update the business ID in the code (step 6).

---

## 6. Point the code at your business ID (1 min)

`OrderWarrantyService.cls` hard-codes the deep link target:

```apex
public static final String APPLE_BUSINESS_ID = '45b81efd-1d6e-405a-9547-7d8e8c34b8a8';
public static final String APPLE_INTENT_ID   = 'register_warranty';
```

Replace `APPLE_BUSINESS_ID` with your own. This value ends up in the QR
code emailed on order activation — the wrong value sends customers to
someone else's Apple business account.

*(A better home for this is Custom Metadata — see `ROADMAP.md`.)*

---

## 7. Configure Omni-Channel presence (2 min)

The queue, routing config and presence status all deploy. What remains:

- Setup → **Omni-Channel** → *Presence Configurations* → confirm your
  support users are on a configuration that includes **Available —
  Messaging**.
- Add **Warranty Support** queue members (users or a public group). The
  queue deploys with its routing config attached but with no members, and
  an escalation into an empty queue waits forever.

---

## 8. Seed test data (1 min)

```bash
sf apex run --file scripts/seed-data.apex --target-org <alias>
```

Edit `CONTACT_EMAIL` at the top of that file first — it must be an address
you can receive mail at.

---

## 9. Smoke test (5 min)

Setup → Agentforce Agents → *Warranty Claims Agent* → **Conversation
Preview**, or send a real message through the Apple channel.

| # | Say this | Expect |
|---|----------|--------|
| 1 | `hi` | greeting + the four things it can do |
| 2 | `register SN-00000100-1` | serial recognised, asks to confirm |
| 3 | `yes` | Asset warranty dates written, confirmation with end date |
| 4 | `my pump is leaking` | asks which product, then for a description |
| 5 | (describe it) | **Case created** — verify in the org, don't take the agent's word |
| 6 | `what's the status of my claim` | reads back the stage |
| 7 | `I want to talk to a person` | routes to Warranty Support queue |

Step 5 is the one that has failed before. The agent used to *narrate*
success without an action result. Open the Case list and confirm a record
exists with a `Defect_Category__c` and `Claim_Stage__c = Under Review`.

---

## What is intentionally not automated

| Thing | Why |
|-------|-----|
| `MessagingChannel` | Created by Apple's registration handshake; carries an Apple-issued ID |
| `MsgChannelLanguageKeyword` | Child of the channel |
| Profile record-type visibility | Profiles are org-specific and destructive to overwrite |
| Queue membership | Depends on who works at your company |
| Agent publish/activate | Requires the Next-Gen Authoring publish step, which is the validator |
