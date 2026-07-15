--  AURA Kernel — aura-capability.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Aura.Rights;
with Aura.Cap_Node; use Aura.Cap_Node;
with Interfaces;

generic
   type Object_Type is limited private with Volatile;
   with function Epoch_Of
     (Obj : Object_Type) return Interfaces.Unsigned_32;
package Aura.Capability is

   pragma SPARK_Mode (Off);

   type Cap_Object_Ref is access all Object_Type; -- Placeholder

   type Instance is limited record
      Object    : Cap_Object_Ref;     --  эквивалент Arc<T>: контролируемая
                                        --  ссылка со счётчиком (см. §1.1)
      Node      : Cap_Node_Access;     --  эквивалент Arc<CapNodeInner>
      Prepared  : aliased Interfaces.Unsigned_64 := 0;  --  T25 fastpath-кэш:
                                        --  high 32 бита = epoch последней
                                        --  успешной проверки
      Rights    : Aura.Rights.Mask;    --  РАНТАЙМ-эквивалент phantom R
   end record;

   --  Почему Cap_Object_Ref (контролируемый тип), а не System.Address:
   --  Rust не позволяет разыменовать Arc<T> после освобождения объекта —
   --  тот же эффект в Ada достигается через контролируемый тип с проверкой
   --  Is_Valid перед доступом, устраняя тот же класс use-after-free.

end Aura.Capability;
