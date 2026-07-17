--  AURA Kernel — Entropy budget implementation
--  SPDX-License-Identifier: GPL-2.0-only


with System;
with Aura.Hal;

package body Aura.Entropy is

   function Check_Valid (Cap : Object_Bind_Prm_Ref) return Kernel_Error is
   begin
      if Cap = null then
         return Bad_Cap;
      else
         return Ok;
      end if;
   end Check_Valid;

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
         Aura.Hal.Atomic_Compare_Exchange_U64
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
         Aura.Hal.Atomic_Compare_Exchange_U64
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
