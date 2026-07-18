--  AURA Kernel — Causal Quarantine Dynamic MAC implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Interfaces;

package body Aura.Proposals.Causal_Quarantine is

   use type Interfaces.Unsigned_64;

   procedure Apply_Quarantine
     (Domain     : in out Causal_Quarantine_Domain;
      Level      : Quarantine_Level;
      Categories : Interfaces.Unsigned_64;
      Duration   : Interfaces.Unsigned_64;
      Now        : Interfaces.Unsigned_64)
   is
   begin
      Domain.Label :=
        (Level => Level, Categories => Categories, Valid_Thru => Now + Duration);
      Domain.Is_Blocked := (Level /= Clean);
   end Apply_Quarantine;

   procedure Propagate_Quarantine
     (Parent : Causal_Quarantine_Domain;
      Child  : in out Causal_Quarantine_Domain)
   is
   begin
      Child.Label := Parent.Label;
      Child.Is_Blocked := Parent.Is_Blocked;
   end Propagate_Quarantine;

   function Check_Write_Authorized
     (Domain     : Causal_Quarantine_Domain;
      Target_Lvl : Quarantine_Level;
      Now        : Interfaces.Unsigned_64) return Boolean
   is
   begin
      --  If the quarantine timer has expired, the domain is authorized to write
      if Now > Domain.Label.Valid_Thru then
         return True;
      end if;

      --  Otherwise, enforce strict Dynamic Bell-LaPadula (No Write-Down: cannot write to a cleaner/lower level)
      return Domain.Label.Level <= Target_Lvl;
   end Check_Write_Authorized;

end Aura.Proposals.Causal_Quarantine;
