--  AURA Kernel — Namespaces implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Ring;

package body Aura.Namespace is

   Max_Namespace_Nodes : constant := 128;
   Pool_Nodes          : array (1 .. Max_Namespace_Nodes) of aliased Namespace_Node;
   Pool_Free           : array (1 .. Max_Namespace_Nodes) of Boolean := [others => True];

   procedure Alloc_Node (Result : out Namespace_Node_Access; Status : out Kernel_Error) is
   begin
      for I in 1 .. Max_Namespace_Nodes loop
         if Pool_Free (I) then
            Pool_Free (I) := False;
            Pool_Nodes (I).Associated := null;
            Pool_Nodes (I).Parent := null;
            Pool_Nodes (I).First_Child := null;
            Pool_Nodes (I).Next_Sibling := null;
            Pool_Nodes (I).Union_Target := null;
            Pool_Nodes (I).Union_Priority := 0;
            Pool_Nodes (I).Is_Union := False;
            Pool_Nodes (I).Attributes := null;
            Pool_Nodes (I).Name := Name_Strings.Null_Bounded_String;
            Pool_Nodes (I).Mac_Level := 0;
            Pool_Nodes (I).Mac_Categories := 0;
            Pool_Nodes (I).Mac_Label_Set := False;

            Result := Pool_Nodes (I)'Access;
            Status := Ok;
            return;
         end if;
      end loop;
      Result := null;
      Status := Out_Of_Memory;
   end Alloc_Node;

   procedure Namespace_Create_Node
     (Parent     : Namespace_Node_Access;
      Name       : String;
      Associated : Cap_Any_Ref;
      Result     : out Namespace_Node_Access;
      Status     : out Kernel_Error)
   is
      Child : Namespace_Node_Access;
   begin
      if Name'Length = 0 or else Name'Length > Namespace_Name_Max then
         Result := null;
         Status := Invalid_Argument;
         return;
      end if;

      -- Check if node with this name already exists under parent
      if Parent /= null then
         Child := Parent.First_Child;
         while Child /= null loop
            if Name_Strings.To_String (Child.Name) = Name then
               Result := null;
               Status := Already_Exists;
               return;
            end if;
            Child := Child.Next_Sibling;
         end loop;
      end if;

      Alloc_Node (Result, Status);
      if Status /= Ok then
         return;
      end if;

      Result.Name := Name_Strings.To_Bounded_String (Name);
      Result.Associated := Associated;

      -- Link to parent
      if Parent /= null then
         Result.Parent := Namespace_Node_Weak_Ref (Parent);
         if Parent.First_Child = null then
            Parent.First_Child := Result;
         else
            Child := Parent.First_Child;
            while Child.Next_Sibling /= null loop
               Child := Child.Next_Sibling;
            end loop;
            Child.Next_Sibling := Result;
         end if;
      end if;

      Status := Ok;
   end Namespace_Create_Node;

   procedure Namespace_Lookup
     (Root       : Namespace_Node_Access;
      Path       : String;
      Result     : out Namespace_Node_Access;
      Status     : out Kernel_Error)
   is
      Curr : Namespace_Node_Access := Root;
      Idx  : Positive := Path'First;
      Last : constant Positive := Path'Last;
      Next_Slash : Natural;
   begin
      if Root = null then
         Result := null;
         Status := Invalid_Argument;
         return;
      end if;

      -- Skip leading slash if any
      if Idx <= Last and then Path (Idx) = '/' then
         Idx := Idx + 1;
      end if;

      while Idx <= Last loop
         -- Find next component
         Next_Slash := Idx;
         while Next_Slash <= Last and then Path (Next_Slash) /= '/' loop
            Next_Slash := Next_Slash + 1;
         end loop;

         declare
            Comp : constant String := Path (Idx .. Next_Slash - 1);
            Child : Namespace_Node_Access;
            Found : Boolean := False;
         begin
            if Comp'Length > 0 then
               Child := Curr.First_Child;
               while Child /= null loop
                  if Name_Strings.To_String (Child.Name) = Comp then
                     Curr := Child;
                     Found := True;
                     exit;
                  end if;
                  Child := Child.Next_Sibling;
               end loop;

               if not Found then
                  Result := null;
                  Status := Not_Found;
                  return;
               end if;
            end if;
         end;

         Idx := Next_Slash + 1;
      end loop;

      Result := Curr;
      Status := Ok;
   end Namespace_Lookup;

   procedure Namespace_Mount
     (Parent     : Namespace_Node_Access;
      Name       : String;
      Source     : Cap_Any_Ref;
      Status     : out Kernel_Error)
   is
      Result : Namespace_Node_Access;
   begin
      if Parent = null or else Source = null then
         Status := Invalid_Argument;
         return;
      end if;

      Namespace_Create_Node (Parent, Name, Source, Result, Status);
   end Namespace_Mount;

end Aura.Namespace;
