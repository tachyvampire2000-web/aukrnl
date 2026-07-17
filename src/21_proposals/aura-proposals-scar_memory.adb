--  AURA Kernel — Memory of Scar implementation
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Proposals.Scar_Memory is

   procedure Record_Crash_Scar
     (Context  : in out Persistent_Scar_Context;
      Reason   : Crash_Reason;
      Fault_Pc : Interfaces.Unsigned_64;
      Now      : Interfaces.Unsigned_64)
   is
      Idx : constant Positive := Context.Next_Write_Idx;
   begin
      Context.History (Idx) :=
        (Reason => Reason, Fault_Pc => Fault_Pc, Timestamp => Now);

      if Context.History_Length < Max_Scars then
         Context.History_Length := Context.History_Length + 1;
      end if;

      if Idx = Max_Scars then
         Context.Next_Write_Idx := 1;
      else
         Context.Next_Write_Idx := Idx + 1;
      end if;
   end Record_Crash_Scar;

   function Check_Pattern_Escalation
     (Context : Persistent_Scar_Context) return Boolean
   is
      Match_Count : Natural := 0;
   begin
      if Context.History_Length < 2 then
         return False;
      end if;

      --  Check if we have repeating crash patterns of same reason and PC
      for I in 1 .. Context.History_Length - 1 loop
         if Context.History (I).Reason = Context.History (I + 1).Reason
           and then Context.History (I).Fault_Pc = Context.History (I + 1).Fault_Pc
         then
            Match_Count := Match_Count + 1;
         end if;
      end loop;

      return Match_Count >= Context.Repeat_Threshold;
   end Check_Pattern_Escalation;

end Aura.Proposals.Scar_Memory;
