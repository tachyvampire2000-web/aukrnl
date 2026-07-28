--  Тело reference-платформы: honest-заглушки. Каждая подпрограмма либо
--  тривиально корректна на одноядерной reference-конфигурации, либо
--  возвращает Not_Supported, не имитируя успех.

with System.Machine_Code;

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
      Root   := 16#FFFF_E000_0000_0000#;
      Status := Ok;
   end Hal_Create_Iommu_Page_Table;

   procedure Hal_Iommu_Attach_Device
     (Domain_Id   : Interfaces.Unsigned_32;
      Platform_Id : Interfaces.Unsigned_32;
      Status      : out Kernel_Error)
   is
      pragma Unreferenced (Domain_Id, Platform_Id);
   begin
      Status := Ok;
   end Hal_Iommu_Attach_Device;

   procedure Hal_Iommu_Map
     (Root_Phys : Interfaces.Unsigned_64;
      Iova      : Interfaces.Unsigned_64;
      Phys      : Interfaces.Unsigned_64;
      Size      : Interfaces.Unsigned_64;
      Flags     : Interfaces.Unsigned_32;
      Status    : out Kernel_Error)
   is
      pragma Unreferenced (Root_Phys, Iova, Phys, Size, Flags);
   begin
      Status := Ok;
   end Hal_Iommu_Map;

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
      use type Interfaces.Unsigned_8;
      use System.Machine_Code;

      Word : Interfaces.Unsigned_64
        with Address => Target, Import, Volatile;

      Actual_Expected : aliased Interfaces.Unsigned_64 := Expected;
      Result_ZF       : Interfaces.Unsigned_8;
   begin
      Asm
        (Template => "lock; cmpxchgq %2, %0; setz %1",
         Outputs  =>
           [Interfaces.Unsigned_64'Asm_Output ("=m", Word),
            Interfaces.Unsigned_8'Asm_Output ("=q", Result_ZF)],
         Inputs   =>
           [Interfaces.Unsigned_64'Asm_Input ("r", Desired),
            Interfaces.Unsigned_64'Asm_Input ("a", Actual_Expected)],
         Clobber  => "cc, memory",
         Volatile => True);

      Success := (Result_ZF /= 0);
   end Atomic_Compare_Exchange_U64;

end Aura.Hal;
