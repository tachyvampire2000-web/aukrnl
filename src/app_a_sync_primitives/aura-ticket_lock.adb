--  AURA Kernel — Synchronization: Ticket Lock implementation
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Ticket_Lock is

   protected body Instance is

      entry Lock (Item : out Element_Type)
         when not Locked is
      begin
         My_Ticket := Now_Serving;
         Next_Ticket := Next_Ticket + 1;
         Item := Data;
         Locked := True;
      end Lock;

      procedure Unlock (Item : Element_Type) is
      begin
         Data := Item;
         Now_Serving := Now_Serving + 1;
         Locked := False;
      end Unlock;

      entry Try_Lock (Item : out Element_Type; Success : out Boolean)
         when True is
      begin
         if not Locked then
            My_Ticket := Now_Serving;
            Next_Ticket := Next_Ticket + 1;
            Item := Data;
            Locked := True;
            Success := True;
         else
            Success := False;
         end if;
      end Try_Lock;

      procedure Init (Initial : Element_Type) is
      begin
         Data := Initial;
         Locked := False;
         Next_Ticket := 0;
         Now_Serving := 0;
         My_Ticket := 0;
      end Init;

   end Instance;

end Aura.Ticket_Lock;
