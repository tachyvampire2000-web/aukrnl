--  AURA Kernel — Hardware Abstraction Layer: reference-платформа.
--  Каждая подпрограмма либо выполняет реальную операцию через
--  защищённый примитив (Atomic_Compare_Exchange_U64), либо явно
--  задокументирована как intentional no-op с обоснованием.
--  SPDX-License-Identifier: GPL-2.0-only

with System.Storage_Elements;

package body Aura.Hal is

   --  Защищённый объект, реализующий атомарный CAS на однопроцессорной
   --  reference-платформе.  Потолочный приоритет System.Interrupt_Priority
   --  запрещает все прерывания (включая таймер) на время выполнения
   --  защищённой процедуры, что делает CAS действительно атомарным на
   --  однопроцессорном ядре.  На многопроцессорном ядре потребуется
   --  замена на аппаратную инструкцию (LOCK CMPXCHG / LL+SC).
   protected Atomic_Ops is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
      procedure Compare_And_Swap_U64
        (Target   : System.Address;
         Expected : Interfaces.Unsigned_64;
         Desired  : Interfaces.Unsigned_64;
         Success  : out Boolean);
   end Atomic_Ops;

   protected body Atomic_Ops is
      procedure Compare_And_Swap_U64
        (Target   : System.Address;
         Expected : Interfaces.Unsigned_64;
         Desired  : Interfaces.Unsigned_64;
         Success  : out Boolean)
      is
         use type Interfaces.Unsigned_64;
         Word : Interfaces.Unsigned_64
           with Address => Target, Import, Volatile;
      begin
         if Word = Expected then
            Word    := Desired;
            Success := True;
         else
            Success := False;
         end if;
      end Compare_And_Swap_U64;
   end Atomic_Ops;

   Next_Domain_Id : Interfaces.Unsigned_32 := 0;

   function Current_Cpu_Id return Natural is (0);

   procedure Platform_Irq_Ack (Irq : Natural) is
      pragma Unreferenced (Irq);
   begin
      --  Intentional no-op: reference-платформа работает на хост-ОС без
      --  прямого управления контроллером прерываний.  На реальном железе
      --  здесь должна быть запись в EOI-регистр APIC/GIC.
      null;
   end Platform_Irq_Ack;

   procedure Spin_Loop_Hint is
   begin
      --  Intentional no-op на reference-платформе; на x86 должен быть
      --  PAUSE, на ARM — YIELD.
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
      --  Intentional no-op: reference-платформа не управляет реальными
      --  таблицами страниц.  На реальном железе здесь должен быть обход
      --  и очистка PML4/PD/PT с последующим TLB-flush.
      Status := Ok;
   end Hal_Unmap_Segment;

   function Hal_Cpus_With_Vspace
     (Vspace : Aura.Vspace.V_Space_Ref) return Interfaces.Unsigned_64
   is
      pragma Unreferenced (Vspace);
   begin
      --  Intentional: reference-платформа однопроцессорная; единственный
      --  CPU никогда не регистрирует активный VSpace в аппаратном
      --  смысле.  На SMP возвращала бы битовую маску CPU с загруженным CR3.
      return 0;
   end Hal_Cpus_With_Vspace;

   procedure Hal_Send_Tlb_Shootdown_Ipi (Cpu : Interfaces.Unsigned_32) is
      pragma Unreferenced (Cpu);
   begin
      --  Intentional no-op: reference-платформа однопроцессорная, IPI
      --  некому слать.  На SMP должна быть запись в APIC ICR для
      --  конкретного CPU.
      null;
   end Hal_Send_Tlb_Shootdown_Ipi;

   procedure Hal_Local_Tlb_Flush
     (Va : Interfaces.Unsigned_64; Size : Interfaces.Unsigned_64)
   is
      pragma Unreferenced (Va, Size);
   begin
      --  Intentional no-op: reference-платформа не управляет TLB
      --  напрямую.  На x86 должен быть INVLPG или MOV CR3.
      null;
   end Hal_Local_Tlb_Flush;

   procedure Hal_Allocate_Iommu_Domain
     (Domain_Id : out Interfaces.Unsigned_32;
      Status    : out Kernel_Error)
   is
      use type Interfaces.Unsigned_32;
   begin
      --  Reference: монотонный счётчик — даёт уникальные ID для тестов,
      --  но не связан с реальным IOMMU hardware.  На реальном железе
      --  здесь должно быть выделение через драйвер IOMMU (Intel VT-d /
      --  AMD-Vi).
      Domain_Id      := Next_Domain_Id;
      Next_Domain_Id := Next_Domain_Id + 1;
      Status         := Ok;
   end Hal_Allocate_Iommu_Domain;

   procedure Hal_Create_Iommu_Page_Table
     (Root   : out Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
   begin
      --  Reference: возвращает фиксированный «нулевой» корень таблицы
      --  IOMMU, достаточный для тестов структуры.  На реальном железе
      --  здесь должно быть выделение физической страницы и инициализация
      --  root entry в структурах IOMMU.
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
      --  Intentional no-op: reference-платформа не управляет реальным
      --  IOMMU.  На реальном железе здесь должна быть запись в
      --  context-entry таблицу IOMMU для привязки устройства к домену.
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
      --  Intentional no-op: reference-платформа не управляет реальными
      --  IOMMU page tables.  На реальном железе здесь должна быть запись
      --  в SL page table (second-level), соответствующей Root_Phys.
      Status := Ok;
   end Hal_Iommu_Map;

   procedure Hal_Iommu_Unmap_All
     (Hw_Table_Root_Phys : Interfaces.Unsigned_64)
   is
      pragma Unreferenced (Hw_Table_Root_Phys);
   begin
      --  Intentional no-op: на реальном железе — обход SL page table и
      --  очистка всех записей с инвалидацией IOMMU TLB.
      null;
   end Hal_Iommu_Unmap_All;

   procedure Hal_Iommu_Tlb_Invalidate_All
     (Domain_Id : Interfaces.Unsigned_32)
   is
      pragma Unreferenced (Domain_Id);
   begin
      --  Intentional no-op: на реальном железе — запись Global-Command
      --  Register для Invalidation Wait Descriptor через Invalidation
      --  Queue (IQ) Intel VT-d.
      null;
   end Hal_Iommu_Tlb_Invalidate_All;

   --  Атомарный CAS на 64-битном слове по адресу.
   --  Реализован через защищённый объект с потолочным приоритетом
   --  Interrupt_Priority'Last, что запрещает вытеснение прерываниями на
   --  однопроцессорной reference-платформе и делает операцию атомарной.
   --  На реальном SMP-железе должна использоваться аппаратная инструкция
   --  (LOCK CMPXCHG для x86, LDREX+STREX для ARMv7, LDXR+STXR для
   --  ARMv8).
   procedure Atomic_Compare_Exchange_U64
     (Target   : System.Address;
      Expected : Interfaces.Unsigned_64;
      Desired  : Interfaces.Unsigned_64;
      Success  : out Boolean)
   is
   begin
      Atomic_Ops.Compare_And_Swap_U64 (Target, Expected, Desired, Success);
   end Atomic_Compare_Exchange_U64;

end Aura.Hal;
