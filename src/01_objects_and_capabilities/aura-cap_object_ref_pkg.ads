--  AURA Kernel — aura-cap_object_ref_pkg.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Ada.Finalization;
with System;
with Interfaces;

package Aura.Cap_Object_Ref_Pkg is

   pragma SPARK_Mode (On);
   pragma Elaborate_Body;

   --  Контролируемая ссылка со счётчиком — эквивалент Arc<T> на границе
   --  §1.1 порта, где Header/Kernel_Object живут за System.Address, а не
   --  за типизированным access-типом. См. T-Ada-06 (§23 порта):
   --  формальное доказательство порядка Object_Destroy/epoch bump
   --  относительно Ada.Finalization.Finalize не выполнено в рамках этого
   --  порта — данное объявление закрывает только компиляционный пробел
   --  (тип существует), не открытый вопрос о порядке операций.
   type Instance is new Ada.Finalization.Controlled with record
      Target : System.Address := System.Null_Address;
      Epoch  : Interfaces.Unsigned_32 := 0;
   end record;

   overriding procedure Adjust   (Self : in out Instance);
   overriding procedure Finalize (Self : in out Instance);

end Aura.Cap_Object_Ref_Pkg;
