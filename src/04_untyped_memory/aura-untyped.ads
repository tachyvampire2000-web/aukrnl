--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Object; use Aura.Object;
with Ada.Containers.Bounded_Vectors;
with Interfaces;

use type Interfaces.Unsigned_64;
package Aura.Untyped is

   pragma SPARK_Mode (Off);

   Untyped_Bitmap_Words_Max : constant := 1024;  --  фиксированная ёмкость
                                                    --  для Bounded-массива,
                                                    --  заменяющего Box<[AtomicU64]>

   package Bitmap_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Interfaces.Unsigned_64);

   type Untyped_Region is limited record
      Header            : Object_Header;
      Phys_Addr_Base    : Interfaces.Unsigned_64;
      Size_Bits         : Interfaces.Unsigned_32;
      Is_Device         : Boolean;
      Allocated_Bitmap  : Bitmap_Vectors.Vector (Untyped_Bitmap_Words_Max);
   end record
     with Volatile;

end Aura.Untyped;
