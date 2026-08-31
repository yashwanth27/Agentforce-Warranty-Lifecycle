public without sharing class CreateWarrantyClaimAction {

    private static final Set<String> CATEGORIES = new Set<String>{
        'Not Working', 'Physical Damage', 'Missing Parts', 'Wrong Item', 'Other'
    };

    public class Request {
        @InvocableVariable(label='Asset Id' description='Asset the claim is filed against')
        public String assetId;
        @InvocableVariable(label='Serial Number' description='Alternative to Asset Id')
        public String serialNumber;
        @InvocableVariable(label='Defect Category' description='Not Working, Physical Damage, Missing Parts, Wrong Item or Other' required=true)
        public String defectCategory;
        @InvocableVariable(label='Description' description='What the customer described, verbatim' required=true)
        public String description;
        @InvocableVariable(label='Content Document Id' description='Photo the customer sent, if already stored as a file')
        public String contentDocumentId;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Case Number')
        public String caseNumber;
        @InvocableVariable(label='Case Id')
        public String caseId;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Create Warranty Claim' description='Files a warranty claim case against a covered asset. Refuses if the warranty has expired. Only call after the defect category, a description and a photo have been collected.' category='WarrantyDesk')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.success = false;

            Asset a = null;
            if (String.isNotBlank(req.assetId)) {
                List<Asset> rows = [
                    SELECT Id, Name, SerialNumber, Status, Warranty_End_Date__c, ContactId, AccountId,
                           Product2Id, Product2.Name
                    FROM Asset WHERE Id = :req.assetId.trim() LIMIT 1
                ];
                a = rows.isEmpty() ? null : rows[0];
            }
            if (a == null && String.isNotBlank(req.serialNumber)) {
                a = WarrantyDesk.assetBySerial(req.serialNumber);
            }
            if (a == null) {
                r.message = 'Could not identify the product. Ask for the serial number before filing.';
                results.add(r);
                continue;
            }

            if (!WarrantyDesk.warrantyActive(a)) {
                r.message = 'Warranty is not active for serial ' + a.SerialNumber
                    + (a.Warranty_End_Date__c == null ? ' (not registered).' : ' - it ended on ' + WarrantyDesk.prettyDate(a.Warranty_End_Date__c) + '.')
                    + ' Do not file a claim. Offer paid repair options instead.';
                results.add(r);
                continue;
            }

            String category = String.isBlank(req.defectCategory) ? 'Other' : req.defectCategory.trim();
            if (!CATEGORIES.contains(category)) { category = 'Other'; }

            if (String.isBlank(req.description) || req.description.trim().length() < 15) {
                r.message = 'The description is too short. Ask the customer for a line or two more detail before filing.';
                results.add(r);
                continue;
            }

            Case claim = new Case(
                Subject = 'Warranty claim - ' + WarrantyDesk.productLabel(a) + ' (' + a.SerialNumber + ') - ' + category,
                Description = req.description.trim(),
                AssetId = a.Id,
                ContactId = a.ContactId,
                AccountId = a.AccountId,
                Defect_Category__c = category,
                Claim_Stage__c = 'Under Review',
                Status = 'New',
                Priority = 'Medium'
            );
            Id rtId = WarrantyDesk.claimRecordTypeId();
            if (rtId != null) { claim.RecordTypeId = rtId; }

            try {
                insert claim;
            } catch (DmlException e) {
                r.message = 'Could not file the claim: ' + e.getDmlMessage(0);
                results.add(r);
                continue;
            }

            if (String.isNotBlank(req.contentDocumentId)) {
                try {
                    insert new ContentDocumentLink(
                        ContentDocumentId = req.contentDocumentId.trim(),
                        LinkedEntityId = claim.Id,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    );
                } catch (Exception e) {
                    // photo relink is best effort - the claim itself is already filed
                }
            }

            Case saved = [SELECT Id, CaseNumber FROM Case WHERE Id = :claim.Id LIMIT 1];
            r.success = true;
            r.caseId = saved.Id;
            r.caseNumber = saved.CaseNumber;
            r.message = 'Claim ' + saved.CaseNumber + ' filed and under review. Tell the customer they will be updated in this conversation.';
            results.add(r);
        }
        return results;
    }
}