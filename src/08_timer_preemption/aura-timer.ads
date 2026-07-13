--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Interfaces;

package Aura.Timer is

   pragma SPARK_Mode (On);

   Timer_Irq : constant := 0;

   use type Interfaces.Unsigned_64;

   Global_Tick : aliased Interfaces.Unsigned_64 := 0;

   procedure Timer_Interrupt_Handler
   with Export, Convention => C;


   function Current_Tick return Interfaces.Unsigned_64 is (Global_Tick);

end Aura.Timer;
