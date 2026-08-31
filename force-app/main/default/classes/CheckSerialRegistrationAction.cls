public without sharing class CheckSerialRegistrationAction {

    public class Request {
        @InvocableVariable(label='Serial Number' description='Serial printed on the carton, e.g. SN-00042-1' required=true)
        public String serialNumber;
    }

    public class Result {
        @InvocableVariable(label='Found' description='True when the serial exists in our records')
        public Boolean found;
        @InvocableVariable(label='Asset Id')
        public String assetId;
        @InvocableVariable(label='Product Name')
        public String productName;
        @InvocableVariable(label='Asset Status' description='Shipped or Registered')
        public String assetStatus;
        @InvocableVariable(label='Already Registered')
        public Boolean alreadyRegistered;
        @InvocableVariable(label='Warranty Active')
        public Boolean warrantyActive;
        @InvocableVariable(label='Warranty End Date' description='Readable date, empty when not registered')
        public String warrantyEndDate;
        @InvocableVariable(label='Contact First Name')
        public String contactFirstName;
        @InvocableVariable(label='Contact Id')
        public String contactId;
        @InvocableVariable(label='Message' description='Plain sentence the agent can relay to the customer')
        public String message;
    }

    @InvocableMethod(label='Check Serial Registration' description='Looks up a product serial number and reports whether it exists, whether the warranty is already registered, and until when it is covered.' category='WarrantyDesk')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.found = false;
            r.alreadyRegistered = false;
            r.warrantyActive = false;
            r.warrantyEndDate = '';

            Asset a = WarrantyDesk.assetBySerial(req.serialNumber);
            if (a == null) {
                r.message = 'No product found with serial ' + (req.serialNumber == null ? '' : req.serialNumber.trim())
                    + '. Ask the customer to re-check the serial printed near the QR sticker.';
                results.add(r);
                continue;
            }

            r.found = true;
            r.assetId = a.Id;
            r.productName = WarrantyDesk.productLabel(a);
            r.assetStatus = a.Status;
            r.contactId = a.ContactId;
            r.contactFirstName = (a.ContactId != null && a.Contact != null) ? a.Contact.FirstName : null;
            r.alreadyRegistered = (a.Status == WarrantyDesk.STATUS_REGISTERED);
            r.warrantyActive = WarrantyDesk.warrantyActive(a);
            r.warrantyEndDate = WarrantyDesk.prettyDate(a.Warranty_End_Date__c);

            if (!r.alreadyRegistered) {
                r.message = r.productName + ' (serial ' + a.SerialNumber + ') is in our records and not registered yet. Collect the customer name and email, then call Register Warranty.';
            } else if (r.warrantyActive) {
                r.message = r.productName + ' (serial ' + a.SerialNumber + ') is already registered and covered until ' + r.warrantyEndDate + '.';
            } else {
                r.message = r.productName + ' (serial ' + a.SerialNumber + ') is registered but the warranty ended on ' + r.warrantyEndDate + '. No warranty claim can be filed.';
            }
            results.add(r);
        }
        return results;
    }
}