--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

generic
   type Element_Type is private;
package Aura.Ticket_Lock is

   pragma SPARK_Mode (On);

   protected type Instance is
      --  Захватывает лок, блокируясь до своей очереди.
      --  Эквивалент Rust TicketLock::lock() + TicketGuard.
      entry Lock (Item : out Element_Type);

      --  Возвращает изменённое значение и освобождает лок.
      --  В Rust это происходило неявно в Drop::drop(); здесь — явный вызов,
      --  так как Ada protected-объекты не имеют деструкторов с доступом к
      --  сохранённому "guard"-состоянию вызывающего.
      procedure Unlock (Item : Element_Type);

      --  Эквивалент TicketLock::try_lock().
      entry Try_Lock (Item : out Element_Type; Success : out Boolean);

      --  Устанавливает начальное значение.
      procedure Init (Initial : Element_Type);

   private
      Data         : Element_Type;
      Next_Ticket  : Natural := 0;
      Now_Serving  : Natural := 0;
      My_Ticket    : Natural := 0;
      Locked       : Boolean := False;
   end Instance;

end Aura.Ticket_Lock;
