--  AURA Kernel — aura-capability.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Aura.Rights; use Aura.Rights;
with Aura.Cap_Node; use Aura.Cap_Node;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Interfaces;

--  П.15 дорожной карты: «with Volatile» на обобщённом формальном типе
--  недопустим (ARM 12.5.1 — аспекты на formal_type_definition не
--  поддерживаются).  Volatile применяется на месте инстанцирования
--  (объявляющий код добавляет Volatile к конкретному типу).
generic
   type Object_Type is limited private;
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

   Cdt_Max_Depth : constant Interfaces.Unsigned_32 := 32;

   --  Создать дочерний узел CDT с теми же объектом и правами,
   --  ограниченными правами родителя.
   procedure Cap_Mint_Node
     (Parent : Instance;
      Status : out Kernel_Error;
      Result : out Instance);

   procedure Cap_Mint
     (Parent    : Instance;
      Requested : Aura.Rights.Mask;
      Result    : out Instance;
      Status    : out Kernel_Error)
   with Pre => Contains (Parent.Rights, Grant);

   procedure Cap_Mint_Temporal
     (Parent      : Instance;
      Valid_From  : Interfaces.Unsigned_64;
      Valid_Until : Interfaces.Unsigned_64;
      Result      : out Instance;
      Status      : out Kernel_Error)
   with Pre => Contains (Parent.Rights, Grant);

   --  Почему Cap_Object_Ref (контролируемый тип), а не System.Address:
   --  Rust не позволяет разыменовать Arc<T> после освобождения объекта —
   --  тот же эффект в Ada достигается через контролируемый тип с проверкой
   --  Is_Valid перед доступом, устраняя тот же класс use-after-free.

end Aura.Capability;
