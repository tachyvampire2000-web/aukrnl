--  AURA Kernel — Capability Node allocator & CDT Cascade Revocation implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Containers.Bounded_Vectors;
with Aura.Hal;

package body Aura.Cap_Node is

   Max_Cap_Nodes : constant := 128;

   Pool_Nodes : array (1 .. Max_Cap_Nodes) of aliased Cap_Node_Inner;

   type Free_Array is array (1 .. Max_Cap_Nodes) of Boolean;
   type Cpu_Epochs_Array is array (0 .. Aura.Hal.Max_Cpus - 1) of aliased Interfaces.Unsigned_32;
   type Retired_Nodes_Array is array (1 .. Max_Cap_Nodes) of Cap_Node_Access;
   type Retired_Epochs_Array is array (1 .. Max_Cap_Nodes) of Interfaces.Unsigned_32;

   protected Cap_Pool_Manager is
      procedure Alloc_Slot
        (Index     : out Positive;
         Success   : out Boolean);
      procedure Free_Slot (Index : Positive);
      procedure Retire_Node (Node : Cap_Node_Access; Success : out Boolean);
      procedure Advance_Epoch_And_Reclaim;
      procedure Enter_Critical_Section (Cpu : Natural);
      procedure Leave_Critical_Section (Cpu : Natural);
   private
      Pool_Free  : Free_Array := [others => True];

      Global_Reclamation_Epoch : Interfaces.Unsigned_32 := 1;
      Active_Cpu_Epochs        : Cpu_Epochs_Array := [others => 0];

      Retired_Nodes            : Retired_Nodes_Array := [others => null];
      Retired_Epochs           : Retired_Epochs_Array := [others => 0];
      Retired_Count            : Natural := 0;
   end Cap_Pool_Manager;

   protected body Cap_Pool_Manager is

      procedure Alloc_Slot
        (Index     : out Positive;
         Success   : out Boolean) is
      begin
         Success := False;
         Index := 1;
         for I in 1 .. Max_Cap_Nodes loop
            if Pool_Free (I) then
               Pool_Free (I) := False;
               Index := I;
               Success := True;
               return;
            end if;
         end loop;
      end Alloc_Slot;

      procedure Free_Slot (Index : Positive) is
      begin
         if Index <= Max_Cap_Nodes then
            Pool_Free (Index) := True;
         end if;
      end Free_Slot;

      procedure Retire_Node (Node : Cap_Node_Access; Success : out Boolean) is
      begin
         Success := False;
         if Node /= null and then Retired_Count < Max_Cap_Nodes then
            Retired_Count := Retired_Count + 1;
            Retired_Nodes (Retired_Count) := Node;
            Retired_Epochs (Retired_Count) := Global_Reclamation_Epoch;
            Success := True;
         end if;
      end Retire_Node;

      procedure Enter_Critical_Section (Cpu : Natural) is
      begin
         if Cpu < Aura.Hal.Max_Cpus then
            Active_Cpu_Epochs (Cpu) := Global_Reclamation_Epoch;
         end if;
      end Enter_Critical_Section;

      procedure Leave_Critical_Section (Cpu : Natural) is
      begin
         if Cpu < Aura.Hal.Max_Cpus then
            Active_Cpu_Epochs (Cpu) := 0; -- 0 represents inactive reader
         end if;
      end Leave_Critical_Section;

      procedure Advance_Epoch_And_Reclaim is
         use type Interfaces.Unsigned_32;
         Safe_To_Free : Boolean;
         Node_Epoch   : Interfaces.Unsigned_32;
         I            : Positive := 1;
      begin
         -- Increment the global reclamation epoch
         Global_Reclamation_Epoch := Global_Reclamation_Epoch + 1;

         -- Iterate and reclaim safe nodes
         while I <= Retired_Count loop
            Node_Epoch := Retired_Epochs (I);
            Safe_To_Free := True;

            for Cpu in 0 .. Aura.Hal.Max_Cpus - 1 loop
               declare
                  Cpu_Epoch : constant Interfaces.Unsigned_32 := Active_Cpu_Epochs (Cpu);
               begin
                  if Cpu_Epoch /= 0 and then Cpu_Epoch <= Node_Epoch then
                     Safe_To_Free := False;
                     exit;
                  end if;
               end;
            end loop;

            if Safe_To_Free then
               -- Safely free the memory slot by finding its index in Pool_Nodes
               declare
                  Freed : Boolean := False;
               begin
                  for K in 1 .. Max_Cap_Nodes loop
                     if Pool_Nodes (K)'Access = Retired_Nodes (I) then
                        Pool_Free (K) := True;
                        Freed := True;
                        exit;
                     end if;
                  end loop;

                  if not Freed then
                     raise Program_Error with "EBR: Retired node not found in Pool_Nodes!";
                  end if;
               end;

               -- Shift remaining elements
               for J in I .. Retired_Count - 1 loop
                  Retired_Nodes (J) := Retired_Nodes (J + 1);
                  Retired_Epochs (J) := Retired_Epochs (J + 1);
               end loop;
               Retired_Nodes (Retired_Count) := null;
               Retired_Epochs (Retired_Count) := 0;
               Retired_Count := Retired_Count - 1;
            else
               I := I + 1;
            end if;
         end loop;
      end Advance_Epoch_And_Reclaim;

   end Cap_Pool_Manager;

   procedure Alloc
     (Obj_Epoch : Interfaces.Unsigned_32;
      Result    : out Cap_Node_Access;
      Status    : out Kernel_Error)
   is
      Index   : Positive;
      Success : Boolean;
   begin
      Result := null;
      Cap_Pool_Manager.Alloc_Slot (Index, Success);
      if Success then
         Pool_Nodes (Index).Cap_Epoch          := 1;
         Pool_Nodes (Index).Creation_Epoch      := 1;
         Pool_Nodes (Index).Obj_Creation_Epoch  := Obj_Epoch;
         Pool_Nodes (Index).Depth               := 0;
         Pool_Nodes (Index).Badge               := 0;
         Pool_Nodes (Index).Rights_Mask         := 0;
         Pool_Nodes (Index).Revoke_In_Progress  := False;
         Pool_Nodes (Index).Cap_Token           := Interfaces.Unsigned_64 (Index);
         Pool_Nodes (Index).Parent              := null;
         Pool_Nodes (Index).First_Child          := null;
         Pool_Nodes (Index).Next_Sibling         := null;
         Pool_Nodes (Index).Prev_Sibling         := null;
         Pool_Nodes (Index).Valid_From          := 0;
         Pool_Nodes (Index).Valid_Until         := 0;
         Pool_Nodes (Index).Rights              := 0;
         Pool_Nodes (Index).Revoke_Notify        := null;

         Result := Pool_Nodes (Index)'Access;
         Status := Ok;
      else
         Status := Out_Of_Memory;
      end if;
   end Alloc;

   procedure Free (Node : Cap_Node_Access) is
   begin
      if Node /= null then
         for I in 1 .. Max_Cap_Nodes loop
            if Pool_Nodes (I)'Access = Node then
               Cap_Pool_Manager.Free_Slot (I);
               return;
            end if;
         end loop;
      end if;
   end Free;

   procedure Cap_Revoke
     (Root   : Cap_Node_Access;
      Status : out Kernel_Error)
   is
      use type Interfaces.Unsigned_32;

      package Node_Vectors is new Ada.Containers.Bounded_Vectors
        (Index_Type => Positive, Element_Type => Cap_Node_Access);

      Stack : Node_Vectors.Vector (Max_Cap_Nodes);
      Node  : Cap_Node_Access;
      Child : Cap_Node_Access;
   begin
      if Root = null then
         Status := Invalid_Argument;
         return;
      end if;

      if Root.Revoke_In_Progress then
         Status := Ok;
         return;
      end if;

      Node_Vectors.Append (Stack, Root);

      while not Node_Vectors.Is_Empty (Stack) loop
         Node := Node_Vectors.Last_Element (Stack);
         Node_Vectors.Delete_Last (Stack);

         if Node /= null then
            -- Set revoke flags and bump epoch for instant revocation
            Node.Revoke_In_Progress := True;
            Node.Cap_Epoch := Node.Cap_Epoch + 1;

            -- Push children to stack
            Child := Node.First_Child;
            while Child /= null loop
               if Integer (Node_Vectors.Length (Stack)) >= Max_Cap_Nodes then
                  Status := Capacity_Exceeded;
                  return;
               end if;
               Node_Vectors.Append (Stack, Child);
               Child := Child.Next_Sibling;
            end loop;

            -- Detach from parent and siblings
            if Node.Prev_Sibling /= null then
               Node.Prev_Sibling.Next_Sibling := Node.Next_Sibling;
            end if;
            if Node.Next_Sibling /= null then
               Node.Next_Sibling.Prev_Sibling := Node.Prev_Sibling;
            end if;
            if Node.Parent /= null and then Node.Parent.First_Child = Node then
               Node.Parent.First_Child := Node.Next_Sibling;
            end if;

            -- Retire the node slot instead of immediate Free under EBR
            Retire (Node);
         end if;
      end loop;

      Status := Ok;
   end Cap_Revoke;

   procedure Enter_Critical_Section (Cpu : Natural) is
   begin
      Cap_Pool_Manager.Enter_Critical_Section (Cpu);
   end Enter_Critical_Section;

   procedure Leave_Critical_Section (Cpu : Natural) is
   begin
      Cap_Pool_Manager.Leave_Critical_Section (Cpu);
   end Leave_Critical_Section;

   procedure Retire (Node : Cap_Node_Access) is
      Success : Boolean;
   begin
      Cap_Pool_Manager.Retire_Node (Node, Success);
   end Retire;

   procedure Advance_Epoch_And_Reclaim is
   begin
      Cap_Pool_Manager.Advance_Epoch_And_Reclaim;
   end Advance_Epoch_And_Reclaim;

end Aura.Cap_Node;
