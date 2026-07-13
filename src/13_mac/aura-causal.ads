--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Object; use Aura.Object;
with Interfaces;

package Aura.Causal is

   pragma SPARK_Mode (On);

   type Causal_Root_Kind_Tag is
     (Timer_Irq_Kind, Hardware_Irq_Kind, Page_Fault_Kind, Syscall_Entry_Kind);

   type Causal_Root_Kind (Tag : Causal_Root_Kind_Tag := Timer_Irq_Kind) is
     record
        case Tag is
           when Hardware_Irq_Kind  => Irq : Interfaces.Unsigned_32;
           when Syscall_Entry_Kind => Nr  : Interfaces.Unsigned_32;
           when others             => null;
        end case;
     end record;

   type Causal_Root is limited record
      Header : Object_Header;
      Kind   : Causal_Root_Kind;
   end record
     with Volatile;

end Aura.Causal;
