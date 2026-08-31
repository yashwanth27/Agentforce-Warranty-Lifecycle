public without sharing class SchedulePickupAction {

    public class Request {
        @InvocableVariable(label='Case Number' required=true)
        public String caseNumber;
        @InvocableVariable(label='Pickup Slot' description='Chosen pickup window from the Apple Messages time picker' required=true)
        public Datetime pickupSlot;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Case Number')
        public String caseNumber;
        @InvocableVariable(label='Confirmed Slot')
        public String confirmedSlot;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Schedule Pickup' description='Books the pickup window the customer chose for an approved warranty claim and moves the claim to Pickup Scheduled.' category='WarrantyDesk')
    public static List<Result> run(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            r.success = false;
            r.caseNumber = req.caseNumber;

            String cn = (req.caseNumber == null) ? '' : req.caseNumber.trim().replaceAll('[^0-9]', '');
            List<Case> rows = String.isBlank(cn) ? new List<Case>() : [
                SELECT Id, CaseNumber, Claim_Stage__c FROM Case
                WHERE CaseNumber LIKE :('%' + cn) AND Claim_Stage__c != null
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (rows.isEmpty()) {
                r.message = 'No warranty claim found with that reference.';
                results.add(r);
                continue;
            }
            Case claim = rows[0];

            if (claim.Claim_Stage__c != 'Approved-Pending-Pickup') {
                r.message = 'Claim ' + claim.CaseNumber + ' is currently ' + claim.Claim_Stage__c
                    + ', so a pickup cannot be booked yet. Only approved claims can be scheduled.';
                results.add(r);
                continue;
            }
            if (req.pickupSlot == null || req.pickupSlot < Datetime.now()) {
                r.message = 'That pickup time is in the past. Ask the customer to choose another slot.';
                results.add(r);
                continue;
            }

            try {
                update new Case(Id = claim.Id, Pickup_Slot__c = req.pickupSlot, Claim_Stage__c = 'Pickup Scheduled');
            } catch (DmlException e) {
                r.message = 'Could not book the pickup: ' + e.getDmlMessage(0);
                results.add(r);
                continue;
            }

            r.success = true;
            r.caseNumber = claim.CaseNumber;
            r.confirmedSlot = req.pickupSlot.format('EEEE d MMM, h:mm a');
            r.message = 'Pickup booked for ' + r.confirmedSlot + ' on claim ' + claim.CaseNumber + '.';
            results.add(r);
        }
        return results;
    }
}