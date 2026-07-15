--  AURA Kernel — Synchronization: Read-Copy Update (RCU) implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;

package body Aura.Rcu is

   use type Interfaces.Unsigned_64;

   procedure Execute (Cb : Rcu_Callback) is
      procedure Free_Layer is new Ada.Unchecked_Deallocation (Integer, Layer_Access);
      procedure Free_Attr_Entry is new Ada.Unchecked_Deallocation (Integer, Attr_Entry_Access);
      procedure Free_Ns_Node is new Ada.Unchecked_Deallocation (Integer, Namespace_Node_Access);
   begin
      --  RCU callback dispatch based on the Kind
      case Cb.Kind is
         when Drop_Object =>
            null; -- raw address tracing / no-op
         when Drop_Layer =>
            declare
               L_Ref : Layer_Access := Cb.Layer_Ref;
            begin
               Free_Layer (L_Ref);
            end;
         when Drop_Attr_Entry =>
            declare
               A_Ref : Attr_Entry_Access := Cb.Attr_Ref;
            begin
               Free_Attr_Entry (A_Ref);
            end;
         when Drop_Namespace_Node =>
            declare
               N_Ref : Namespace_Node_Access := Cb.Ns_Node_Ref;
            begin
               Free_Ns_Node (N_Ref);
            end;
      end case;
   end Execute;

   protected body Rcu_Queue is

      procedure Push (Cb : Rcu_Callback; Status : out Kernel_Error) is
      begin
         if Len < Rcu_Queue_Capacity then
            Len := Len + 1;
            for I in Entries'Range loop
               if not Entries (I).Present then
                  declare
                     New_Entry : Callback_Option (Present => True);
                  begin
                     New_Entry.Value := Cb;
                     Entries (I) := New_Entry;
                  end;
                  Status := Ok;
                  return;
               end if;
            end loop;
         end if;
         Status := Capacity_Exceeded;
      end Push;

      procedure Drain is
      begin
         for I in Entries'Range loop
            if Entries (I).Present then
               Execute (Entries (I).Value);
               Entries (I) := (Present => False);
            end if;
         end loop;
         Len := 0;
      end Drain;

   end Rcu_Queue;

   protected body Rcu_Domain is

      procedure Read_Lock is
      begin
         Active_Readers := Active_Readers + 1;
      end Read_Lock;

      procedure Read_Unlock is
         Idx : Natural;
      begin
         Active_Readers := Active_Readers - 1;

         -- Grace period reached: when readers drop to 0,
         -- shift generation and drain inactive queue
         if Active_Readers = 0 then
            Global_Gen := Global_Gen + 1;
            Idx := Natural (Global_Gen mod 2);
            -- Swap queues and drain the callbacks of the inactive generation
            Pending_Queues (1 - Idx).Drain;
         end if;
      end Read_Unlock;

      procedure Call_Rcu (Cb : Rcu_Callback; Status : out Kernel_Error) is
         Idx : constant Natural := Natural (Global_Gen mod 2);
      begin
         if Active_Readers = 0 then
            -- Immediate execution if no active readers are currently reading
            Execute (Cb);
            Status := Ok;
         else
            Pending_Queues (Idx).Push (Cb, Status);
         end if;
      end Call_Rcu;

      function Readers_Count return Interfaces.Unsigned_64 is
      begin
         return Active_Readers;
      end Readers_Count;

   end Rcu_Domain;

   procedure Call (Self : Defer; Cb : Rcu_Callback; Status : out Kernel_Error)
   is
   begin
      Self.Domain.Call_Rcu (Cb, Status);
   end Call;

   procedure Rcu_Assign (Ptr : System.Address; Val : Element_Access) is
      use type System.Address;
      type Address_Access is access all Element_Access;
      function To_Access is new Ada.Unchecked_Conversion (System.Address, Address_Access);
   begin
      if Ptr /= System.Null_Address then
         To_Access (Ptr).all := Val;
      end if;
   end Rcu_Assign;

   function Rcu_Deref (Ptr : System.Address) return Element_Access is
      use type System.Address;
      type Address_Access is access all Element_Access;
      function To_Access is new Ada.Unchecked_Conversion (System.Address, Address_Access);
   begin
      if Ptr /= System.Null_Address then
         return To_Access (Ptr).all;
      else
         return null;
      end if;
   end Rcu_Deref;

end Aura.Rcu;
