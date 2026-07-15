--  AURA Kernel — Common Instances specification
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Option;
with Aura.Thread_Capability;
with Aura.Capability.Validity;
with Aura.Weak_Ref;
with Aura.Thread;
with Aura.Ticket_Lock;
with Aura.Per_Cpu;
with Interfaces;
with Ada.Containers.Bounded_Vectors;

package Aura.Instances is
   pragma SPARK_Mode (Off);

   use type Interfaces.Unsigned_64;

   package Phys_Addr_Option_Base is new Aura.Option (Interfaces.Unsigned_64);
   
   package Revoke_Stacks is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Interfaces.Unsigned_64);

   package Audit_Locks is new Aura.Ticket_Lock (Interfaces.Unsigned_64);

   subtype Full_Thread is Aura.Thread.Thread;

   function Thread_Epoch
     (T : Full_Thread) return Interfaces.Unsigned_32
   is (T.Header.Epoch);

   package Thread_Capability renames Aura.Thread_Capability;
   package Thread_Weak_Ref_Base is new Aura.Weak_Ref (Full_Thread, Aura.Thread.Thread_Access, Thread_Epoch);

   package Thread_Capability_Validity is new Aura.Thread_Capability.Validity;
   package Cpu_Data is new Aura.Per_Cpu (Integer, 4);

end Aura.Instances;
