--  AURA Kernel — aura-iommu.adb
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Hal; use Aura.Hal;

package body Aura.Iommu is

   use type Interfaces.Unsigned_32;

   function Check_Valid (Cap : Object_Bind_Prm_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   function Check_Valid (Cap : Iommu_Domain_Manage_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   function Check_Valid (Cap : Device_Object_Manage_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   function Check_Valid (Cap : Object_Read_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   procedure Resolve_External_Effect (Self : in out Iommu_Domain) is
   begin
      --  Платформенный вызов — граница платформы, идентичная
      --  unsafe-блоку Rust-версии.
      Hal_Iommu_Unmap_All (Self.Hw_Table_Root_Phys);
      Hal_Iommu_Tlb_Invalidate_All (Self.Domain_Id);
   end Resolve_External_Effect;

   procedure Construct_Iommu_Domain
     (Hw_Table_Root_Phys : Interfaces.Unsigned_64;
      Domain_Id           : Interfaces.Unsigned_32;
      Max_Mapped_Frames    : Interfaces.Unsigned_32;
      Result               : out Iommu_Domain_Manage_Ref)
   is
   begin
      Result :=
        (Object => new Iommu_Domain'
           (Header                => <>,
            Hw_Table_Root_Phys      => Hw_Table_Root_Phys,
            Domain_Id               => Domain_Id,
            Attached_Device_Count    => 0,
            Max_Mapped_Frames        => Max_Mapped_Frames,
            Mapped_Frame_Count       => 0,
            Mappings                 => <>));
   end Construct_Iommu_Domain;

   procedure Iommu_Domain_Create
     (Prm_Cap           : Object_Bind_Prm_Ref;
      Max_Mapped_Frames  : Interfaces.Unsigned_32;
      Result             : out Iommu_Domain_Manage_Ref;
      Status             : out Kernel_Error)
   is
      Domain_Id     : Interfaces.Unsigned_32;
      Alloc_Status  : Kernel_Error;
      Hw_Root       : Interfaces.Unsigned_64;
      Create_Status : Kernel_Error;
   begin
      Status := Check_Valid (Prm_Cap);
      if Status /= Ok then
         return;
      end if;

      Hal_Allocate_Iommu_Domain (Domain_Id, Alloc_Status);
      if Alloc_Status /= Ok then
         Status := Capacity_Exceeded;
         return;
      end if;

      Hal_Create_Iommu_Page_Table (Hw_Root, Create_Status);
      if Create_Status /= Ok then
         Status := Create_Status;
         return;
      end if;

      Construct_Iommu_Domain
        (Hw_Table_Root_Phys => Hw_Root,
         Domain_Id => Domain_Id,
         Max_Mapped_Frames => Max_Mapped_Frames,
         Result => Result);
      Status := Ok;
   end Iommu_Domain_Create;

   procedure Iommu_Attach_Device
     (Domain : Iommu_Domain_Manage_Ref;
      Device : Device_Object_Manage_Ref;
      Status : out Kernel_Error)
   is
      Attach_Status : Kernel_Error;
   begin
      Status := Check_Valid (Domain);
      if Status /= Ok then
         return;
      end if;
      Status := Check_Valid (Device);
      if Status /= Ok then
         return;
      end if;
      Hal_Iommu_Attach_Device
        (Domain.Object.Domain_Id, Device.Object.Platform_Id, Attach_Status);
      if Attach_Status /= Ok then
         Status := Attach_Status;
         return;
      end if;
      Domain.Object.Attached_Device_Count :=
        Domain.Object.Attached_Device_Count + 1;
      Status := Ok;
   end Iommu_Attach_Device;

   procedure Iommu_Map
     (Domain : Iommu_Domain_Manage_Ref;
      Frame  : Object_Read_Ref;
      Offset : Interfaces.Unsigned_64;
      Iova   : Interfaces.Unsigned_64;
      Length : Interfaces.Unsigned_64;
      Flags  : Iommu_Map_Flags;
      Status : out Kernel_Error)
   is
      use type Interfaces.Unsigned_64;
      Map_Status : Kernel_Error;
      Phys_Addr  : Interfaces.Unsigned_64;
   begin
      Status := Check_Valid (Domain);
      if Status /= Ok then
         return;
      end if;

      Status := Check_Valid (Frame);
      if Status /= Ok then
         return;
      end if;

      if Length = 0 then
         Status := Invalid_Argument;
         return;
      end if;

      if Domain.Object.Max_Mapped_Frames > 0
        and then Domain.Object.Mapped_Frame_Count = Domain.Object.Max_Mapped_Frames
      then
         Status := Capacity_Exceeded;
         return;
      end if;

      -- Simulate physical frame address
      Phys_Addr := 16#2000_0000# + Interfaces.Unsigned_64 (Frame.Object.Platform_Id) + Offset;

      Hal_Iommu_Map
        (Domain.Object.Hw_Table_Root_Phys,
         Iova,
         Phys_Addr,
         Length,
         Interfaces.Unsigned_32 (Flags),
         Map_Status);

      if Map_Status /= Ok then
         Status := Map_Status;
         return;
      end if;

      Domain.Object.Mapped_Frame_Count := Domain.Object.Mapped_Frame_Count + 1;
      Status := Ok;
   end Iommu_Map;

end Aura.Iommu;
