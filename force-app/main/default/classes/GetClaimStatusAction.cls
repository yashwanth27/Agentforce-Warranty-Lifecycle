public without sharing class GetClaimStatusAction {

    public class Request {
        @InvocableVariable(label='Case Number' description='Claim reference such as 00001042, if the customer quoted one')
        public String caseNumber;
        @InvocableVariable(label='Contact Id')
        public String contactId;
        @InvocableVariable(label='Messaging End User Id')
        public String messagingEndUserId;
    }

    public class Result {
        @InvocableVariable(label='Found')
        public Boolean found;
        @InvocableVariable(label='Claim Count')
        public Decimal claimCount;
        @InvocableVariable(label='Case Number')
        public String caseNumber;
        @InvocableVariable(label='Claim Stage')
        public String claimStage;
        @InvocableVariable(label='Defect Category')
        public String defectCategory;
        @InvocableVariable(label='Product Name')
        public String productName;
        @InvocableVariable(label='Filed On')
        public String filedOn;
        @InvocableVariable(label='Pickup Slot')
        public String pickupSlot;
        @InvocableVariable(label='Claim Summary' description='One line per claim when the customer has several')
        public String claimSummary;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Get Claim Status' description='Reports the current stage of a warranty claim, by claim reference or for the customer in this conversation.' category='WarrantyDesk')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.found = false;
            r.claimCount = 0;
            r.claimSummary = '';

            List<Case> claims = new List<Case>();
            if (String.isNotBlank(req.caseNumber)) {
                String cn = req.caseNumber.trim().replaceAll('[^0-9]', '');
                if (String.isNotBlank(cn)) {
                    claims = [
                        SELECT Id, CaseNumber, Claim_Stage__c, Defect_Category__c, CreatedDate, Pickup_Slot__c,
                               Asset.Name, Asset.SerialNumber, Asset.Product2.Name
                        FROM Case
                        WHERE Claim_Stage__c != null AND CaseNumber LIKE :('%' + cn)
                        ORDER BY CreatedDate DESC LIMIT 10
                    ];
                }
            }

            if (claims.isEmpty()) {
                Id cid = null;
                if (String.isNotBlank(req.contactId)) {
                    try { cid = Id.valueOf(req.contactId.trim()); } catch (Exception e) { cid = null; }
                }
                if (cid == null && String.isNotBlank(req.messagingEndUserId)) {
                    cid = WarrantyDesk.contactFromMessaging(req.messagingEndUserId.trim());
                }
                if (cid != null) {
                    claims = [
                        SELECT Id, CaseNumber, Claim_Stage__c, Defect_Category__c, CreatedDate, Pickup_Slot__c,
                               Asset.Name, Asset.SerialNumber, Asset.Product2.Name
                        FROM Case
                        WHERE ContactId = :cid AND Claim_Stage__c != null
                        ORDER BY CreatedDate DESC LIMIT 10
                    ];
                }
            }

            if (claims.isEmpty()) {
                r.message = 'No warranty claim found for this customer. Offer to file one if their product is still covered.';
                results.add(r);
                continue;
            }

            r.found = true;
            r.claimCount = claims.size();
            Case top = claims[0];
            r.caseNumber = top.CaseNumber;
            r.claimStage = top.Claim_Stage__c;
            r.defectCategory = top.Defect_Category__c;
            r.productName = (top.Asset != null)
                ? (top.Asset.Product2 != null && String.isNotBlank(top.Asset.Product2.Name) ? top.Asset.Product2.Name : top.Asset.Name)
                : '';
            r.filedOn = top.CreatedDate.format('d MMM yyyy, h:mm a');
            r.pickupSlot = (top.Pickup_Slot__c == null) ? '' : top.Pickup_Slot__c.format('EEEE d MMM, h:mm a');

            List<String> lines = new List<String>();
            for (Case c : claims) {
                lines.add(c.CaseNumber + ' | ' + c.Claim_Stage__c + ' | ' + c.Defect_Category__c
                    + ' | filed ' + c.CreatedDate.format('d MMM yyyy'));
            }
            r.claimSummary = String.join(lines, '\n');
            r.message = 'Claim ' + r.caseNumber + ' is currently ' + r.claimStage + ', filed ' + r.filedOn + '.';
            results.add(r);
        }
        return results;
    }
}