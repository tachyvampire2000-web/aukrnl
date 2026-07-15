--  AURA Kernel — aura-causal.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Interfaces;

package Aura.Causal is

   pragma SPARK_Mode (On);

   type Causal_Root_Kind_Tag is
     (Timer_Irq_Kind, Hardware_Irq_Kind, Page_Fault_Kind, Syscall_Entry_Kind);

   type Causal_Root_Kind (Tag : Causal_Root_Kind_Tag := Timer_Irq_Kind) is
     record
        case Tag is
           when Hardware_Irq_Kind  => Irq : Interfaces.Unsigned_32;
           when Syscall_Entry_Kind => Nr  : Interfaces.Unsigned_32;
           when others             => null;
        end case;
     end record;

   type Causal_Root is limited record
      Header : Object_Header;
      Kind   : Causal_Root_Kind;
   end record
     with Volatile;

end Aura.Causal;
