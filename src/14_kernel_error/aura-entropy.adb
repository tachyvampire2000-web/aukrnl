--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with System;

package body Aura.Entropy is

   procedure Atomic_Compare_Exchange_U64
     (Addr : System.Address; Expected : Interfaces.Unsigned_64;
      Desired : Interfaces.Unsigned_64; Success : out Boolean) is
   begin
      --  Placeholder
      Success := True;
   end Atomic_Compare_Exchange_U64;

   function Check_Valid (Cap : Object_Bind_Prm_Ref) return Kernel_Error is (Ok);

   procedure Entropy_Consume
     (Bytes : Interfaces.Unsigned_64; Status : out Kernel_Error)
   is
      Cur    : Interfaces.Unsigned_64;
      Cas_Ok : Boolean;
   begin
      loop
         Cur := Entropy_Budget;
         if Cur < Bytes then
            Status := Entropy_Exhausted;
            return;
         end if;
         Atomic_Compare_Exchange_U64
           (Entropy_Budget'Address, Cur, Cur - Bytes, Cas_Ok);
         if Cas_Ok then
            Status := Ok;
            return;
         end if;
      end loop;
   end Entropy_Consume;

   procedure Entropy_Replenish (Bytes : Interfaces.Unsigned_64) is
      Cur, Next : Interfaces.Unsigned_64;
      Cas_Ok    : Boolean;
   begin
      loop
         Cur  := Entropy_Budget;
         Next := Interfaces.Unsigned_64'Min
           (Saturating_Add_U64 (Cur, Bytes), Entropy_Budget_Max);
         Atomic_Compare_Exchange_U64
           (Entropy_Budget'Address, Cur, Next, Cas_Ok);
         if Cas_Ok then
            return;
         end if;
      end loop;
   end Entropy_Replenish;

   procedure Entropy_Feed
     (Caller_Cap : Object_Bind_Prm_Ref;
      Bytes      : Interfaces.Unsigned_64;
      Status     : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Caller_Cap);
      if Status /= Ok then
         return;
      end if;
      Entropy_Replenish (Bytes);
      Status := Ok;
   end Entropy_Feed;

end Aura.Entropy;
