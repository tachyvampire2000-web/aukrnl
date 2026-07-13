--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

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
   begin
      --  OPEN (портировано из todo!() Rust-версии, §17): тело не
      --  реализовано ни в Rust-документе, ни здесь. Семь шагов плана
      --  переносятся как комментарий:
      --    1. Cap_Manage на Domain.
      --    2. Эпохи Frame (Check_Valid).
      --    3. Границы Offset+Length.
      --    4. Attached_Device_Count > 0 (если не Allow_Unattached).
      --    5. Max_Mapped_Frames.
      --    6. Запись в HW таблицы.
      --    7. TLB инвалидация.
      Status := Not_Supported;
   end Iommu_Map;

end Aura.Iommu;
