--  AURA Kernel — aura-rights.ads
--  SPDX-License-Identifier: GPL-2.0-only


package Aura.Rights is

   pragma SPARK_Mode (On);
   pragma Pure;

   --  Рантайм-маска — прямой перенос RightsMask (bitflags) из Rust-версии,
   --  единственного места, где права реально проверялись в рантайме уже
   --  в Rust-коде (check_right() всегда работал с RightsMask, а не с R).
   type Mask is mod 2 ** 32;

   Read       : constant Mask := 16#01#;
   Write      : constant Mask := 16#02#;
   Grant      : constant Mask := 16#04#;
   Manage     : constant Mask := 16#08#;
   Attr_Read  : constant Mask := 16#10#;
   Attr_Write : constant Mask := 16#20#;
   Mount      : constant Mask := 16#40#;
   Bind_Prm   : constant Mask := 16#80#;

   --  T28: deny-биты (сдвинуты на 16, идентично Rust-версии)
   Deny_Read   : constant Mask := 16#01_0000#;
   Deny_Write  : constant Mask := 16#02_0000#;
   Deny_Manage : constant Mask := 16#04_0000#;

   --  Именованные комбинации — эквивалент отдельных marker-типов там, где
   --  они реально использовались как значение, а не просто как maркер:
   Read_Write : constant Mask := Read or Write;   -- заменяет (Read, Write)
   Read_Only  : constant Mask := Read;
   Any_Rights : constant Mask := 16#FF#;           -- все grant-биты без deny

   function Contains (M : Mask; Required : Mask) return Boolean is
     ((M and Required) = Required);

end Aura.Rights;
