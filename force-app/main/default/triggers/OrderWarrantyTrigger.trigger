trigger OrderWarrantyTrigger on Order (after insert, after update) {
    List<Order> activated = new List<Order>();
    for (Order o : Trigger.new) {
        if (o.Status != 'Activated' || o.QR_Email_Sent__c == true) { continue; }
        if (Trigger.isUpdate) {
            Order old = Trigger.oldMap.get(o.Id);
            if (old.Status == 'Activated' && old.QR_Email_Sent__c == o.QR_Email_Sent__c) { continue; }
        }
        activated.add(o);
    }
    if (!activated.isEmpty()) {
        OrderWarrantyService.handleActivation(activated);
    }
}