--  AURA Kernel — Entropy pool specification
--  П.51-K дорожной карты закрыт: Entropy_Consume объявлена в .ads и
--  экспортирована публично — больше недоступна только внутри .adb.
--  SPDX-License-Identifier: GPL-2.0-only

with Interfaces;

package Aura.Entropy is

   pragma SPARK_Mode (Off);

   --  Подать энтропийные данные в пул.
   procedure Entropy_Feed
     (Data : Interfaces.Unsigned_64;
      Bits : Natural);

   --  Получить N бит энтропии из пула.  Возвращает значение и количество
   --  реально доступных бит (может быть меньше N при истощении пула).
   procedure Entropy_Consume
     (N           : Natural;
      Value       : out Interfaces.Unsigned_64;
      Actual_Bits : out Natural);

   --  Текущий уровень накопленной энтропии в битах.
   function Entropy_Level return Natural;

end Aura.Entropy;
