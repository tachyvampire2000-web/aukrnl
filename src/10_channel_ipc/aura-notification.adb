--  AURA — Notification implementation
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Notification is

   use type Interfaces.Unsigned_64;

   --  П.11 дорожной карты: Signal_Mask реально используется — выставляем
   --  именно переданные биты, а не жёстко бит 0.
   procedure Notification_Signal
     (Notif       : Notification_Ref;
      Signal_Mask : Interfaces.Unsigned_64 := 1)
   is
      Mask : constant Interfaces.Unsigned_64 :=
        (if Signal_Mask = 0 then 1 else Signal_Mask);
   begin
      Notif.Pending := Notif.Pending or Mask;
      if Aura.Wait_Queue.Waiter_Count_Snapshot (Notif.Wait_Queue) > 0 then
         Aura.Wait_Queue.Wake_All_With_Signal (Notif.Wait_Queue);
      end if;
   end Notification_Signal;

end Aura.Notification;
