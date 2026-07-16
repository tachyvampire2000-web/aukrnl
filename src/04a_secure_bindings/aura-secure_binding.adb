--  AURA Kernel — Secure Resource Bindings implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Hal;
with Aura.Ring;

package body Aura.Secure_Binding is

   use type Aura.Vspace.V_Space_Ref;
   use type Aura.Vspace.Process_Context_Ref;
   use type Aura.Vspace.Process_Context_Weak_Ref;

   procedure Upgrade (W : Process_Context_Weak_Ref; R : out Process_Context_Ref; A : out Boolean) is
   begin
      R := Process_Context_Ref (W);
      A := W /= null;
   end Upgrade;

   procedure Vspace_Unmap (V : Aura.Vspace.V_Space_Ref; Va, S : Interfaces.Unsigned_64; St : out Kernel_Error) is
   begin
      if V = null then
         St := Bad_Cap;
      else
         Aura.Hal.Hal_Unmap_Segment (V.Page_Table_Root, Va, S, St);
      end if;
   end Vspace_Unmap;

   function Check_Valid (C : Prm_Resource_Set_Cap) return Kernel_Error is
      pragma Unreferenced (C);
   begin
      return Ok;
   end Check_Valid;

   procedure Map_Resource_Into_Vspace
     (V : Aura.Vspace.V_Space_Ref; R : Secure_Binding_Resource; H : Interfaces.Unsigned_64;
      Va : out Interfaces.Unsigned_64; St : out Kernel_Error) is
   begin
      if V = null then
         Va := 0;
         St := Bad_Cap;
      else
         Va := (if H /= 0 then H else 16#1000_0000#);
         -- Map MMIO, DMA or Ports
         declare
            Phys : Interfaces.Unsigned_64;
            Size : Interfaces.Unsigned_64;
         begin
            case R.Kind is
               when Mmio_Region =>
                  Phys := R.Mmio_Phys_Base;
                  Size := R.Mmio_Size;
               when Dma_Buffer =>
                  Phys := R.Dma_Phys_Base;
                  Size := R.Dma_Size;
               when Port_Io =>
                  Phys := Interfaces.Unsigned_64 (R.Base_Port);
                  Size := Interfaces.Unsigned_64 (R.Count);
            end case;
            Aura.Hal.Hal_Iommu_Map (V.Page_Table_Root, Va, Phys, Size, 0, St);
         end;
      end if;
   end Map_Resource_Into_Vspace;

   procedure Construct_Secure_Binding
     (Header     : Object_Header;
      Resource   : Secure_Binding_Resource;
      Owner      : Process_Context_Ref;
      Kernel_Tlb : Interfaces.Unsigned_64;
      Result     : out Secure_Binding_Manage_Ref) is
      pragma Unreferenced (Header);
   begin
      Result := (Object => new Secure_Binding'
        (Header     => (Epoch => 1, Min_Ring => Aura.Ring.Ring3, Rcu_Domain => null),
         Resource   => Resource,
         Owner      => Process_Context_Weak_Ref (Owner),
         Kernel_Tlb => Kernel_Tlb));
   end Construct_Secure_Binding;

   procedure Resolve_External_Effect (Self : in out Secure_Binding) is
      Owner_Alive  : Boolean;
      Owner_Ctx    : Process_Context_Ref;
      Vspace_Alive : Boolean;
      Vspace       : Aura.Vspace.V_Space_Ref;
      Va           : Interfaces.Unsigned_64;
      Size         : Interfaces.Unsigned_64;
   begin
      Upgrade (Self.Owner, Owner_Ctx, Owner_Alive);
      if not Owner_Alive then
         return;
      end if;
      Vspace := Owner_Ctx.Vspace;
      Vspace_Alive := Vspace /= null;
      if not Vspace_Alive then
         return;
      end if;

      Va := Self.Kernel_Tlb;
      if Va /= 0 then
         Size := (case Self.Resource.Kind is
                    when Mmio_Region => Self.Resource.Mmio_Size,
                    when Dma_Buffer  => Self.Resource.Dma_Size,
                    when Port_Io     =>
                      Interfaces.Unsigned_64 (Self.Resource.Count));

         --  Немедленный TLB shootdown — ни одна инструкция процесса не
         --  пройдёт через этот маппинг после возврата. Идентично
         --  комментарию Rust-версии.
         declare
            Unmap_Status : Kernel_Error;
         begin
            Vspace_Unmap (Vspace, Va, Size, Unmap_Status);
         end;
         Self.Kernel_Tlb := 0;
      end if;
   end Resolve_External_Effect;

   procedure Secure_Binding_Create
     (Prm_Cap  : Prm_Resource_Set_Cap;
      Resource : Secure_Binding_Resource;
      Owner    : Process_Context_Ref;
      Va_Hint  : Interfaces.Unsigned_64;
      Result   : out Secure_Binding_Manage_Ref;
      Status   : out Kernel_Error)
   is
      Vspace_Alive : Boolean;
      Vspace       : Aura.Vspace.V_Space_Ref;
      Va           : Interfaces.Unsigned_64;
   begin
      if Check_Valid (Prm_Cap) /= Ok then
         Status := Check_Valid (Prm_Cap);
         return;
      end if;
      if Owner = null then
         Status := Invalid_Argument;
         return;
      end if;
      Vspace := Owner.Vspace;
      Vspace_Alive := Vspace /= null;
      if not Vspace_Alive then
         Status := Host_Vspace_Destroyed;
         return;
      end if;
      Map_Resource_Into_Vspace (Vspace, Resource, Va_Hint, Va, Status);
      if Status /= Ok then
         return;
      end if;
      Construct_Secure_Binding
        (Header => (Epoch => 1, Min_Ring => Aura.Ring.Ring3, Rcu_Domain => null),
         Resource => Resource,
         Owner => Owner, Kernel_Tlb => Va, Result => Result);
      Status := Ok;
   end Secure_Binding_Create;

end Aura.Secure_Binding;
