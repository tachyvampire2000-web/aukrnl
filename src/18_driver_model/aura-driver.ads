--  AURA Kernel — aura-driver.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Aura.Ring; use Aura.Ring;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights; use Aura.Rights;
with Aura.Namespace;
with System;
with Interfaces;
with Ada.Strings.Bounded;

package Aura.Driver is

   pragma SPARK_Mode (On);

   package Name_Strings renames Aura.Namespace.Name_Strings;


   type Device_Object_Ref is access all Integer; -- Placeholder
   type Device_Object_Ref_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Device_Object_Ref;
         when False => null;
      end case;
   end record;

   type Erased_Cap is access all Integer; -- Placeholder
   type Erased_Cap_Access is access all Erased_Cap;
   type Erased_Cap_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Erased_Cap;
         when False => null;
      end case;
   end record;

   type Reincarnation_Contract_Ref_Option (Present : Boolean := False) is record
      case Present is
         when True  => Addr : System.Address; -- Placeholder
         when False => null;
      end case;
   end record;

   type Notification_Read_Ref is access all Integer; -- Placeholder
   type Untyped_Region_Ref is access all Integer; -- Placeholder
   type Timer_Object_Read_Ref is access all Integer; -- Placeholder

   type Prm_Resource_Set_Manage_Ref is access all Integer; -- Placeholder
   type Process_Context_Ref is access all Integer; -- Placeholder

   type Execution_Context is access all Integer; -- Placeholder
   type Phys_Addr_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Interfaces.Unsigned_64;
         when False => null;
      end case;
   end record;

   type Page_Table_Result (Ok : Boolean := True) is record
      case Ok is
         when True  => Root : Interfaces.Unsigned_64;
         when False => Status : Kernel_Error;
      end case;
   end record;

   type V_Space is access all Integer; -- Placeholder
   type Byte_Array is array (Interfaces.Unsigned_64 range <>) of Interfaces.Unsigned_8;
   type Copy_Result (Ok : Boolean := True) is record
      case Ok is
         when True  => Bytes_Copied : Interfaces.Unsigned_64;
         when False => Status : Kernel_Error;
      end case;
   end record;

   type Validate_Mmio_Result (Ok : Boolean := True) is record
      case Ok is
         when True  => null;
         when False => Status : Kernel_Error;
      end case;
   end record;

   type Validate_Port_Io_Result (Ok : Boolean := True) is record
      case Ok is
         when True  => null;
         when False => Status : Kernel_Error;
      end case;
   end record;

   type Rdrand_Result (Ok : Boolean := True) is record
      case Ok is
         when True  => Value : Interfaces.Unsigned_64;
         when False => Status : Kernel_Error;
      end case;
   end record;

   type Msi_X_Alloc_Result (Ok : Boolean := True) is record
      case Ok is
         when True  => Vector : Interfaces.Unsigned_16;
         when False => Status : Kernel_Error;
      end case;
   end record;

   type Iommu_Domain_Alloc_Result (Ok : Boolean := True) is record
      case Ok is
         when True  => Domain_Id : Interfaces.Unsigned_32;
         when False => Status : Kernel_Error;
      end case;
   end record;


   type Device_Class is
     (Unknown_Class, Block_Storage, Network, Display, Input_Hid, Bus,
      Timer_Class, Platform_Other);

   type Device_State is
     (Enumerated, Bound, Active, Faulted, Removed);

   type Device_State_Result (Ok : Boolean := True) is record
      case Ok is
         when True  => Value : Device_State;
         when False => null;
      end case;
   end record;
   for Device_State use
     (Enumerated => 0, Bound => 1, Active => 2, Faulted => 3, Removed => 4);
   for Device_State'Size use 8;

   function Device_State_From_U8
     (V : Interfaces.Unsigned_8) return Device_State_Result
   is
     (case V is
        when 0 => (Ok => True, Value => Enumerated),
        when 1 => (Ok => True, Value => Bound),
        when 2 => (Ok => True, Value => Active),
        when 3 => (Ok => True, Value => Faulted),
        when 4 => (Ok => True, Value => Removed),
        when others => (Ok => False));
        --  Faulted как значение-заглушка при Ok = False — вызывающий
        --  обязан проверить Ok, не читать Value напрямую при ошибке;
        --  эквивалент Rust Result<DeviceState, KernelError>.

   type Device_Object is limited record
      Header                : Object_Header;
      Class                  : Device_Class;
      State                   : aliased Interfaces.Unsigned_8;  --  хранится
                                  --  как байт для атомарного доступа,
                                  --  идентично Rust AtomicU8
      Platform_Id             : Interfaces.Unsigned_64;
      Parent                  : Device_Object_Ref_Option;
      --  Указатель, обновляемый атомарно чтобы Rebind_Driver_Caps мог
      --  атомарно обновить при перезапуске. Null = мандат не выдан
      --  (состояние до Driver_Load).
      Driver_Endpoint_Cap      : Erased_Cap_Access;
      Iommu_Domain_Cap          : Erased_Cap_Option;  --  не меняется
                                   --  после Driver_Load
      Prm_Resource_Set_Cap       : Erased_Cap_Access;
      Supervision_Contract        : Reincarnation_Contract_Ref_Option;
   end record
     with Volatile;

   function State (Self : Device_Object) return Device_State
     with Volatile_Function;
   procedure Set_State (Self : in out Device_Object; S : Device_State);


   Driver_Manifest_Max_Classes : constant := 8;

   type Device_Class_Array is array (1 .. Driver_Manifest_Max_Classes)
     of Device_Class;

   Driver_Entry_Point_Path_Max : constant := 255;

   type Prm_Resource_Class_Mask is mod 2 ** 32;

   type Driver_Manifest is record
      Abi_Version            : Interfaces.Unsigned_32;
      Supported_Classes       : Device_Class_Array;
      Supported_Class_Count    : Interfaces.Unsigned_32;
      Match_Platform_Id_Mask    : Interfaces.Unsigned_64;
      --  Bounded_String для no_std-совместимого динамического пути —
      --  эквивалент Rust Box<str>.
      Entry_Point_Path          : Name_Strings.Bounded_String;
      Required_Prm_Resources     : Prm_Resource_Class_Mask;
      Requires_Iommu_Domain       : Boolean;
   end record;
   Interrupt_Line : constant Prm_Resource_Class_Mask := 16#01#;
   Mmio_Region    : constant Prm_Resource_Class_Mask := 16#02#;
   Port_Io_Range  : constant Prm_Resource_Class_Mask := 16#04#;
   Timer_Channel  : constant Prm_Resource_Class_Mask := 16#08#;
   Dma_Channel    : constant Prm_Resource_Class_Mask := 16#10#;
   Msi_X_Vector   : constant Prm_Resource_Class_Mask := 16#20#;
      --  T74: MSI-X interrupt vector (PCIe)

   Msi_X_Max_Vectors : constant := 2048;  -- PCIe spec maximum

   --  T74: дескриптор одного MSI-X вектора.
   type Msi_X_Vector_Desc is record
      Vector_Index : Interfaces.Unsigned_16;  -- индекс в таблице MSI-X
                                                -- устройства
      Cpu_Affinity : Interfaces.Unsigned_32;   -- целевой CPU для этого
                                                 -- вектора
      Allocated    : Boolean;
   end record;

   type Msi_X_Vector_Array is array (0 .. Msi_X_Max_Vectors - 1)
     of Msi_X_Vector_Desc;

   type Msi_X_Vector_Array_Option (Present : Boolean := False) is record
      case Present is
         when True  => Vectors : Msi_X_Vector_Array;
         when False => null;
      end case;
   end record;

   type Prm_Resource_Set is limited record
      Header               : Object_Header;
      Owning_Device         : Device_Object_Ref;
      Granted_Classes_Mask   : Prm_Resource_Class_Mask;
      --  T74: MSI-X вектора выделяются при Driver_Load, хранятся здесь.
      --  Present = False если Msi_X_Vector не в Granted_Classes_Mask.
      Msi_X_Vectors           : Msi_X_Vector_Array_Option;
   end record
     with Volatile;

   --  Реализует Has_External_Effect (§1.7.0 порта).

   --  Enum вместо Capability по dyn-объекту — dispatch по типу
   --  несовместим с фиксированным представлением записи (эквивалент
   --  Rust "dyn несовместим с Sized").
   type Prm_Resource_Cap_Kind is
     (Interrupt_Line_Cap, Mmio_Region_Cap, Timer_Channel_Cap,
      Msi_X_Vector_Cap);

   type Prm_Resource_Cap (Kind : Prm_Resource_Cap_Kind := Interrupt_Line_Cap)
     is record
        case Kind is
           when Interrupt_Line_Cap =>
              Interrupt_Notif : Notification_Read_Ref;  --  требует Read
           when Mmio_Region_Cap =>
              --  Единственное реальное место использования комбинации
              --  Read+Write как единого мандата — см. port-02/§1.4 порта
              --  (Read_Write константа).
              Mmio_Cap : Untyped_Region_Ref;  --  требует Read_Write
           when Timer_Channel_Cap =>
              Timer_Cap : Timer_Object_Read_Ref;  --  требует Read
           when Msi_X_Vector_Cap =>
              --  T74: Notification + vector_index
              Msi_X_Notif  : Notification_Read_Ref;  --  требует Read
              Msi_X_Index  : Interfaces.Unsigned_16;
        end case;
     end record;

   procedure Prm_Request_Resource
     (Resource_Set      : Prm_Resource_Set;  --  Placeholder, requires Manage
      Class             : Prm_Resource_Class_Mask;
      Resource_Selector  : Interfaces.Unsigned_64;
      Result            : out Prm_Resource_Cap;
      Status            : out Kernel_Error);

   --  Перезапуск процесса драйвера после обнаружения краша/зависания
   --  через Supervisor_Tick. Отдельный путь от Supervisor_Tick (§16.2
   --  порта) потому что:
   --  1. Rebind_Namespace_Mounts восстанавливает только Ns_Mount-журнал —
   --     три мандата из шага 7 Driver_Load (Target, Prm_Resource_Set,
   --     Driver_Endpoint_Cap) там не писались.
   --  2. Device_State управляется драйверным путём, не общим
   --     supervisor-путём.

   --  Внутренний шаг: повтор части шагов 7-8 Driver_Load для нового
   --  процесса. Не новый системный вызов — внутренняя функция ядра.
   --  См. port-08 (журнал изменений порта): Rust dyn-трейт переносится
   --  через Ada tagged type с абстрактными примитивами. Единственное
   --  отличие в стоимости — Ada dispatching-вызов через tag аналогичен
   --  Rust vtable-вызову через &dyn Trait по стоимости (один косвенный
   --  переход), так что здесь это не ослабление, а прямой структурный
   --  аналог, не только концептуальный.
   type Hardware_Abstraction is interface;

   function Iommu_Map
     (Self : Hardware_Abstraction; Root, Iova, Phys, Len : Interfaces.Unsigned_64;
      Flags : Interfaces.Unsigned_32) return Kernel_Error is abstract;
   procedure Iommu_Tlb_Invalidate
     (Self : Hardware_Abstraction; Domain_Id : Interfaces.Unsigned_32) is abstract;
   procedure Irq_Ack (Self : Hardware_Abstraction; Irq : Interfaces.Unsigned_32)
     is abstract;
   procedure Send_Reschedule_Ipi
     (Self : Hardware_Abstraction; Cpu : Interfaces.Unsigned_32) is abstract;
   procedure Save_Context_And_Yield (Self : Hardware_Abstraction) is abstract
     with No_Return;
   procedure Restore_Context
     (Self : Hardware_Abstraction; Ctx : Execution_Context) is abstract
     with No_Return;
   procedure Wait_For_Interrupt (Self : Hardware_Abstraction) is abstract;
   function Page_Table_Lookup
     (Self : Hardware_Abstraction; Root, Va : Interfaces.Unsigned_64)
      return Phys_Addr_Option is abstract;
   function Create_Page_Table
     (Self : Hardware_Abstraction) return Page_Table_Result is abstract;
   function Map_Segment
     (Self : Hardware_Abstraction; Root, Va, Pa, Size : Interfaces.Unsigned_64;
      Flags : Interfaces.Unsigned_32) return Kernel_Error is abstract;
   function Unmap_Segment
     (Self : Hardware_Abstraction; Root, Va, Size : Interfaces.Unsigned_64)
      return Kernel_Error is abstract;
   procedure Send_Tlb_Shootdown_Ipi
     (Self : Hardware_Abstraction; Cpu : Interfaces.Unsigned_32) is abstract;
   procedure Local_Tlb_Flush
     (Self : Hardware_Abstraction; Va, Size : Interfaces.Unsigned_64) is abstract;
   function Cpus_With_Vspace
     (Self : Hardware_Abstraction; Vspace : V_Space) return Interfaces.Unsigned_64
     is abstract;
   function Copy_From_User
     (Self : Hardware_Abstraction; Dst : in out Byte_Array; Src_Va : Interfaces.Unsigned_64)
      return Copy_Result is abstract;
   function Validate_Irq
     (Self : Hardware_Abstraction; Irq : Interfaces.Unsigned_32)
      return Kernel_Error is abstract;
   function Validate_Mmio
     (Self : Hardware_Abstraction; Base : Interfaces.Unsigned_64;
      Size : Interfaces.Unsigned_32) return Validate_Mmio_Result is abstract;
   function Validate_Timer
     (Self : Hardware_Abstraction; Timer_Id : Interfaces.Unsigned_32)
      return Kernel_Error is abstract;
   function Validate_Port_Io
     (Self : Hardware_Abstraction; Port : Interfaces.Unsigned_16)
      return Validate_Port_Io_Result is abstract;
   function Validate_Dma
     (Self : Hardware_Abstraction; Channel : Interfaces.Unsigned_32)
      return Kernel_Error is abstract;
   function Rdrand
     (Self : Hardware_Abstraction) return Rdrand_Result is abstract;
   --  T74: выделить MSI-X вектор для устройства.
   function Allocate_Msi_X_Vector
     (Self : Hardware_Abstraction; Platform_Id : Interfaces.Unsigned_64;
      Cpu : Interfaces.Unsigned_32) return Msi_X_Alloc_Result is abstract;
   --  T74: освободить MSI-X вектор при уничтожении Prm_Resource_Set.
   procedure Release_Msi_X_Vector
     (Self : Hardware_Abstraction; Platform_Id : Interfaces.Unsigned_64;
      Vector_Index : Interfaces.Unsigned_16) is abstract;
   --  T66: выделить новый IOMMU домен (hardware domain ID).
   function Allocate_Iommu_Domain
     (Self : Hardware_Abstraction) return Iommu_Domain_Alloc_Result is abstract;
   --  T66: привязать устройство к домену на уровне IOMMU hardware.
   function Iommu_Attach_Device
     (Self : Hardware_Abstraction; Domain_Id : Interfaces.Unsigned_32;
      Platform_Id : Interfaces.Unsigned_64) return Kernel_Error is abstract;

   type Reincarnation_Contract is record
      Supervised : Process_Context_Ref;
      Respawn_Cap : Erased_Cap;
      Restart_Count : Interfaces.Unsigned_32;
      Last_Heartbeat_Tick : Interfaces.Unsigned_64;
   end record;

   procedure Respawn_Driver_Process
     (Target   : in out Device_Object;
      Contract : in out Reincarnation_Contract;
      Now      : Interfaces.Unsigned_64);

   --  Глобальный экземпляр, инициализируется при старте платформой —
   --  эквивалент Rust `static HAL: &'static dyn HardwareAbstraction`.
   Hal : access Hardware_Abstraction'Class;

end Aura.Driver;
