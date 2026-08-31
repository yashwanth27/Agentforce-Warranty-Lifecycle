/**
 * Shared helpers for the WarrantyDesk Apple Messages agent.
 */
public without sharing class WarrantyDesk {

    public static final String CLAIM_RT_DEVNAME = 'Warranty_Claim';
    public static final String STATUS_SHIPPED = 'Shipped';
    public static final String STATUS_REGISTERED = 'Registered';

    /** Claim record type id, or null when the running user has no visibility yet. */
    public static Id claimRecordTypeId() {
        Schema.RecordTypeInfo rt = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(CLAIM_RT_DEVNAME);
        if (rt == null || !rt.isAvailable()) {
            return null;
        }
        return rt.getRecordTypeId();
    }

    public static Asset assetBySerial(String serial) {
        if (String.isBlank(serial)) { return null; }
        String s = serial.trim();
        List<Asset> rows = [
            SELECT Id, Name, SerialNumber, Status, PurchaseDate, Warranty_Months__c, Warranty_End_Date__c,
                   ContactId, Contact.FirstName, Contact.LastName, Contact.Email, AccountId,
                   Product2Id, Product2.Name, Order__c
            FROM Asset WHERE SerialNumber = :s LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static List<Asset> assetsForContact(Id contactId) {
        if (contactId == null) { return new List<Asset>(); }
        return [
            SELECT Id, Name, SerialNumber, Status, PurchaseDate, Warranty_Months__c, Warranty_End_Date__c,
                   ContactId, AccountId, Product2Id, Product2.Name
            FROM Asset WHERE ContactId = :contactId ORDER BY CreatedDate DESC LIMIT 50
        ];
    }

    public static Boolean warrantyActive(Asset a) {
        return a != null
            && a.Status == STATUS_REGISTERED
            && a.Warranty_End_Date__c != null
            && a.Warranty_End_Date__c >= Date.today();
    }

    public static String productLabel(Asset a) {
        if (a == null) { return ''; }
        if (a.Product2Id != null && a.Product2 != null && String.isNotBlank(a.Product2.Name)) {
            return a.Product2.Name;
        }
        return String.isBlank(a.Name) ? 'your product' : a.Name;
    }

    /** 30 Aug 2027 - readable in a chat bubble, unambiguous across locales. */
    public static String prettyDate(Date d) {
        if (d == null) { return ''; }
        List<String> months = new List<String>{'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
        return String.valueOf(d.day()) + ' ' + months[d.month() - 1] + ' ' + String.valueOf(d.year());
    }

    public static Boolean looksLikeEmail(String e) {
        if (String.isBlank(e)) { return false; }
        return Pattern.matches('^[\\w.%+-]+@[\\w.-]+\\.[A-Za-z]{2,}$', e.trim());
    }

    /** Loose name check - first OR last name token must appear, so 'Ramesh' matches 'Ramesh Patil'. */
    public static Boolean nameMatches(String supplied, Contact c) {
        if (c == null || String.isBlank(supplied)) { return false; }
        String given = supplied.toLowerCase().trim();
        String first = c.FirstName == null ? '' : c.FirstName.toLowerCase();
        String last = c.LastName == null ? '' : c.LastName.toLowerCase();
        if (String.isNotBlank(first) && (given.contains(first) || first.contains(given))) { return true; }
        if (String.isNotBlank(last) && (given.contains(last) || last.contains(given))) { return true; }
        return false;
    }

    public static Id contactFromMessaging(String endUserId) {
        if (String.isBlank(endUserId)) { return null; }
        List<MessagingEndUser> rows = [SELECT ContactId FROM MessagingEndUser WHERE Id = :endUserId LIMIT 1];
        return rows.isEmpty() ? null : rows[0].ContactId;
    }
}