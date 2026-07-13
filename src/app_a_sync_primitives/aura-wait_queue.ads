--  AURA — очередь ожидания (Wait_Queue).
--  Общий примитив блокирующего ожидания для Notification, Channel и
--  Attr_Watch: поток регистрируется (Prepare), блокируется в планировщике
--  и снимает регистрацию (Cancel). Waiter_Count_Snapshot даёт
--  безлоковый снимок числа ожидающих — ложноположительное чтение
--  безопасно, пробуждение идемпотентно.

with Interfaces;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;

package Aura.Wait_Queue is

   pragma SPARK_Mode (Off);

   Wait_Queue_Max_Waiters : constant := 64;

   type Wait_Token is record
      Id : Interfaces.Unsigned_64 := 0;
   end record;

   type Instance is tagged record
      Waiters : aliased Natural := 0;
      Signal  : aliased Interfaces.Unsigned_64 := 0;
   end record;

   --  Зарегистрироваться как waiter. Max_Waiters при переполнении.
   procedure Prepare (Self : in out Instance; Status : out Kernel_Error);

   --  То же, с внешним токеном (Cap_Wait_Any, T31).
   procedure Prepare_With_Token
     (Self   : in out Instance;
      Token  : Wait_Token;
      Status : out Kernel_Error);

   --  Снять регистрацию (после пробуждения или таймаута).
   procedure Cancel (Self : in out Instance);

   --  Снимок числа ожидающих без блокировки.
   function Waiter_Count_Snapshot (Self : Instance) return Natural;

   --  Разбудить всех ожидающих, выставив сигнал.
   procedure Wake_All_With_Signal (Self : in out Instance);

end Aura.Wait_Queue;
