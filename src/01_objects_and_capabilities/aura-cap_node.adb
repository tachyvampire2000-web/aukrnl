--  AURA Kernel — Capability Node allocator & CDT Cascade Revocation implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Containers.Bounded_Vectors;

package body Aura.Cap_Node is

   Max_Cap_Nodes : constant := 128;

   Pool_Nodes : array (1 .. Max_Cap_Nodes) of aliased Cap_Node_Inner;
   Pool_Free  : array (1 .. Max_Cap_Nodes) of Boolean := [others => True];

   procedure Alloc
     (Obj_Epoch : Interfaces.Unsigned_32;
      Result    : out Cap_Node_Access;
      Status    : out Kernel_Error)
   is
   begin
      Result := null;
      for I in 1 .. Max_Cap_Nodes loop
         if Pool_Free (I) then
            Pool_Free (I) := False;

            Pool_Nodes (I).Cap_Epoch          := 1;
            Pool_Nodes (I).Creation_Epoch      := 1;
            Pool_Nodes (I).Obj_Creation_Epoch  := Obj_Epoch;
            Pool_Nodes (I).Depth               := 0;
            Pool_Nodes (I).Badge               := 0;
            Pool_Nodes (I).Rights_Mask         := 0;
            Pool_Nodes (I).Revoke_In_Progress  := False;
            Pool_Nodes (I).Cap_Token           := Interfaces.Unsigned_64 (I);
            Pool_Nodes (I).Parent              := null;
            Pool_Nodes (I).First_Child          := null;
            Pool_Nodes (I).Next_Sibling         := null;
            Pool_Nodes (I).Prev_Sibling         := null;
            Pool_Nodes (I).Valid_From          := 0;
            Pool_Nodes (I).Valid_Until         := 0;
            Pool_Nodes (I).Rights              := 0;
            Pool_Nodes (I).Revoke_Notify        := null;

            Result := Pool_Nodes (I)'Access;
            Status := Ok;
            return;
         end if;
      end loop;
      Status := Out_Of_Memory;
   end Alloc;

   procedure Free (Node : Cap_Node_Access) is
   begin
      if Node /= null then
         for I in 1 .. Max_Cap_Nodes loop
            if Pool_Nodes (I)'Access = Node then
               Pool_Free (I) := True;
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

            -- Free the node slot
            Free (Node);
         end if;
      end loop;

      Status := Ok;
   end Cap_Revoke;

end Aura.Cap_Node;
