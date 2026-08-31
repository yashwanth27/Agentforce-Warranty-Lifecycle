public without sharing class GetCustomerAssetsAction {

    public class Request {
        @InvocableVariable(label='Contact Id' description='Contact behind this Apple Messages conversation')
        public String contactId;
        @InvocableVariable(label='Messaging End User Id' description='Used to resolve the Contact when Contact Id is unknown')
        public String messagingEndUserId;
        @InvocableVariable(label='Customer Email' description='Fallback identification when neither id is available')
        public String customerEmail;
    }

    public class Result {
        @InvocableVariable(label='Asset Count')
        public Decimal assetCount;
        @InvocableVariable(label='Covered Count' description='How many of them are still under warranty')
        public Decimal coveredCount;
        @InvocableVariable(label='Any Warranty Active')
        public Boolean anyWarrantyActive;
        @InvocableVariable(label='Single Covered Asset Id' description='Populated only when exactly one asset is under warranty, so the agent can skip the picker')
        public String singleCoveredAssetId;
        @InvocableVariable(label='Single Covered Asset Label')
        public String singleCoveredAssetLabel;
        @InvocableVariable(label='Asset Summary' description='One line per product, ready to render as an Apple Messages list picker')
        public String assetSummary;
        @InvocableVariable(label='Resolved Contact Id')
        public String resolvedContactId;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Get Customer Assets' description='Lists the registered products belonging to this customer and flags which are still under warranty. Call this before offering to file a claim.' category='WarrantyDesk')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            Integer total = 0;
            Integer covered = 0;
            r.anyWarrantyActive = false;
            r.assetSummary = '';

            Id cid = null;
            if (String.isNotBlank(req.contactId)) {
                try { cid = Id.valueOf(req.contactId.trim()); } catch (Exception e) { cid = null; }
            }
            if (cid == null && String.isNotBlank(req.messagingEndUserId)) {
                cid = WarrantyDesk.contactFromMessaging(req.messagingEndUserId.trim());
            }
            if (cid == null && String.isNotBlank(req.customerEmail)) {
                String em = req.customerEmail.trim();
                List<Contact> cs = [SELECT Id FROM Contact WHERE Email = :em LIMIT 1];
                if (!cs.isEmpty()) { cid = cs[0].Id; }
            }

            if (cid == null) {
                r.assetCount = 0;
                r.coveredCount = 0;
                r.message = 'Could not identify the customer. Ask for the serial number printed near the QR sticker instead.';
                results.add(r);
                continue;
            }
            r.resolvedContactId = cid;

            List<Asset> assets = WarrantyDesk.assetsForContact(cid);
            List<String> lines = new List<String>();
            Asset onlyCovered = null;
            for (Asset a : assets) {
                if (a.Status != WarrantyDesk.STATUS_REGISTERED) { continue; }
                total++;
                Boolean live = WarrantyDesk.warrantyActive(a);
                if (live) {
                    covered++;
                    onlyCovered = (covered == 1) ? a : onlyCovered;
                }
                lines.add(WarrantyDesk.productLabel(a) + ' | serial ' + a.SerialNumber
                    + ' | ' + (live ? 'covered until ' + WarrantyDesk.prettyDate(a.Warranty_End_Date__c)
                                    : 'warranty ended ' + WarrantyDesk.prettyDate(a.Warranty_End_Date__c))
                    + ' | assetId ' + a.Id);
            }

            r.assetCount = total;
            r.coveredCount = covered;
            r.assetSummary = String.join(lines, '\n');
            r.anyWarrantyActive = (covered > 0);
            if (covered == 1 && onlyCovered != null) {
                r.singleCoveredAssetId = onlyCovered.Id;
                r.singleCoveredAssetLabel = WarrantyDesk.productLabel(onlyCovered) + ' (serial ' + onlyCovered.SerialNumber + ')';
            }

            if (total == 0) {
                r.message = 'No registered product on this account. Offer to register one - ask for the serial near the QR sticker.';
            } else if (covered == 0) {
                r.message = 'The customer has registered products but none are still under warranty. Do not file a claim - offer paid repair instead.';
            } else if (covered == 1) {
                r.message = 'Exactly one product is under warranty: ' + r.singleCoveredAssetLabel + '. Proceed straight to the defect question.';
            } else {
                r.message = 'Several products are under warranty. Show the list and let the customer pick one before filing a claim.';
            }
            results.add(r);
        }
        return results;
    }
}