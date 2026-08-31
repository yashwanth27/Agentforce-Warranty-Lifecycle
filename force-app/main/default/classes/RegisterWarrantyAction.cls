public without sharing class RegisterWarrantyAction {

    public class Request {
        @InvocableVariable(label='Serial Number' required=true)
        public String serialNumber;
        @InvocableVariable(label='Customer Full Name' required=true)
        public String customerName;
        @InvocableVariable(label='Customer Email' required=true)
        public String customerEmail;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Needs Escalation' description='True when identity could not be verified against the order Contact')
        public Boolean needsEscalation;
        @InvocableVariable(label='Product Name')
        public String productName;
        @InvocableVariable(label='Serial Number')
        public String serialNumber;
        @InvocableVariable(label='Warranty End Date')
        public String warrantyEndDate;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Register Warranty' description='Verifies the supplied name and email against the Contact on the order, then activates the warranty on that serial and returns the coverage end date.' category='WarrantyDesk')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.success = false;
            r.needsEscalation = false;
            r.serialNumber = req.serialNumber;
            r.warrantyEndDate = '';

            Asset a = WarrantyDesk.assetBySerial(req.serialNumber);
            if (a == null) {
                r.message = 'That serial is not in our records. Ask the customer to re-check the serial near the QR sticker.';
                results.add(r);
                continue;
            }
            r.productName = WarrantyDesk.productLabel(a);

            if (a.Status == WarrantyDesk.STATUS_REGISTERED) {
                r.warrantyEndDate = WarrantyDesk.prettyDate(a.Warranty_End_Date__c);
                r.message = 'This unit is already registered and covered until ' + r.warrantyEndDate + '. Offer to file a claim or check claim status instead.';
                results.add(r);
                continue;
            }

            if (!WarrantyDesk.looksLikeEmail(req.customerEmail)) {
                r.message = 'That email does not look valid. Ask the customer to retype it, for example name@example.com.';
                results.add(r);
                continue;
            }

            Contact c = null;
            if (a.ContactId != null) {
                c = [SELECT Id, FirstName, LastName, Email FROM Contact WHERE Id = :a.ContactId LIMIT 1];
            }

            if (c != null) {
                Boolean emailOk = String.isNotBlank(c.Email)
                    && c.Email.toLowerCase().trim() == req.customerEmail.toLowerCase().trim();
                Boolean nameOk = WarrantyDesk.nameMatches(req.customerName, c);
                if (!emailOk || !nameOk) {
                    r.needsEscalation = true;
                    r.message = 'The name or email does not match the person who placed this order. Do not register. Offer to connect the customer to the support team.';
                    results.add(r);
                    continue;
                }
            }

            Decimal months = (a.Warranty_Months__c == null) ? 12 : a.Warranty_Months__c;
            Date purchase = Date.today();
            Date ends = purchase.addMonths(Integer.valueOf(months));

            Asset upd = new Asset(
                Id = a.Id,
                Status = WarrantyDesk.STATUS_REGISTERED,
                PurchaseDate = purchase,
                Warranty_Months__c = months,
                Warranty_End_Date__c = ends
            );
            try {
                update upd;
            } catch (DmlException e) {
                r.message = 'Could not complete the registration: ' + e.getDmlMessage(0);
                results.add(r);
                continue;
            }

            if (c != null) {
                Boolean touch = false;
                Contact cu = new Contact(Id = c.Id);
                if (String.isBlank(c.Email)) { cu.Email = req.customerEmail.trim(); touch = true; }
                if (touch) { update cu; }
            }

            r.success = true;
            r.warrantyEndDate = WarrantyDesk.prettyDate(ends);
            r.message = 'Registered. ' + r.productName + ', serial ' + a.SerialNumber + ', covered until ' + r.warrantyEndDate + '.';
            results.add(r);
        }
        return results;
    }
}