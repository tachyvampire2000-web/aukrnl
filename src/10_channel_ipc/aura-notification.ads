--  AURA — Notification: асинхронный сигнальный объект (аналог
--  Zircon event / seL4 notification). Pending — битовая маска
--  накопленных сигналов; получатели ждут на Wait_Queue.

with Aura.Object; use Aura.Object;
with Aura.Wait_Queue;
with Interfaces;

package Aura.Notification is

   pragma SPARK_Mode (Off);

   type Notification_Object is limited record
      Header     : Object_Header;
      Pending    : aliased Interfaces.Unsigned_64 := 0;
      Wait_Queue : Aura.Wait_Queue.Instance;
   end record;

   type Notification_Ref is access all Notification_Object;

   --  Выставить сигнал и разбудить ожидающих.
   procedure Notification_Signal (Notif : Notification_Ref);

end Aura.Notification;
