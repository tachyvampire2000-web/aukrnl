--  AURA — Hardware Abstraction Layer (граница платформы).
--  Здесь собраны все точки, где ядро пересекает границу с конкретным
--  оборудованием: TLB, IPI, IOMMU, контроллер прерываний. Реализации в
--  теле пакета — переносимые заглушки reference-платформы; порт на
--  конкретную архитектуру заменяет тело, не трогая спецификацию.

with System;
with Interfaces;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Vspace;

package Aura.Hal is

   pragma SPARK_Mode (Off);

   Max_Cpus : constant := 256;

   function Current_Cpu_Id return Natural;

   procedure Platform_Irq_Ack (Irq : Natural);

   procedure Spin_Loop_Hint;

   --  Снять маппинг сегмента [Va, Va + Size) в таблице страниц Root.
   procedure Hal_Unmap_Segment
     (Root   : Interfaces.Unsigned_64;
      Va     : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Status : out Kernel_Error);

   --  Битовая маска CPU, на которых Vspace сейчас активен.
   function Hal_Cpus_With_Vspace
     (Vspace : Aura.Vspace.V_Space_Ref) return Interfaces.Unsigned_64;

   procedure Hal_Send_Tlb_Shootdown_Ipi (Cpu : Interfaces.Unsigned_32);

   procedure Hal_Local_Tlb_Flush
     (Va : Interfaces.Unsigned_64; Size : Interfaces.Unsigned_64);

   procedure Hal_Allocate_Iommu_Domain
     (Domain_Id : out Interfaces.Unsigned_32;
      Status    : out Kernel_Error);

   procedure Hal_Create_Iommu_Page_Table
     (Root   : out Interfaces.Unsigned_64;
      Status : out Kernel_Error);

   procedure Hal_Iommu_Attach_Device
     (Domain_Id   : Interfaces.Unsigned_32;
      Platform_Id : Interfaces.Unsigned_32;
      Status      : out Kernel_Error);

   procedure Hal_Iommu_Unmap_All
     (Hw_Table_Root_Phys : Interfaces.Unsigned_64);

   procedure Hal_Iommu_Tlb_Invalidate_All
     (Domain_Id : Interfaces.Unsigned_32);

   --  CAS на 64-битном слове по адресу — эквивалент
   --  AtomicU64::compare_exchange в Rust-версии.
   procedure Atomic_Compare_Exchange_U64
     (Target   : System.Address;
      Expected : Interfaces.Unsigned_64;
      Desired  : Interfaces.Unsigned_64;
      Success  : out Boolean);

end Aura.Hal;
