--  AURA Kernel — aura-iommu.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Aura.Ticket_Lock;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Ada.Containers.Bounded_Vectors;
with Interfaces;

package Aura.Iommu is

   pragma SPARK_Mode (Off);

   type Iommu_Map_Flags is mod 2 ** 32;

   type Iommu_Mapping is record
      Iova  : Interfaces.Unsigned_64 := 0;
      Phys  : Interfaces.Unsigned_64 := 0;
      Size  : Interfaces.Unsigned_64 := 0;
      Flags : Iommu_Map_Flags := 0;
   end record;

   type Iommu_Domain;
   type Iommu_Domain_Access is access all Iommu_Domain;

   --  Устройство с точки зрения IOMMU: платформенный идентификатор
   --  (BDF на PCIe) плюс стандартный заголовок объекта ядра.
   type Device_Object is limited record
      Header      : Object_Header;
      Platform_Id : Interfaces.Unsigned_32 := 0;
   end record;

   type Device_Object_Access is access all Device_Object;

   --  Мандаты (рантайм-представление прав — см. §1 порта).
   type Object_Bind_Prm_Ref is record
      Object : Device_Object_Access;
   end record;

   type Iommu_Domain_Manage_Ref is record
      Object : Iommu_Domain_Access;
   end record;

   type Device_Object_Manage_Ref is record
      Object : Device_Object_Access;
   end record;

   type Object_Read_Ref is record
      Object : Device_Object_Access;
   end record;

   function Check_Valid (Cap : Object_Bind_Prm_Ref) return Kernel_Error;
   function Check_Valid (Cap : Iommu_Domain_Manage_Ref) return Kernel_Error;
   function Check_Valid (Cap : Device_Object_Manage_Ref) return Kernel_Error;
   function Check_Valid (Cap : Object_Read_Ref) return Kernel_Error;

   Iommu_Mapping_Max : constant := 64;

   package Iommu_Mapping_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Iommu_Mapping);
   subtype Iommu_Mapping_Vector is Iommu_Mapping_Vectors.Vector (Iommu_Mapping_Max);
   package Iommu_Mapping_Locks is new Aura.Ticket_Lock
     (Iommu_Mapping_Vector);

   type Iommu_Domain is limited record
      Header                : Object_Header;
      Hw_Table_Root_Phys      : Interfaces.Unsigned_64;
      Domain_Id               : Interfaces.Unsigned_32;
      Attached_Device_Count    : aliased Interfaces.Unsigned_32;
      Max_Mapped_Frames        : Interfaces.Unsigned_32;
      Mapped_Frame_Count       : aliased Interfaces.Unsigned_32;
      Mappings                 : Iommu_Mapping_Locks.Instance;
   end record
     with Volatile;

   --  Реализует Has_External_Effect (§1.7.0 порта).

   --  T66: явное создание Iommu_Domain как capability object. Требует
   --  мандат с Bind_Prm — только PRM-уровень может создавать домены.
   --  Возвращает мандат Manage — владелец может делегировать подмандаты.
   procedure Iommu_Domain_Create
     (Prm_Cap           : Object_Bind_Prm_Ref;  --  требует Bind_Prm
      Max_Mapped_Frames  : Interfaces.Unsigned_32;
      Result             : out Iommu_Domain_Manage_Ref;
      Status             : out Kernel_Error);


   --  T66: привязать устройство к домену через capability.
   --  Device_Object.Iommu_Domain_Cap теперь явный мандат, не опциональный
   --  Erased_Cap.
   procedure Iommu_Attach_Device
     (Domain : Iommu_Domain_Manage_Ref;  --  требует Manage
      Device : Device_Object_Manage_Ref;  --  требует Manage
      Status : out Kernel_Error);


   procedure Iommu_Map
     (Domain : Iommu_Domain_Manage_Ref;   --  требует Manage
      Frame  : Object_Read_Ref;            --  требует Read
      Offset : Interfaces.Unsigned_64;
      Iova   : Interfaces.Unsigned_64;
      Length : Interfaces.Unsigned_64;
      Flags  : Iommu_Map_Flags;
      Status : out Kernel_Error);


end Aura.Iommu;
