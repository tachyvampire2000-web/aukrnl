--  AURA Kernel — IOMMU управление мандатами отображения.
--  П.21 дорожной карты: физический адрес больше НЕ вычисляется по
--  формуле 16#2000_0000# + Platform_Id + Offset.  Теперь физический
--  адрес берётся из Prm_Resource_Set.Mmio_Base_Phys — реального поля
--  ресурсного набора, заполненного при инициализации устройства.
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Hal; use Aura.Hal;

package body Aura.Iommu is

   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_32;

   function Check_Valid (Cap : Iommu_Domain_Cap) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   procedure Iommu_Domain_Create
     (Rs      : Aura.Driver.Prm_Resource_Set_Ref;
      Result  : out Iommu_Domain_Cap;
      Status  : out Kernel_Error)
   is
      Domain_Id : Interfaces.Unsigned_32;
      Root_Phys : Interfaces.Unsigned_64;
      Dom       : Iommu_Domain_Ref;
      Hal_St    : Kernel_Error;
   begin
      if Rs = null then
         Result := (Object => null);
         Status := Bad_Cap;
         return;
      end if;
      Hal_Allocate_Iommu_Domain (Domain_Id, Hal_St);
      if Hal_St /= Ok then
         Result := (Object => null);
         Status := Hal_St;
         return;
      end if;
      Hal_Create_Iommu_Page_Table (Root_Phys, Hal_St);
      if Hal_St /= Ok then
         Result := (Object => null);
         Status := Hal_St;
         return;
      end if;
      Hal_Iommu_Attach_Device (Domain_Id, Rs.Platform_Id, Hal_St);
      if Hal_St /= Ok then
         Result := (Object => null);
         Status := Hal_St;
         return;
      end if;
      Dom := new Iommu_Domain'
        (Header        => <>,
         Domain_Id     => Domain_Id,
         Hw_Table_Root => Root_Phys,
         Resource_Set  => Rs);
      Result := (Object => Dom);
      Status := Ok;
   end Iommu_Domain_Create;

   --  П.21 дорожной карты: физический адрес берётся из
   --  Dom.Resource_Set.Mmio_Base_Phys (реальное поле аппаратного ресурса),
   --  а не из формульного вычисления.
   procedure Iommu_Map
     (Domain  : Iommu_Domain_Cap;
      Iova    : Interfaces.Unsigned_64;
      Offset  : Interfaces.Unsigned_64;
      Size    : Interfaces.Unsigned_64;
      Flags   : Interfaces.Unsigned_32;
      Status  : out Kernel_Error)
   is
      Dom  : Iommu_Domain_Ref renames Domain.Object;
      Phys : Interfaces.Unsigned_64;
   begin
      Status := Check_Valid (Domain);
      if Status /= Ok then return; end if;

      --  Физический адрес = база MMIO из ресурсного набора + смещение.
      --  Mmio_Base_Phys установлен при Driver_Init из данных ACPI/DeviceTree.
      if Dom.Resource_Set = null then
         Status := Not_Supported;
         return;
      end if;
      Phys := Dom.Resource_Set.Mmio_Base_Phys;
      if Phys = 0 then
         --  Устройство без MMIO (чисто port-mapped): IOMMU-отображение
         --  не применимо.
         Status := Invalid_Argument;
         return;
      end if;
      if Offset > Dom.Resource_Set.Mmio_Size or else
        Size > Dom.Resource_Set.Mmio_Size - Offset
      then
         Status := Overflow;
         return;
      end if;
      Phys := Phys + Offset;

      Hal_Iommu_Map (Dom.Hw_Table_Root, Iova, Phys, Size, Flags, Status);
      if Status /= Ok then return; end if;
      Hal_Iommu_Tlb_Invalidate_All (Dom.Domain_Id);
      Status := Ok;
   end Iommu_Map;

   procedure Iommu_Unmap_All (Domain : Iommu_Domain_Cap;
                               Status : out Kernel_Error) is
      Dom : Iommu_Domain_Ref renames Domain.Object;
   begin
      Status := Check_Valid (Domain);
      if Status /= Ok then return; end if;
      Hal_Iommu_Unmap_All (Dom.Hw_Table_Root);
      Hal_Iommu_Tlb_Invalidate_All (Dom.Domain_Id);
      Status := Ok;
   end Iommu_Unmap_All;

   procedure Iommu_Domain_Destroy
     (Domain : in out Iommu_Domain_Cap;
      Status : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Domain);
      if Status /= Ok then return; end if;
      Hal_Iommu_Unmap_All (Domain.Object.Hw_Table_Root);
      Hal_Iommu_Tlb_Invalidate_All (Domain.Object.Domain_Id);
      declare
         procedure Free is new Ada.Unchecked_Deallocation
           (Iommu_Domain, Iommu_Domain_Ref);
         D : Iommu_Domain_Ref := Domain.Object;
      begin
         Free (D);
      end;
      Domain := (Object => null);
      Status := Ok;
   end Iommu_Domain_Destroy;

end Aura.Iommu;
