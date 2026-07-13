with Aura.Option;
with Aura.Capability;
with Aura.Weak_Ref;
with Aura.Slot_Map;
with Aura.Flip_Cell;
with Aura.Ticket_Lock;
with Aura.Thread;
with Aura.Object; use Aura.Object;
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

   package Thread_Capability is
     new Aura.Capability (Full_Thread, Thread_Epoch);
   package Thread_Weak_Ref_Base is new Aura.Weak_Ref (Full_Thread, Aura.Thread.Thread_Access);

end Aura.Instances;
