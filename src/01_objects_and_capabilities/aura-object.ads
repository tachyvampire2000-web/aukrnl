--  AURA Kernel — aura-object.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Ring; use Aura.Ring;
with Interfaces;

package Aura.Object is

   pragma SPARK_Mode (On);

   type Rcu_Domain_Access is access all Integer; -- Placeholder

   --  [fix-009] Epoch : Unsigned_32 (4 миллиарда revoke-циклов до overflow)
   --  [T45]    Min_Ring : минимальный уровень для доступа к объекту
   type Object_Header is limited record
      Epoch      : aliased Interfaces.Unsigned_32 := 1;
      Min_Ring    : Ring_Level := Ring3;  --  разрешительный дефолт,
                                            --  эквивалент бывшего URing2
      Rcu_Domain  : Rcu_Domain_Access;     --  эквивалент Arc<RcuDomain>
   end record;

   --  Эквивалент Rust trait KernelObject. Ada tagged type с абстрактным
   --  примитивом даёт dispatching-эквивалент dyn-трейта там, где он нужен
   --  (см. §18.6 HardwareAbstraction) — здесь используется как интерфейс.
   type Kernel_Object is interface;

   function Header (Self : Kernel_Object) return Object_Header is abstract;

end Aura.Object;
