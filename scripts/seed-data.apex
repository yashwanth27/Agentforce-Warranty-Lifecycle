/**
 * WarrantyDesk — seed data for a fresh scratch org / dev org.
 *
 * Run with:
 *   sf apex run --file scripts/seed-data.apex --target-org <alias>
 *
 * Creates: 1 Account, 1 Contact, 2 Products (+ PricebookEntries),
 *          2 Orders, 3 Assets with live warranties.
 *
 * IMPORTANT — change CONTACT_EMAIL to an address you can actually receive
 * mail at. The registration QR email and every "find my products" lookup
 * key off this value.
 */

String CONTACT_EMAIL = 'you@example.com';   // <-- CHANGE ME

// ---------------------------------------------------------------- Account
Account acc = new Account(Name = 'Ramesh Traders');
insert acc;

// ---------------------------------------------------------------- Contact
Contact con = new Contact(
    FirstName = 'Ramesh',
    LastName  = 'Patil',
    Email     = CONTACT_EMAIL,
    AccountId = acc.Id
);
insert con;

// --------------------------------------------------------------- Products
Product2 p1 = new Product2(Name = 'Model X-200 Submersible Pump',
                           ProductCode = 'X-200', IsActive = true);
Product2 p2 = new Product2(Name = 'Model X-450 Booster Pump',
                           ProductCode = 'X-450', IsActive = true);
insert new List<Product2>{ p1, p2 };

Id pbId = Test.isRunningTest()
        ? Test.getStandardPricebookId()
        : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

insert new List<PricebookEntry>{
    new PricebookEntry(Pricebook2Id = pbId, Product2Id = p1.Id,
                       UnitPrice = 18500, IsActive = true),
    new PricebookEntry(Pricebook2Id = pbId, Product2Id = p2.Id,
                       UnitPrice = 24900, IsActive = true)
};

// ----------------------------------------------------------------- Orders
// NOTE: OrderWarrantyTrigger fires on Order activation. Insert as Draft
// first so the seed script controls when (and whether) the QR email goes out.
Order o1 = new Order(AccountId = acc.Id, BillToContactId = con.Id,
                     EffectiveDate = Date.today().addDays(-30),
                     Status = 'Draft', Pricebook2Id = pbId);
Order o2 = new Order(AccountId = acc.Id, BillToContactId = con.Id,
                     EffectiveDate = Date.today().addDays(-5),
                     Status = 'Draft', Pricebook2Id = pbId);
insert new List<Order>{ o1, o2 };

// ----------------------------------------------------------------- Assets
// Serial format mirrors what the trigger generates: SN-{OrderNumber}-{n}
Order o1r = [SELECT OrderNumber FROM Order WHERE Id = :o1.Id];
Order o2r = [SELECT OrderNumber FROM Order WHERE Id = :o2.Id];

List<Asset> assets = new List<Asset>{
    new Asset(Name = 'Model X-200 Submersible Pump',
              SerialNumber = 'SN-' + o1r.OrderNumber + '-1',
              ContactId = con.Id, AccountId = acc.Id, Product2Id = p1.Id,
              Status = 'Purchased', PurchaseDate = Date.today().addDays(-30),
              Order__c = o1.Id, Warranty_Months__c = 12,
              Warranty_End_Date__c = Date.today().addDays(-30).addMonths(12)),
    new Asset(Name = 'Model X-200 Submersible Pump',
              SerialNumber = 'SN-' + o1r.OrderNumber + '-2',
              ContactId = con.Id, AccountId = acc.Id, Product2Id = p1.Id,
              Status = 'Purchased', PurchaseDate = Date.today().addDays(-30),
              Order__c = o1.Id, Warranty_Months__c = 12,
              Warranty_End_Date__c = Date.today().addDays(-30).addMonths(12)),
    new Asset(Name = 'Model X-450 Booster Pump',
              SerialNumber = 'SN-' + o2r.OrderNumber + '-1',
              ContactId = con.Id, AccountId = acc.Id, Product2Id = p2.Id,
              Status = 'Purchased', PurchaseDate = Date.today().addDays(-5),
              Order__c = o2.Id, Warranty_Months__c = 12,
              Warranty_End_Date__c = Date.today().addDays(-5).addMonths(12))
};
insert assets;

System.debug('=== WarrantyDesk seed complete ===');
System.debug('Account  : ' + acc.Id);
System.debug('Contact  : ' + con.Id + ' (' + CONTACT_EMAIL + ')');
System.debug('Orders   : ' + o1r.OrderNumber + ', ' + o2r.OrderNumber);
for (Asset a : [SELECT SerialNumber, Warranty_End_Date__c
                FROM Asset WHERE Id IN :assets]) {
    System.debug('Asset    : ' + a.SerialNumber +
                 ' warranty to ' + a.Warranty_End_Date__c);
}
