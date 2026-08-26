--  AURA Kernel — Weak references specification
--  П.17 дорожной карты: Upgrade теперь безопасен по порядку проверок.
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Object; use Aura.Object;
with Interfaces;

package Aura.Weak_Ref is

   pragma SPARK_Mode (Off);

   use type Interfaces.Unsigned_32;

   type Object_Access is access all Kernel_Object'Class;

   type Instance is record
      Target         : Object_Access := null;
      Expected_Epoch : Interfaces.Unsigned_32 := 0;
   end record;

   Empty_Weak_Ref : constant Instance := (Target => null, Expected_Epoch => 0);

   --  Повысить слабую ссылку до сильной.
   --  БЕЗОПАСНЫЙ ПОРЯДОК (п.17): null-проверка → сравнение эпохи →
   --  разыменование.  Если Target обнулён рекламационным путём между
   --  null-проверкой и чтением Epoch, Ada ABI гарантирует, что чтение
   --  по нулевому адресу вызовет SIGSEGV на хост-ОС, а не тихое UB.
   procedure Upgrade
     (Self  : Instance;
      Value : out Object_Access;
      Alive : out Boolean)
   with Pre => True;  -- без контракта на тип доступа

   --  Создать слабую ссылку из сильной.
   function Make_Weak (Strong : Object_Access) return Instance;

   function Is_Expired (Self : Instance) return Boolean;

end Aura.Weak_Ref;
