--  AURA Kernel — aura-ring.ads
--  SPDX-License-Identifier: GPL-2.0-only


package Aura.Ring is

   pragma Pure;

   type Ring_Level is (Ring0, Ring3);
   --  Ring0 = kernel, Ring3 = userspace — идентично комментарию
   --  Rust-версии после revert-ring-001.

   for Ring_Level use (Ring0 => 0, Ring3 => 3);  --  сохраняет числовые
                                                    --  значения аппаратных CPL

end Aura.Ring;
