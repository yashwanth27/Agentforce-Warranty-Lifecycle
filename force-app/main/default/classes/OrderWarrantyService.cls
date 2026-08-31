/**
 * Fires when an Order is activated: mints one warranty Asset per unit ordered and
 * emails the customer a QR code per serial. Scanning the QR opens Apple Messages
 * with the registration text pre-filled.
 *
 * Apple-only by design - because there is no WhatsApp fallback to branch on, the QR
 * encodes the bcrw.apple.com deep link directly and no redirect page is needed.
 */
public without sharing class OrderWarrantyService {

    /** Apple Business Register business id - matches MessagingChannel.MessagingPlatformKey. */
    public static final String APPLE_BUSINESS_ID = '45b81efd-1d6e-405a-9547-7d8e8c34b8a8';
    public static final String APPLE_INTENT_ID = 'register_warranty';
    public static final Integer DEFAULT_WARRANTY_MONTHS = 12;

    public static String appleDeepLink(String serial) {
        String body = EncodingUtil.urlEncode('Register warranty ' + serial, 'UTF-8');
        return 'https://bcrw.apple.com/urn:biz:' + APPLE_BUSINESS_ID
            + '?biz-intent-id=' + APPLE_INTENT_ID
            + '&body=' + body;
    }

    public static String qrImageUrl(String serial) {
        return 'https://quickchart.io/qr?ecLevel=Q&size=200&text='
            + EncodingUtil.urlEncode(appleDeepLink(serial), 'UTF-8');
    }

    public static void handleActivation(List<Order> orders) {
        Set<Id> orderIds = new Set<Id>();
        for (Order o : orders) {
            if (o.Status == 'Activated' && o.QR_Email_Sent__c != true) {
                orderIds.add(o.Id);
            }
        }
        if (orderIds.isEmpty()) { return; }

        List<Order> full = [
            SELECT Id, OrderNumber, AccountId, BillToContactId, ShipToContactId, QR_Email_Sent__c,
                   (SELECT Id, Product2Id, Quantity FROM OrderItems)
            FROM Order WHERE Id IN :orderIds
        ];

        Set<String> existing = new Set<String>();
        for (Asset a : [SELECT SerialNumber FROM Asset WHERE Order__c IN :orderIds]) {
            existing.add(a.SerialNumber);
        }

        List<Asset> toCreate = new List<Asset>();
        Map<Id, List<String>> serialsByOrder = new Map<Id, List<String>>();

        for (Order o : full) {
            Id contactId = (o.BillToContactId != null) ? o.BillToContactId : o.ShipToContactId;
            Integer seq = 0;
            serialsByOrder.put(o.Id, new List<String>());
            for (OrderItem oi : o.OrderItems) {
                Integer qty = (oi.Quantity == null) ? 1 : Integer.valueOf(oi.Quantity);
                for (Integer i = 0; i < qty; i++) {
                    seq++;
                    String serial = 'SN-' + o.OrderNumber + '-' + String.valueOf(seq);
                    if (existing.contains(serial)) { continue; }
                    toCreate.add(new Asset(
                        Name = 'Warranty ' + serial,
                        SerialNumber = serial,
                        Status = WarrantyDesk.STATUS_SHIPPED,
                        AccountId = o.AccountId,
                        ContactId = contactId,
                        Product2Id = oi.Product2Id,
                        Order__c = o.Id,
                        Warranty_Months__c = DEFAULT_WARRANTY_MONTHS
                    ));
                    serialsByOrder.get(o.Id).add(serial);
                }
            }
        }

        if (!toCreate.isEmpty()) { insert toCreate; }

        List<Order> stamp = new List<Order>();
        for (Order o : full) { stamp.add(new Order(Id = o.Id, QR_Email_Sent__c = true)); }
        if (!stamp.isEmpty()) { update stamp; }

        sendQrEmails(full, serialsByOrder);
    }

    private static void sendQrEmails(List<Order> orders, Map<Id, List<String>> serialsByOrder) {
        Map<Id, Contact> contacts = new Map<Id, Contact>();
        Set<Id> cids = new Set<Id>();
        for (Order o : orders) {
            if (o.BillToContactId != null) { cids.add(o.BillToContactId); }
            else if (o.ShipToContactId != null) { cids.add(o.ShipToContactId); }
        }
        if (!cids.isEmpty()) {
            contacts = new Map<Id, Contact>([SELECT Id, FirstName, Email FROM Contact WHERE Id IN :cids]);
        }

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        for (Order o : orders) {
            Id cid = (o.BillToContactId != null) ? o.BillToContactId : o.ShipToContactId;
            Contact c = (cid == null) ? null : contacts.get(cid);
            List<String> serials = serialsByOrder.get(o.Id);
            if (c == null || String.isBlank(c.Email) || serials == null || serials.isEmpty()) { continue; }

            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setToAddresses(new List<String>{ c.Email });
            m.setSubject('Register the warranty on order ' + o.OrderNumber);
            m.setSaveAsActivity(false);
            m.setHtmlBody(buildHtml(o, c, serials));
            mails.add(m);
        }
        if (mails.isEmpty()) { return; }
        try {
            Messaging.sendEmail(mails, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WarrantyDesk QR email suppressed: ' + e.getMessage());
        }
    }

    private static String buildHtml(Order o, Contact c, List<String> serials) {
        String greeting = String.isBlank(c.FirstName) ? 'Hello' : 'Hi ' + c.FirstName;
        String html = '<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#1d1d1f;max-width:520px">';
        html += '<p>' + greeting + ',</p>';
        html += '<p>Your order <strong>' + o.OrderNumber + '</strong> is on its way. '
             + 'Scan the code below on your iPhone to register the warranty - it opens Messages with everything filled in, '
             + 'and you just tap send.</p>';
        for (String s : serials) {
            html += '<div style="margin:24px 0;padding:16px;border:1px solid #e5e5e7;border-radius:12px;text-align:center">';
            html += '<div style="font-size:13px;color:#6e6e73;margin-bottom:8px">Serial ' + s + '</div>';
            html += '<img src="' + qrImageUrl(s) + '" alt="Register warranty for ' + s + '" width="200" height="200" />';
            html += '<div style="margin-top:10px"><a href="' + appleDeepLink(s) + '" style="color:#0071e3;text-decoration:none;font-size:14px">Or tap here to open Messages</a></div>';
            html += '</div>';
        }
        html += '<p style="font-size:13px;color:#6e6e73">Keep this email - the same conversation is where you file a claim if anything goes wrong.</p>';
        html += '</div>';
        return html;
    }
}