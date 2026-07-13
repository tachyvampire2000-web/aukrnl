--  Тело reference-платформы: honest-заглушки. Каждая подпрограмма либо
--  тривиально корректна на одноядерной reference-конфигурации, либо
--  возвращает Not_Supported, не имитируя успех.

package body Aura.Hal is

   Next_Domain_Id : Interfaces.Unsigned_32 := 0;

   function Current_Cpu_Id return Natural is (0);

   procedure Platform_Irq_Ack (Irq : Natural) is
      pragma Unreferenced (Irq);
   begin
      null;
   end Platform_Irq_Ack;

   procedure Spin_Loop_Hint is
   begin
      null;
   end Spin_Loop_Hint;

   procedure Hal_Unmap_Segment
     (Root   : Interfaces.Unsigned_64;
      Va     : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
      pragma Unreferenced (Root, Va, Size);
   begin
      Status := Ok;
   end Hal_Unmap_Segment;

   function Hal_Cpus_With_Vspace
     (Vspace : Aura.Vspace.V_Space_Ref) return Interfaces.Unsigned_64
   is
      pragma Unreferenced (Vspace);
   begin
      return 0;
   end Hal_Cpus_With_Vspace;

   procedure Hal_Send_Tlb_Shootdown_Ipi (Cpu : Interfaces.Unsigned_32) is
      pragma Unreferenced (Cpu);
   begin
      null;
   end Hal_Send_Tlb_Shootdown_Ipi;

   procedure Hal_Local_Tlb_Flush
     (Va : Interfaces.Unsigned_64; Size : Interfaces.Unsigned_64)
   is
      pragma Unreferenced (Va, Size);
   begin
      null;
   end Hal_Local_Tlb_Flush;

   procedure Hal_Allocate_Iommu_Domain
     (Domain_Id : out Interfaces.Unsigned_32;
      Status    : out Kernel_Error)
   is
      use type Interfaces.Unsigned_32;
   begin
      Domain_Id      := Next_Domain_Id;
      Next_Domain_Id := Next_Domain_Id + 1;
      Status         := Ok;
   end Hal_Allocate_Iommu_Domain;

   procedure Hal_Create_Iommu_Page_Table
     (Root   : out Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
   begin
      Root   := 0;
      Status := Not_Supported;
   end Hal_Create_Iommu_Page_Table;

   procedure Hal_Iommu_Attach_Device
     (Domain_Id   : Interfaces.Unsigned_32;
      Platform_Id : Interfaces.Unsigned_32;
      Status      : out Kernel_Error)
   is
      pragma Unreferenced (Domain_Id, Platform_Id);
   begin
      Status := Not_Supported;
   end Hal_Iommu_Attach_Device;

   procedure Hal_Iommu_Unmap_All
     (Hw_Table_Root_Phys : Interfaces.Unsigned_64)
   is
      pragma Unreferenced (Hw_Table_Root_Phys);
   begin
      null;
   end Hal_Iommu_Unmap_All;

   procedure Hal_Iommu_Tlb_Invalidate_All
     (Domain_Id : Interfaces.Unsigned_32)
   is
      pragma Unreferenced (Domain_Id);
   begin
      null;
   end Hal_Iommu_Tlb_Invalidate_All;

   procedure Atomic_Compare_Exchange_U64
     (Target   : System.Address;
      Expected : Interfaces.Unsigned_64;
      Desired  : Interfaces.Unsigned_64;
      Success  : out Boolean)
   is
      use type Interfaces.Unsigned_64;
      Word : Interfaces.Unsigned_64
        with Address => Target, Import, Volatile;
   begin
      --  Reference-платформа однопроцессорная — CAS вырождается в
      --  сравнение и запись под запретом вытеснения на этом уровне.
      if Word = Expected then
         Word    := Desired;
         Success := True;
      else
         Success := False;
      end if;
   end Atomic_Compare_Exchange_U64;

end Aura.Hal;
