--  AURA Kernel — generic capability minting and CDT insertion
--  П.30 дорожной карты: реальный Cap_Mint с проверками и привязкой
--  дочернего узла к First_Child родителя.
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Capability is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Cap_Node_Access;

   --  Один lock защищает вставку в CDT на reference platform.
   protected Cdt_Lock is
      procedure Insert
        (Parent : Cap_Node_Access;
         Child  : Cap_Node_Access);
   end Cdt_Lock;

   protected body Cdt_Lock is
      procedure Insert
        (Parent : Cap_Node_Access;
         Child  : Cap_Node_Access)
      is
      begin
         Child.Parent       := Cap_Node_Weak_Ref (Parent);
         Child.Next_Sibling := Parent.First_Child;
         Child.Prev_Sibling := null;
         if Parent.First_Child /= null then
            Parent.First_Child.Prev_Sibling := Cap_Node_Weak_Ref (Child);
         end if;
         Parent.First_Child := Child;
      end Insert;
   end Cdt_Lock;

   function Empty_Instance return Instance is
     (Object   => null,
      Node     => null,
      Prepared => 0,
      Rights   => 0);

   procedure Cap_Mint_Node
     (Parent : Instance;
      Status : out Kernel_Error;
      Result : out Instance)
   is
      Node       : Cap_Node_Access;
      Node_Status : Kernel_Error;
   begin
      Result := Empty_Instance;

      if Parent.Object = null or else Parent.Node = null then
         Status := Bad_Cap;
         return;
      end if;
      if Parent.Node.Revoke_In_Progress then
         Status := Parent_Revoking;
         return;
      end if;
      if Parent.Node.Depth + 1 > Cdt_Max_Depth then
         Status := Cdt_Too_Deep;
         return;
      end if;

      Cap_Node.Alloc
        (Obj_Epoch => Epoch_Of (Parent.Object.all),
         Result    => Node,
         Status    => Node_Status);
      if Node_Status /= Ok then
         Status := Node_Status;
         return;
      end if;

      Node.Depth       := Parent.Node.Depth + 1;
      Node.Badge       := Parent.Node.Badge;
      Node.Rights_Mask := Parent.Node.Rights_Mask;
      Node.Rights      := Parent.Node.Rights;
      Cdt_Lock.Insert (Parent.Node, Node);

      Result := (Object   => Parent.Object,
                 Node     => Node,
                 Prepared => 0,
                 Rights   => Parent.Rights);
      Status := Ok;
   end Cap_Mint_Node;

   procedure Cap_Mint
     (Parent    : Instance;
      Requested : Aura.Rights.Mask;
      Result    : out Instance;
      Status    : out Kernel_Error)
   is
      Node        : Cap_Node_Access;
      Node_Status : Kernel_Error;
   begin
      Result := Empty_Instance;

      if Parent.Object = null or else Parent.Node = null then
         Status := Bad_Cap;
         return;
      end if;
      if not Contains (Parent.Rights, Grant)
        or else not Contains (Parent.Node.Rights_Mask, Requested)
      then
         Status := Bad_Rights;
         return;
      end if;
      if Parent.Node.Revoke_In_Progress then
         Status := Parent_Revoking;
         return;
      end if;
      if Parent.Node.Depth + 1 > Cdt_Max_Depth then
         Status := Cdt_Too_Deep;
         return;
      end if;

      Cap_Node.Alloc
        (Obj_Epoch => Epoch_Of (Parent.Object.all),
         Result    => Node,
         Status    => Node_Status);
      if Node_Status /= Ok then
         Status := Node_Status;
         return;
      end if;

      Node.Depth        := Parent.Node.Depth + 1;
      Node.Badge        := Parent.Node.Badge;
      Node.Rights_Mask  := Requested;
      Node.Rights       := Requested;
      Cdt_Lock.Insert (Parent.Node, Node);

      Result := (Object   => Parent.Object,
                 Node     => Node,
                 Prepared => 0,
                 Rights   => Requested);
      Status := Ok;
   end Cap_Mint;

   procedure Cap_Mint_Temporal
     (Parent      : Instance;
      Valid_From  : Interfaces.Unsigned_64;
      Valid_Until : Interfaces.Unsigned_64;
      Result      : out Instance;
      Status      : out Kernel_Error)
   is
   begin
      Result := Empty_Instance;
      if Valid_Until /= 0 and then Valid_Until <= Valid_From then
         Status := Invalid_Argument;
         return;
      end if;

      Cap_Mint (Parent, Parent.Rights, Result, Status);
      if Status = Ok then
         Result.Node.Valid_From  := Valid_From;
         Result.Node.Valid_Until := Valid_Until;
      end if;
   end Cap_Mint_Temporal;

end Aura.Capability;