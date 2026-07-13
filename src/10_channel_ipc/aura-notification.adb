package body Aura.Notification is

   procedure Notification_Signal (Notif : Notification_Ref) is
      use type Interfaces.Unsigned_64;
   begin
      Notif.Pending := Notif.Pending or 1;
      if Aura.Wait_Queue.Waiter_Count_Snapshot (Notif.Wait_Queue) > 0 then
         Aura.Wait_Queue.Wake_All_With_Signal (Notif.Wait_Queue);
      end if;
   end Notification_Signal;

end Aura.Notification;
