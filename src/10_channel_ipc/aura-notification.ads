--  AURA — Notification: асинхронный сигнальный объект (аналог
--  Zircon event / seL4 notification). Pending — битовая маска
--  накопленных сигналов; получатели ждут на Wait_Queue.
--  П.11 дорожной карты: Notification_Signal принимает Signal_Mask —
--  многобитовую маску, а не жёстко бит 0.

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

   --  Выставить биты Signal_Mask в Pending и разбудить ожидающих.
   --  Signal_Mask = 0 выставляет бит 0 (обратная совместимость с кодом,
   --  который передаёт 0 или не передаёт маску явно).
   procedure Notification_Signal
     (Notif       : Notification_Ref;
      Signal_Mask : Interfaces.Unsigned_64 := 1);

end Aura.Notification;
