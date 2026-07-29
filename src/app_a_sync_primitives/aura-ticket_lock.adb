--  AURA Kernel — Synchronization: Ticket Lock implementation
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Ticket_Lock is

   protected body Instance is

      entry Lock (Item : out Element_Type) when True is
         My_Ticket : Natural;
      begin
         My_Ticket := Next_Ticket;
         Next_Ticket := Next_Ticket + 1;

         if not Locked and then Now_Serving = My_Ticket then
            Locked := True;
            Item := Data;
         else
            requeue Wait_Queue (My_Ticket mod 16);
         end if;
      end Lock;

      entry Wait_Queue (for I in Ticket_Index) (Item : out Element_Type)
         when not Locked and then Now_Serving mod 16 = I is
      begin
         Locked := True;
         Item := Data;
      end Wait_Queue;

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
      end Init;

   end Instance;

end Aura.Ticket_Lock;
