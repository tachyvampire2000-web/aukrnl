--  AURA — Ticket_Lock (correct and robust mutex implementation)
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Ticket_Lock is

   protected body Instance is

      entry Lock (Item : out Element_Type)
         when not Locked is
      begin
         Item := Data;
         Locked := True;
      end Lock;

      procedure Unlock (Item : Element_Type) is
      begin
         Data := Item;
         Locked := False;
      end Unlock;

      entry Try_Lock (Item : out Element_Type; Success : out Boolean)
         when True is
      begin
         if not Locked then
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
      end Init;

   end Instance;

end Aura.Ticket_Lock;
