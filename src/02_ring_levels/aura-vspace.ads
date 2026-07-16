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

   type Process_Context is limited record
      Vspace : V_Space_Ref;
   end record;

   type Process_Context_Ref is access all Process_Context;
   type Process_Context_Weak_Ref is access all Process_Context;

end Aura.Vspace;
