--  AURA — виртуальное адресное пространство (VSpace).
--  Минимальный объект уровня ядра: корень таблицы страниц плюс
--  стандартный Object_Header (эпоха, минимальное кольцо, RCU-домен).

with Aura.Object; use Aura.Object;
with Interfaces;

package Aura.Vspace is

   pragma SPARK_Mode (Off);

   type V_Space is limited record
      Header          : Object_Header;
      Page_Table_Root : Interfaces.Unsigned_64 := 0;
   end record;

   type V_Space_Ref is access all V_Space;

end Aura.Vspace;
