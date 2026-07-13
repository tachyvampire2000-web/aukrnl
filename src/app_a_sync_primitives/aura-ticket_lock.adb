--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

package body Aura.Ticket_Lock is

   protected body Instance is

      entry Lock (Item : out Element_Type)
         when Now_Serving = My_Ticket is
      begin
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
         if not Locked and then Now_Serving = Next_Ticket then
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
      end Init;

   end Instance;

end Aura.Ticket_Lock;
